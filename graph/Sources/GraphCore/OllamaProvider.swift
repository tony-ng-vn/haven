import Foundation

/// The outer Ollama /api/generate response envelope: only "response" matters here, a STRING
/// that itself contains the model's own JSON (per Ollama's API, requested via format:"json").
private struct OllamaGenerateResponse: Decodable {
    let response: String
}

/// The model's own JSON, embedded inside OllamaGenerateResponse.response as text, per the
/// exact shape GuessPrompt asks for.
private struct ModelGuessJSON: Decodable {
    let name: String
    let description: String?
}

/// Talks to a local Ollama server's /api/generate endpoint. Default, zero-cost, zero-data-
/// leaves-the-machine provider per PLAN.md; a cloud provider is explicit opt-in and out of
/// scope entirely for this step.
public struct OllamaProvider: NameGuessProvider {
    public let baseURL: URL
    public let model: String
    private let session: URLSession

    /// Defaults to an ephemeral session, never .shared: the prompt this sends contains real
    /// message snippets (see GuessPrompt), and URLSession.shared is backed by an on-disk
    /// URLCache plus persistent cookie storage -- exactly the kind of "written to disk" path
    /// this step's privacy discipline forbids for message-derived text. The injectable
    /// `session:` param exists so tests can substitute a URLProtocol-stubbed session.
    public init(
        baseURL: URL = URL(string: "http://localhost:11434")!,
        model: String = "llama3.2",
        session: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    public func guess(prompt: String) async throws -> NameGuess {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Belt and suspenders alongside the ephemeral session itself: never let this specific
        // request read or write any cache entry.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false, "format": "json"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            // Any transport-level failure (connection refused being the common real case for
            // a local Ollama server that is not running) is unreachable, not a bad response:
            // there was never a response to be bad.
            throw NameGuessError.providerUnreachable
        }

        guard let outer = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: data),
              let innerData = outer.response.data(using: .utf8),
              let inner = try? JSONDecoder().decode(ModelGuessJSON.self, from: innerData),
              !inner.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NameGuessError.badResponse
        }

        return NameGuess(name: inner.name, detail: inner.description)
    }
}
