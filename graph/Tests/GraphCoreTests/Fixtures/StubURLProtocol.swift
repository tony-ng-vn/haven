import Foundation

/// Intercepts every request made through a URLSession configured with this protocol class
/// registered, so tests never make a real network call. Registered into an ephemeral
/// URLSessionConfiguration per test (see OllamaProviderTests), never URLSession.shared.
final class StubURLProtocol: URLProtocol {
    /// Set per-test, cleared in tearDown: returning a response, or throwing to simulate a
    /// transport-level failure (e.g. connection refused). `nonisolated(unsafe)`: XCTest runs
    /// this test class's methods serially, one at a time, so there is no real concurrent
    /// access to guard against -- only the compiler's inability to see that.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    /// The last request this protocol saw, for pinning URL/body-shape assertions.
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // httpBodyStream is how URLSession delivers a POST body to a custom protocol handler
        // in practice, not request.httpBody (which is often nil by the time it gets here).
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            Self.lastRequestBody = data
        } else {
            Self.lastRequestBody = request.httpBody
        }

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
