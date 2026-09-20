import Foundation
@testable import EonaCore

let paris = TimeZone(identifier: "Europe/Paris")!

/// Epoch millis of a wall-clock time in Paris.
func parisMillis(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = paris
    let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    return Int(date.timeIntervalSince1970 * 1000)
}

func place(
    _ id: String,
    meters: Int,
    name: String? = nil,
    hours: OpeningHours? = nil,
    fuel: StationFuel? = nil,
    nearby: NearbyInfo? = nil
) -> Place {
    Place(
        id: id,
        name: name ?? id,
        subtitle: "",
        kind: .result,
        lat: 48.11,
        lon: -1.68,
        fuel: fuel,
        distanceMeters: meters,
        nearby: nearby ?? hours.map { NearbyInfo(hours: $0) }
    )
}

func step(_ type: String, _ modifier: String? = nil, name: String = "", exit: Int? = nil) -> RouteStep {
    RouteStep(location: GeoPoint(lat: 0, lon: 0), type: type, modifier: modifier, name: name, distanceMeters: 0, exit: exit)
}
