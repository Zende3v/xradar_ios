import Foundation
import EonaCore

/// What a driver types (`/api/search`): the backend asks a place search and the official address
/// search at once and merges them, so "Lycée Adolphe Chérioux vitry" finds the school and
/// "10 rue de la paix" finds the door. Biased toward where the driver is.
public struct SearchAPI: Sendable {
    static let timeout: TimeInterval = 10

    private let client: BackendClient

    public init(client: BackendClient = BackendClient()) {
        self.client = client
    }

    public func search(
        _ query: String,
        around: GeoPoint? = nil,
        limit: Int = 8,
        token: String?
    ) async -> [Place] {
        var items = [URLQueryItem("q", query), URLQueryItem("limit", limit)]
        if let around {
            items += [URLQueryItem("lat", around.lat), URLQueryItem("lon", around.lon)]
        }
        guard let request = try? client.request("GET", client.url("/api/search", query: items), token: token, timeout: Self.timeout),
              let result = try? await client.send(request), result.isSuccessful,
              let json = result.json
        else { return [] }
        return (json.objects("results") ?? []).compactMap(Self.place)
    }

    private static func place(_ item: JSON) -> Place? {
        let lat = item.double("lat")
        let lon = item.double("lon")
        let name = item.nonBlankString("name")
        guard lat.isFinite, lon.isFinite, let name else { return nil }
        return Place(
            id: item.nonBlankString("id") ?? "\(lat),\(lon)",
            name: name,
            subtitle: item.string("subtitle"),
            kind: .result,
            lat: lat,
            lon: lon,
            distanceMeters: item.has("distanceM") && !item.isNull("distanceM") ? item.int("distanceM") : nil
        )
    }
}
