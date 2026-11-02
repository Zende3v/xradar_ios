import Foundation
import Testing
import EonaCore
@testable import EonaData

struct SearchAPITests {
    @Test func sendsTheCapturedSessionAndEncodedQuery() async throws {
        let transport = StubTransport(body: #"{"results":[{"id":"paris","name":"Paris","lat":48.86,"lon":2.35,"distanceM":1200},{"name":"invalid"}]}"#)
        let places = try await SearchAPI(client: backend(transport)).search(
            "rue de la gare & co +", around: GeoPoint(lat: 48.1, lon: 2.1), token: "captured-token"
        )
        #expect(places.count == 1)
        #expect(places.first?.id == "paris")
        #expect(places.first?.distanceMeters == 1200)
        #expect(transport.last?.path == "/api/search")
        #expect(transport.last?.query == ["q": "rue de la gare & co +", "limit": "8", "lat": "48.1", "lon": "2.1"])
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == "Bearer captured-token")
    }

    @Test func successfulEmptyResultsRemainEmpty() async throws {
        let transport = StubTransport(body: #"{"results":[]}"#)
        #expect(try await SearchAPI(client: backend(transport)).search("Paris", token: nil).isEmpty)
        #expect(transport.last?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport.last?.query == ["q": "Paris", "limit": "8"])
    }

    @Test(arguments: [401, 403, 429, 500, 503])
    func refusalsAndServerErrorsAreNotEmptyResults(_ status: Int) async {
        let expected: SearchAPI.Failure
        switch status {
        case 401: expected = .unauthenticated
        case 403: expected = .forbidden
        case 429: expected = .rateLimited
        default: expected = .unavailable
        }
        await #expect(throws: expected) {
            try await SearchAPI(client: backend(StubTransport(status: status, body: #"{"results":[]}"#)))
                .search("Paris", token: "old")
        }
    }

    @Test(arguments: ["not json", "{}", #"{"results":null}"#, #"{"results":{}}"#, #"{"results":[null]}"#, #"{"results":[{"name":"invalid"}]}"#])
    func invalidResponsesAreUnavailable(_ body: String) async {
        await #expect(throws: SearchAPI.Failure.unavailable) {
            try await SearchAPI(client: backend(StubTransport(body: body))).search("Paris", token: nil)
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut])
    func networkFailuresAreUnavailable(_ code: URLError.Code) async {
        let transport = StubTransport { _ in throw URLError(code) }
        await #expect(throws: SearchAPI.Failure.unavailable) {
            try await SearchAPI(client: backend(transport)).search("Paris", token: "session")
        }
    }

    @Test func transportCancellationIsPropagated() async {
        let transport = StubTransport { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) {
            try await SearchAPI(client: backend(transport)).search("Paris", token: "session")
        }
    }

    @Test func cancellationAfterTransportDoesNotReturnResults() async {
        let client = BackendClient(
            configuration: BackendConfiguration(baseURL: URL(string: "https://example.org/")!),
            transport: CancellingSearchTransport()
        )
        let request = Task { try await SearchAPI(client: client).search("Paris", token: "session") }
        await #expect(throws: CancellationError.self) { try await request.value }
    }
}

/// Simule un transport qui termine malgré l'annulation de la tâche pendant l'envoi.
private struct CancellingSearchTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        withUnsafeCurrentTask { $0?.cancel() }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(#"{"results":[]}"#.utf8), response)
    }
}
