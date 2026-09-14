import Foundation

/// The alerts of the driving HUD, as the Android DriveViewModel computes them: the radars and
/// crowd reports ahead of the driver (inside a cone around their course), nearest first.
public enum AlertsAhead {
    /// How far ahead a radar or a report shows as an alert.
    public static let alertDistanceMeters = 700.0
    /// A speed radar this close ahead gives its VMA as the limit.
    public static let limitDistanceMeters = 1000.0
    /// Farther than this off the driver's course, it is not ahead.
    public static let aheadConeDeg = 75.0
    /// A crowd report closer than this asks "toujours là / plus là".
    public static let voteDistanceMeters = 300
    /// The voice announces an alert once inside each band: 201...500 m, then 0...200 m.
    public static let voiceFarMeters = 500
    public static let voiceNearMeters = 200

    /// Every radar ahead within alert range, nearest first, and the VMA of the nearest speed
    /// radar ahead within [limitDistanceMeters].
    public static func radars(_ radars: [Radar], sample: LocationSample?, speedKmh: Int) -> (alerts: [RoadAlert], limitKmh: Int?) {
        guard let sample, !radars.isEmpty else { return ([], nil) }
        let ahead = radars
            .map { Candidate(item: $0, distance: distance(from: sample, $0.lat, $0.lon)) }
            .filter { isAhead(sample, $0.item.lat, $0.item.lon) }
            .stableSorted { $0.distance }
        let limit = ahead.first { $0.item.isSpeedRadar && $0.distance <= limitDistanceMeters }?.item.vma
        let speed = metersPerSecond(speedKmh)
        let alerts = ahead.prefix(while: { $0.distance <= alertDistanceMeters }).map { candidate in
            RoadAlert(
                type: candidate.item.alertType,
                title: candidate.item.displayTitle,
                roadLabel: nil,
                speedLimitKmh: candidate.item.vma,
                distanceMeters: roundToInt(candidate.distance),
                etaSeconds: roundToInt(candidate.distance / speed),
                confidence: 1,
                lastReportedLabel: nil,
                id: candidate.item.id
            )
        }
        return (alerts, limit)
    }

    /// Every report ahead still worth an alert for this driver, nearest first. [onSameRoad] says
    /// whether a report sits on the road being driven (only knowable while navigating).
    public static func reports(
        _ reports: [UserReport],
        sample: LocationSample?,
        speedKmh: Int,
        onSameRoad: (UserReport) -> Bool
    ) -> [RoadAlert] {
        guard let sample, !reports.isEmpty else { return [] }
        let heading = sample.bearingDeg
        let speed = metersPerSecond(speedKmh)
        return reports
            .map { Candidate(item: $0, distance: distance(from: sample, $0.lat, $0.lon)) }
            .filter { isAhead(sample, $0.item.lat, $0.item.lon) }
            .stableSorted { $0.distance }
            // Never shown before the alert distance, whatever the category's impact zone.
            .filter { $0.distance <= alertDistanceMeters }
            .compactMap { candidate in
                let report = candidate.item
                // Worth an alert while the full score (time, crowd, road, direction, distance)
                // stays above the minimum for this driver.
                let score = ReportRelevance.score(
                    report,
                    distanceMeters: candidate.distance,
                    driverBearing: heading,
                    onSameRoad: onSameRoad(report)
                )
                guard score >= ReportRelevance.minimum else { return nil }
                return RoadAlert(
                    type: report.type.alertType,
                    title: report.type.label,
                    // The other carriageway changes what the driver does: say so.
                    roadLabel: report.direction == "opposite" ? report.directionLabel : report.sideLabel.map { "côté \($0)" },
                    speedLimitKmh: nil,
                    distanceMeters: roundToInt(candidate.distance),
                    etaSeconds: roundToInt(candidate.distance / speed),
                    confidence: min(max(score / 100.0, 0), 1),
                    lastReportedLabel: report.crowdLabel,
                    id: report.id
                )
            }
    }

    /// What the voice says for [alert] at its distance, and the band it belongs to (said once
    /// per alert and band); nil outside both bands.
    public static func announcement(for alert: RoadAlert) -> (band: Int, text: String)? {
        let meters = alert.distanceMeters
        if meters > voiceNearMeters && meters <= voiceFarMeters {
            let spoken = GuidanceText.spokenDistance(meters)
            if let vma = alert.speedLimitKmh {
                return (voiceFarMeters, "\(alert.title) dans \(spoken), vitesse \(vma).")
            }
            return (voiceFarMeters, "\(alert.title) dans \(spoken).")
        }
        if meters >= 0 && meters <= voiceNearMeters {
            return (voiceNearMeters, "\(alert.title)\(alert.roadLabel.map { ", \($0)" } ?? "").")
        }
        return nil
    }

    static func isAhead(_ sample: LocationSample, _ lat: Double, _ lon: Double) -> Bool {
        guard let heading = sample.bearingDeg else { return true }
        let toward = Geo.bearing(lat1: sample.latitude, lon1: sample.longitude, lat2: lat, lon2: lon)
        return Geo.angularDiff(heading, toward) <= aheadConeDeg
    }

    private static func distance(from sample: LocationSample, _ lat: Double, _ lon: Double) -> Double {
        Geo.haversine(lat1: sample.latitude, lon1: sample.longitude, lat2: lat, lon2: lon)
    }

    private static func metersPerSecond(_ speedKmh: Int) -> Double {
        max(Double(speedKmh) * 1000.0 / 3600.0, 1.0)
    }

    private struct Candidate<Item> {
        let item: Item
        let distance: Double
    }
}

public extension RoadAlert {
    /// Stable identity across frames: its radar or report id.
    var key: String {
        id ?? "\(type):\(title)"
    }

    /// "Sens opposé · limité à 90 km/h"; empty when there is nothing to add.
    var subtitle: String {
        var parts: [String] = []
        if let roadLabel { parts.append(roadLabel) }
        if let speedLimitKmh { parts.append("limité à \(speedLimitKmh) km/h") }
        return parts.joined(separator: " · ")
    }

    /// "650 m", "1,2 km".
    static func distanceLabel(_ meters: Int) -> String {
        meters >= 1000 ? "\(frenchOneDecimal(Double(meters) / 1000.0)) km" : "\(meters) m"
    }

    /// Nearest first, except that two neighbours less than [marginMeters] apart keep the order
    /// they had last time ([previous] keys): GPS noise must not swap them back and forth.
    static func stableOrder(previous: [String], alerts: [RoadAlert], marginMeters: Int) -> [RoadAlert] {
        var sorted = alerts.stableSorted { $0.distanceMeters }
        guard !previous.isEmpty, sorted.count > 1 else { return sorted }
        var rank: [String: Int] = [:]
        for (index, key) in previous.enumerated() {
            rank[key] = index
        }
        for i in 0..<(sorted.count - 1) {
            let near = sorted[i]
            let far = sorted[i + 1]
            guard let nearRank = rank[near.key], let farRank = rank[far.key] else { continue }
            if farRank < nearRank && far.distanceMeters - near.distanceMeters < marginMeters {
                sorted[i] = far
                sorted[i + 1] = near
            }
        }
        return sorted
    }
}

/// Kotlin's `roundToInt` for the positive values used here.
func roundToInt(_ value: Double) -> Int {
    Int(value.rounded())
}
