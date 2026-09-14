import Foundation
import XRadarCore

/// Sends one HTTP request. The app uses [URLSessionTransport]; tests plug in canned answers.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession without a response cache: every call reads the backend, as OkHttp does.
public struct URLSessionTransport: HTTPTransport {
    public static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.defaultSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// An answer: its status and body.
struct HTTPResult: Sendable {
    let status: Int
    let data: Data

    var isSuccessful: Bool {
        (200..<300).contains(status)
    }

    var text: String {
        String(decoding: data, as: UTF8.self)
    }

    var json: JSON? {
        JSON(data: data)
    }
}

/// The x_radar backend: where it lives and how requests reach it. Shared by every API.
public struct BackendClient: Sendable {
    public let baseURL: URL
    let transport: any HTTPTransport

    public init(configuration: BackendConfiguration = .production, transport: any HTTPTransport = URLSessionTransport()) {
        baseURL = configuration.baseURL
        self.transport = transport
    }

    /// Query values keep "+", "&" and "=" encoded, so a value never splits or turns into a space.
    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))

    /// [path] ("/api/…") on the backend, with its query.
    func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return try Self.url(base + path, query: query)
    }

    /// An absolute address with its query (also for services other than the backend).
    static func url(_ address: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: address) else { throw URLError(.badURL) }
        if !query.isEmpty {
            components.percentEncodedQueryItems = query.map {
                URLQueryItem(name: $0.name, value: $0.value?.addingPercentEncoding(withAllowedCharacters: queryValueAllowed))
            }
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// One path segment, encoded (an id inside a path).
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    func request(
        _ method: String,
        _ url: URL,
        json: [String: Any]? = nil,
        token: String? = nil,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let (data, response) = try await transport.send(request)
        return HTTPResult(status: response.statusCode, data: data)
    }
}

/// A route polyline as the backend expects it: `[[longitude, latitude], …]`.
func coordinates(_ points: [GeoPoint]) -> [[Double]] {
    points.map { [$0.lon, $0.lat] }
}

extension URLQueryItem {
    /// A query parameter written as the Android app writes it ("48.1113", "5000", "90.5").
    init(_ name: String, _ value: some CustomStringConvertible) {
        self.init(name: name, value: value.description)
    }
}
