import Foundation

/// The driver's speeds for EONA's own traffic ("Aide au trafic partagé", 29/09): one sample every
/// `sampleEverySeconds` of a trip under way — where, which way, how fast, under which limit —
/// handed out by batches of `batch` at most every `sendEverySeconds`, with [tripKey], a random key
/// of the trip, never the account. The more drivers cover a road, the less HERE is asked. Same
/// rules as Android.
public struct SpeedSampler: Sendable {
    public struct Sample: Sendable, Hashable {
        public let lat: Double
        public let lon: Double
        public let course: Double
        public let speedKmh: Double
        public let limitKmh: Int?
        public let timeMs: Int
    }

    static let sampleEverySeconds = 15.0
    static let sendEverySeconds = 60.0
    static let batch = 20
    static let maxPending = 40

    public let tripKey: String
    private var pending: [Sample] = []
    private var lastSampleAt = Date.distantPast
    private var lastSentAt = Date.distantPast

    public init(tripKey: String = UUID().uuidString.lowercased()) {
        self.tripKey = tripKey
    }

    /// A fix of the trip at [now], under [limitKmh] (the one shown); without a course, nothing.
    public mutating func add(_ fix: LocationSample, limitKmh: Int?, now: Date = Date()) {
        guard now.timeIntervalSince(lastSampleAt) >= Self.sampleEverySeconds, let course = fix.bearingDeg else { return }
        lastSampleAt = now
        pending.append(Sample(
            lat: fix.latitude, lon: fix.longitude, course: course, speedKmh: max(fix.speedKmh, 0),
            limitKmh: limitKmh, timeMs: Int(now.timeIntervalSince1970 * 1000)
        ))
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
    }

    /// The samples to send at [now], taken out; nil when it is not time yet or there are none.
    public mutating func due(now: Date = Date()) -> [Sample]? {
        guard !pending.isEmpty, now.timeIntervalSince(lastSentAt) >= Self.sendEverySeconds else { return nil }
        lastSentAt = now
        let batch = Array(pending.prefix(Self.batch))
        pending.removeFirst(batch.count)
        return batch
    }
}
