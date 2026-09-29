import Foundation

/// When the ETA asks TomTom again (D2.2): at once for a new route, then on an event — the driver
/// off the plan (the arrival moved by `driftSeconds` or `driftRatio` of the time left since
/// TomTom's last answer), a TomTom jam passed — or at the latest after a wait that grows with the
/// time left. Never closer than the backend's minGapS (its budget, D3.1) nor `minGapSeconds`.
/// Between those, the drivers' and data.gouv's traffic come every `othersEverySeconds` without
/// TomTom. The thresholds are first values, to measure (D2.2). Same rules as Android.
public struct TrafficRefresh: Sendable {
    public enum Ask: Sendable, Equatable { case withTomtom, withoutTomtom }

    static let debounceSeconds = 15.0
    static let minGapSeconds = 60.0
    static let othersEverySeconds = 120.0
    static let driftSeconds = 120.0
    static let driftRatio = 0.1

    private var lastAskAt = Date.distantPast
    private var lastTomtomAt: Date?
    private var tomtomNotBefore = Date.distantPast
    private var predictedArrival: Date?
    private var jamEnds: [Double] = []

    public init() {}

    /// A new route: TomTom is asked at once.
    public mutating func newRoute() {
        lastTomtomAt = nil
        tomtomNotBefore = .distantPast
        predictedArrival = nil
        jamEnds = []
    }

    /// What to ask at [now] for a driver [alongMeters] along the route, the arrival shown being
    /// [arrival] (nil without a route): nil for nothing.
    public func due(now: Date, alongMeters: Double, arrival: Date?) -> Ask? {
        if now.timeIntervalSince(lastAskAt) < Self.debounceSeconds { return nil }
        if now >= tomtomNotBefore && tomtomDue(now: now, alongMeters: alongMeters, arrival: arrival) { return .withTomtom }
        return now.timeIntervalSince(lastAskAt) >= Self.othersEverySeconds ? .withoutTomtom : nil
    }

    private func tomtomDue(now: Date, alongMeters: Double, arrival: Date?) -> Bool {
        guard let lastTomtomAt else { return true }
        guard let arrival else { return false }
        let left = arrival.timeIntervalSince(now)
        let drifted = predictedArrival.map { abs(arrival.timeIntervalSince($0)) >= max(Self.driftSeconds, left * Self.driftRatio) } ?? false
        let jamPassed = jamEnds.contains { $0 <= alongMeters }
        return drifted || jamPassed || now.timeIntervalSince(lastTomtomAt) >= Self.maxWait(left: left)
    }

    public mutating func asked(now: Date) {
        lastAskAt = now
    }

    /// The answer came: [tomtom] whether TomTom timed the route, [arrival] the arrival shown with
    /// it, [tomtomJamEnds] where its jams end (metres along the route), [minGapSeconds] the
    /// backend's least wait before the next recalage.
    public mutating func answered(now: Date, tomtom: Bool, asked: Ask, arrival: Date?, tomtomJamEnds: [Double], minGapSeconds: Int) {
        let gap = max(Self.minGapSeconds, Double(minGapSeconds))
        if tomtom {
            lastTomtomAt = now
            predictedArrival = arrival
            jamEnds = tomtomJamEnds
        }
        if tomtom || asked == .withTomtom { tomtomNotBefore = now.addingTimeInterval(gap) }
    }

    private static func maxWait(left: TimeInterval) -> TimeInterval {
        if left >= 3600 { return 15 * 60 }
        if left >= 1200 { return 10 * 60 }
        return 5 * 60
    }
}
