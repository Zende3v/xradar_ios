/// The ground speed shown to the driver, from Core Location's raw readings: the noise of a car
/// standing still reads 0, a reading worse than its own margin is ignored, a spike is clamped to
/// what a car can really do, and what remains is smoothed just enough not to jump.
public struct SpeedFilter: Sendable {
    /// Under this (3,6 km/h) a reading is a stop, once the car is already slow.
    static let stopMps = 1.0
    /// Leaving a stop takes two readings in a row above this (~7 km/h).
    static let startMps = 1.9
    /// A stop is only believed below this speed: at 80 km/h a sudden 0 is a glitch.
    static let stopBelowMps = 5.0
    /// Hard acceleration and emergency braking of a car, in m/s².
    static let maxAccelerationMps2 = 4.0
    static let maxBrakingMps2 = 9.0
    /// Weight of each new reading.
    static let smoothing = 0.6

    private var current = 0.0
    private var stopped = true
    private var startReadings = 0
    private var lastTimeMs: Int?

    public init() {}

    /// [speed] and [accuracy] in m/s as Core Location gives them (negative = invalid), at [timeMs];
    /// returns the speed to show, in m/s.
    public mutating func update(speed: Double, accuracy: Double, timeMs: Int) -> Double {
        let seconds = lastTimeMs.map { min(max(Double(timeMs - $0) / 1000, 0.1), 5) } ?? 1
        lastTimeMs = timeMs
        let reliable = speed >= 0 && accuracy >= 0 && accuracy <= max(2.0, speed * 0.5)
        let reading = reliable ? speed : current

        if stopped {
            startReadings = reading >= Self.startMps ? startReadings + 1 : 0
            guard startReadings >= 2 else { return 0 }
            stopped = false
        } else if reading < Self.stopMps && current < Self.stopBelowMps {
            stopped = true
            startReadings = 0
            current = 0
            return 0
        }

        let smoothed = (reading - current) * Self.smoothing
        current += min(max(smoothed, -Self.maxBrakingMps2 * seconds), Self.maxAccelerationMps2 * seconds)
        return max(current, 0)
    }
}
