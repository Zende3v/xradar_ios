/// The proximity beeps of speed enforcement ahead, like a radar detector or Radarbot: the closer
/// the radar, the faster they come, and a laser burst right at it. Nothing before `startMeters`.
public enum AlertBeeps {
    /// The first beep sounds here, exactly: no radar sound farther out (Arthur, 01/10).
    public static let startMeters = 200
    /// At this distance or closer, one laser burst replaces the beeps.
    public static let burstMeters = 60
    /// Beeps only while driving: a car waiting at a light by a radar stays quiet.
    public static let minSpeedKmh = 10

    /// Seconds between two beeps at [meters] from the radar; nil when none is due (farther than
    /// the first beep, or already in the burst).
    public static func interval(meters: Int) -> Double? {
        switch meters {
        case ...burstMeters: nil
        case ...150: 0.45
        case ...startMeters: 0.8
        default: nil
        }
    }
}

/// Beeps calés sur distance réelle, pas sur dernier fix GPS. Fix vieux de 1 s à 130 km/h : 36 m
/// d'écart. Distance extrapolée depuis heure du fix, vitesse, latence de sortie audio.
public struct EnforcementBeeps: Sendable {
    public enum Cue: Sendable, Equatable {
        case beep
        case burst
    }

    /// What to play now, whether the audio must be ready, and when to look again.
    public struct Step: Sendable, Equatable {
        public let cue: Cue?
        /// Audio prêt : session active, tampons chargés avant premier bip.
        public let armed: Bool
        public let wakeIn: Double
    }

    /// Jamais d'extrapolation au-delà : GPS perdu, tunnel.
    public static let maxFixAgeSeconds = 2.5
    /// Audio préparé ce délai avant premier bip.
    public static let armSeconds = 1.5
    /// Tour de boucle loin des seuils.
    public static let tickSeconds = 0.1
    /// Latence de sortie retenue au plus (Bluetooth compris).
    public static let maxLatencySeconds = 0.5

    private var started: Set<String> = []
    private var bursts: Set<String> = []
    private var lastBeepAt = -Double.infinity

    public init() {}

    /// Distance au radar maintenant : distance au fix moins chemin parcouru depuis.
    public static func predictedMeters(atFix meters: Double, speedMps: Double, fixAgeSeconds: Double) -> Double {
        meters - max(speedMps, 0) * min(max(fixAgeSeconds, 0), maxFixAgeSeconds)
    }

    /// [key] nearest enforcement alert (nil: none), [metersAtFix] its distance at the fix,
    /// [now] seconds on any steady clock, [latency] audio output delay. [speaking]: the voice
    /// talks; only in-between beeps wait for it, never the first one nor the burst.
    public mutating func step(
        key: String?,
        metersAtFix: Double,
        speedMps: Double,
        fixAgeSeconds: Double,
        now: Double,
        latency: Double,
        speaking: Bool
    ) -> Step {
        if started.count > 300 {
            started.removeAll()
            bursts.removeAll()
        }
        let speed = max(speedMps, 0)
        guard let key, speed * 3.6 >= Double(AlertBeeps.minSpeedKmh) else {
            return Step(cue: nil, armed: false, wakeIn: Self.tickSeconds)
        }
        // Distance où sera la voiture quand le son atteint l'oreille.
        let lead = speed * min(max(latency, 0), Self.maxLatencySeconds)
        let heard = Self.predictedMeters(atFix: metersAtFix, speedMps: speed, fixAgeSeconds: fixAgeSeconds) - lead
        let start = Double(AlertBeeps.startMeters)
        let burst = Double(AlertBeeps.burstMeters)
        let armed = heard <= start + speed * Self.armSeconds
        func until(_ meters: Double) -> Double { (heard - meters) / speed }

        if heard <= burst {
            let cue: Cue? = bursts.insert(key).inserted ? .burst : nil
            started.insert(key)
            return Step(cue: cue, armed: armed, wakeIn: Self.tickSeconds)
        }
        if heard > start {
            return Step(cue: nil, armed: armed, wakeIn: Self.wake(until(start)))
        }
        var cue: Cue?
        if started.insert(key).inserted {
            cue = .beep
            lastBeepAt = now
        } else if !speaking, let interval = AlertBeeps.interval(meters: Int(heard.rounded(.up))), now - lastBeepAt >= interval {
            cue = .beep
            lastBeepAt = now
        }
        // Voix en cours : bip suivant attend, sans boucle serrée.
        let nextBeep = speaking
            ? Self.tickSeconds
            : (AlertBeeps.interval(meters: Int(heard.rounded(.up))) ?? Self.tickSeconds) - (now - lastBeepAt)
        return Step(cue: cue, armed: armed, wakeIn: Self.wake(min(nextBeep, until(burst))))
    }

    /// Sommeil borné : jamais plus d'un tour, jamais zéro.
    private static func wake(_ seconds: Double) -> Double {
        min(max(seconds, 0.005), tickSeconds)
    }
}
