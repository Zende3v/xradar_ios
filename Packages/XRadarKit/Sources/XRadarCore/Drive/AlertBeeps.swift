/// The proximity beeps of speed enforcement ahead, like a radar detector or Radarbot: the closer
/// the radar, the faster they come, and a laser burst right at it.
public enum AlertBeeps {
    /// At this distance or closer, one laser burst replaces the beeps.
    public static let burstMeters = 60
    /// Beeps only while driving: a car waiting at a light by a radar stays quiet.
    public static let minSpeedKmh = 10

    /// Seconds between two beeps at [meters] from the radar; nil when none is due (farther than
    /// an alert shows, or already in the burst).
    public static func interval(meters: Int) -> Double? {
        switch meters {
        case ...burstMeters: nil
        case ...150: 0.45
        case ...300: 0.8
        case ...450: 1.3
        case ...Int(AlertsAhead.alertDistanceMeters): 2.0
        default: nil
        }
    }
}
