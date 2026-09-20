import Foundation

/// Is the sun up here, right now? Picks the day or night basemap without asking the phone's
/// theme. Low-precision solar position (±0.5°, standard almanac approximation).
public enum SunClock {

    /// Sun altitude in degrees above the horizon at lat/lon and [date].
    public static func altitudeDeg(lat: Double, lon: Double, at date: Date) -> Double {
        // Days since the J2000.0 epoch (2000-01-01 12:00 UTC).
        let d = (date.timeIntervalSince1970 * 1000.0 - j2000Millis) / 86_400_000.0

        let meanLongitude = 280.460 + 0.9856474 * d
        let meanAnomaly = Geo.radians(357.528 + 0.9856003 * d)
        // Ecliptic longitude: mean longitude corrected for the orbit's eccentricity.
        let eccentricity = 1.915 * sin(meanAnomaly) + 0.020 * sin(2.0 * meanAnomaly)
        let lambda = Geo.radians(meanLongitude + eccentricity)
        let obliquity = Geo.radians(23.439 - 0.0000004 * d)

        let rightAscension = atan2(cos(obliquity) * sin(lambda), cos(lambda))
        let declination = asin(sin(obliquity) * sin(lambda))

        // Greenwich mean sidereal time, then the local hour angle of the sun.
        let gmstHours = 18.697374558 + 24.06570982441908 * d
        let hourAngle = Geo.radians(norm360(gmstHours * 15.0 + lon - Geo.degrees(rightAscension)))

        let phi = Geo.radians(lat)
        let overhead = sin(phi) * sin(declination)
        let slant = cos(phi) * cos(declination) * cos(hourAngle)
        return Geo.degrees(asin(overhead + slant))
    }

    /// True while there is daylight. The threshold sits at civil twilight, so the map flips a
    /// little before the sun clears the horizon, which is what the eye expects.
    public static func isDaylight(lat: Double, lon: Double, at date: Date = Date()) -> Bool {
        altitudeDeg(lat: lat, lon: lon, at: date) > civilTwilightDeg
    }

    static func norm360(_ degrees: Double) -> Double {
        (degrees.truncatingRemainder(dividingBy: 360.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    static let j2000Millis = 946_728_000_000.0
    static let civilTwilightDeg = -6.0
}
