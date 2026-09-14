import Foundation
@testable import XRadarData

/// Canned backend: answers every request with [respond] and records what was sent.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let respond: @Sendable (URLRequest) throws -> (Int, String)

    init(_ respond: @escaping @Sendable (URLRequest) throws -> (Int, String)) {
        self.respond = respond
    }

    convenience init(status: Int = 200, body: String) {
        self.init { _ in (status, body) }
    }

    var last: URLRequest? {
        lock.withLock { recorded.last }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let (status, body) = try respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

func backend(_ transport: StubTransport) -> BackendClient {
    BackendClient(configuration: BackendConfiguration(baseURL: URL(string: "https://example.org/")!), transport: transport)
}

extension URLRequest {
    var jsonBody: [String: Any] {
        guard let data = httpBody, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return object
    }

    /// Decoded query parameters.
    var query: [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    /// Percent-encoded path.
    var path: String {
        url?.path() ?? ""
    }
}
