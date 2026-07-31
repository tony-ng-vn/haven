import XCTest
@testable import GraphCore

final class OllamaProviderTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastRequestBody = nil
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // A free function, not an instance method: it must be callable from inside a @Sendable
    // stub-handler closure without capturing `self` (XCTestCase is not Sendable).
    private func ollamaResponse(_ innerJSON: String) -> Data { Self.ollamaResponse(innerJSON) }

    private static func ollamaResponse(_ innerJSON: String) -> Data {
        let outer: [String: Any] = ["model": "llama3.2", "response": innerJSON, "done": true]
        return try! JSONSerialization.data(withJSONObject: outer)
    }

    func testRequestURLAndBodyShape() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.ollamaResponse("{\"name\": \"Test\", \"description\": \"A person\"}"))
        }
        let provider = OllamaProvider(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "llama3.2",
            session: stubbedSession()
        )

        _ = try await provider.guess(prompt: "some prompt text")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/generate")
        XCTAssertEqual(request.httpMethod, "POST")

        let bodyData = try XCTUnwrap(StubURLProtocol.lastRequestBody)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertEqual(body["prompt"] as? String, "some prompt text")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["format"] as? String, "json")
    }

    func testHappyParseProducesANameGuess() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.ollamaResponse("{\"name\": \"Jordan Rivera\", \"description\": \"A college friend\"}"))
        }
        let provider = OllamaProvider(session: stubbedSession())

        let guess = try await provider.guess(prompt: "irrelevant")

        XCTAssertEqual(guess.name, "Jordan Rivera")
        XCTAssertEqual(guess.detail, "A college friend")
    }

    func testGarbageResponseThrowsBadResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("not json at all { [ }".utf8))
        }
        let provider = OllamaProvider(session: stubbedSession())

        do {
            _ = try await provider.guess(prompt: "irrelevant")
            XCTFail("expected badResponse to be thrown")
        } catch let error as NameGuessError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("expected a NameGuessError")
        }
    }

    func testEmptyNameInInnerJSONThrowsBadResponse() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.ollamaResponse("{\"name\": \"\", \"description\": \"something\"}"))
        }
        let provider = OllamaProvider(session: stubbedSession())

        do {
            _ = try await provider.guess(prompt: "irrelevant")
            XCTFail("expected badResponse to be thrown for an empty required name")
        } catch let error as NameGuessError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("expected a NameGuessError")
        }
    }

    func testSimulatedConnectionErrorThrowsProviderUnreachable() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let provider = OllamaProvider(session: stubbedSession())

        do {
            _ = try await provider.guess(prompt: "irrelevant")
            XCTFail("expected providerUnreachable to be thrown")
        } catch let error as NameGuessError {
            XCTAssertEqual(error, .providerUnreachable)
        } catch {
            XCTFail("expected a NameGuessError")
        }
    }
}
