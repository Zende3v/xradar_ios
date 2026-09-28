/// A car standing still stays still on screen. At a stop the GPS drifts by metres, turns its course
/// every way and reads speeds that are not there (30 km/h at a red light). Once the speed shown is
/// 0, every fix shows where the car stopped, the last course driven and 0 km/h; the car leaves the
/// stop only when the fixes really go away from it, farther at each one, and the speed says so
/// twice (`SpeedFilter`). A poor fix never starts the car, and a better one moves the stop to
/// where it says. Same rules as the Android app.
public struct StandstillFilter: Sendable {
    static let minHoldMeters = 8.0
    static let maxHoldMeters = 25.0
    /// Leaving: each fix at least this much farther from the stop than the last one.
    static let minStepMeters = 1.0
    /// A fix worse than this never starts the car.
    static let maxStartAccuracyMeters = 30.0
    static let unknownAccuracyMeters = 10.0
    /// A fix reading less than this (3,6 km/h) says the car does not move.
    static let stillMps = 1.0

    private var speed = SpeedFilter()
    /// Where the car stands, while the speed shown is 0.
    private var stop: LocationSample?
    /// How far the last fix was from `stop`: leaving means farther at each fix.
    private var lastAwayMeters = 0.0
    /// The last course driven, kept at the stop.
    private var course: Double?

    public init() {}

    /// [sample] as Core Location gives it, [speedAccuracy] its speed's margin in m/s (negative:
    /// unknown); returns the fix to show.
    public mutating func update(_ sample: LocationSample, speedAccuracy: Double) -> LocationSample {
        let away = stop.map {
            Geo.haversine(lat1: $0.latitude, lon1: $0.longitude, lat2: sample.latitude, lon2: sample.longitude)
        } ?? 0
        let leaving = stop == nil || (
            away >= Self.hold(sample.accuracyM)
                && away > lastAwayMeters + Self.minStepMeters
                && (sample.accuracyM ?? 0) <= Self.maxStartAccuracyMeters
        )
        lastAwayMeters = away
        let shown = leaving
            ? speed.update(speed: sample.speedMps ?? -1, accuracy: speedAccuracy, timeMs: sample.timeMs)
            : speed.update(speed: 0, accuracy: 0, timeMs: sample.timeMs)
        if shown > 0 {
            stop = nil
            lastAwayMeters = 0
            if let bearing = sample.bearingDeg { course = bearing }
            return sample.with(speedMps: shown)
        }
        // Standing: a first fix, or a better one farther than the noise that does not move (the
        // GPS correcting itself, not the car leaving), sets where the car is.
        var held = stop
        if let at = stop,
           Self.accuracy(sample) <= Self.accuracy(at),
           away >= Self.hold(sample.accuracyM) || Self.accuracy(sample) <= Self.accuracy(at) / 2,
           !leaving || (sample.speedMps ?? 0) < Self.stillMps {
            held = nil
        }
        if held == nil {
            stop = sample
            lastAwayMeters = 0
        }
        let at = held ?? sample
        return LocationSample(
            latitude: at.latitude,
            longitude: at.longitude,
            speedMps: 0,
            bearingDeg: course,
            accuracyM: sample.accuracyM,
            timeMs: sample.timeMs
        )
    }

    private static func accuracy(_ fix: LocationSample) -> Double {
        fix.accuracyM ?? unknownAccuracyMeters
    }

    /// The noise around a stop: the fix's own margin, within bounds.
    private static func hold(_ accuracyM: Double?) -> Double {
        min(max(accuracyM ?? unknownAccuracyMeters, minHoldMeters), maxHoldMeters)
    }
}

private extension LocationSample {
    func with(speedMps: Double) -> LocationSample {
        LocationSample(
            latitude: latitude,
            longitude: longitude,
            speedMps: speedMps,
            bearingDeg: bearingDeg,
            accuracyM: accuracyM,
            timeMs: timeMs
        )
    }
}
