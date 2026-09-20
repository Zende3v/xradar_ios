import Foundation

/// OSRM maneuvers to French instructions and a visual [Maneuver] class.
/// Reference: OSRM `maneuver.type` / `maneuver.modifier` vocabulary.
public enum GuidanceText {

    /// Which arrow to show for a step.
    public static func maneuver(of step: RouteStep) -> Maneuver {
        switch step.type {
        case "depart":
            return .depart
        case "arrive":
            return .arrive
        case "roundabout", "rotary", "roundabout turn":
            return .roundabout
        case "merge":
            return .merge
        case "on ramp", "off ramp":
            // The ramp arrow points right: a ramp on the left gets a left arrow.
            return step.modifier?.contains("left") == true ? .slightLeft : .ramp
        case "fork":
            if step.modifier?.contains("left") == true { return .forkLeft }
            if step.modifier?.contains("right") == true { return .forkRight }
            return .straight
        default:
            return byModifier(step.modifier)
        }
    }

    private static func byModifier(_ modifier: String?) -> Maneuver {
        switch modifier {
        case "left"?: return .left
        case "right"?: return .right
        case "slight left"?: return .slightLeft
        case "slight right"?: return .slightRight
        case "sharp left"?: return .sharpLeft
        case "sharp right"?: return .sharpRight
        case "uturn"?: return .uturn
        default: return .straight
        }
    }

    /// Short verb phrase, capitalized, no distance ("Tournez à droite").
    public static func verb(_ step: RouteStep) -> String {
        let modifier = step.modifier
        switch step.type {
        case "depart":
            return "C'est parti"
        case "arrive":
            return "Vous êtes arrivé"
        case "roundabout", "rotary", "roundabout turn":
            if let exit = step.exit, (1...9).contains(exit) {
                return "Au rond-point, prenez la \(ordinal(exit)) sortie"
            }
            return "Prenez le rond-point"
        case "merge":
            return "Insérez-vous" + side(modifier)
        case "on ramp":
            return "Prenez la bretelle" + side(modifier)
        case "off ramp":
            return "Prenez la sortie" + side(modifier)
        case "fork":
            if modifier?.contains("left") == true { return "Restez à gauche" }
            if modifier?.contains("right") == true { return "Restez à droite" }
            return "Continuez tout droit"
        case "end of road":
            switch modifier {
            case "left"?: return "Au bout de la route, à gauche"
            case "right"?: return "Au bout de la route, à droite"
            default: return "Continuez tout droit"
            }
        case "new name", "continue", "notification", "use lane":
            switch modifier {
            case nil, "straight"?: return "Continuez tout droit"
            case "uturn"?: return "Faites demi-tour"
            default: return turn(modifier)
            }
        default:
            return turn(modifier)
        }
    }

    private static func turn(_ modifier: String?) -> String {
        switch modifier {
        case "left"?: return "Tournez à gauche"
        case "right"?: return "Tournez à droite"
        case "slight left"?: return "Serrez à gauche"
        case "slight right"?: return "Serrez à droite"
        case "sharp left"?: return "Tournez franchement à gauche"
        case "sharp right"?: return "Tournez franchement à droite"
        case "uturn"?: return "Faites demi-tour"
        default: return "Continuez tout droit"
        }
    }

    private static func side(_ modifier: String?) -> String {
        if modifier?.contains("left") == true { return " à gauche" }
        if modifier?.contains("right") == true { return " à droite" }
        return ""
    }

    private static func ordinal(_ n: Int) -> String {
        n == 1 ? "1re" : "\(n)e"
    }

    /// Compact distance for the banner ("250 m", "1,2 km").
    public static func distanceLabel(_ meters: Int) -> String {
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            return km >= 10 ? "\(Int(km.rounded())) km" : "\(frenchOneDecimal(km)) km"
        }
        if meters >= 20 {
            return "\(((meters + 5) / 10) * 10) m"
        }
        return "\(meters) m"
    }

    /// Distance as spoken French ("250 mètres", "1,2 kilomètre", "2 kilomètres").
    public static func spokenDistance(_ meters: Int) -> String {
        guard meters >= 1000 else {
            return "\(max((meters + 25) / 50, 1) * 50) mètres"
        }
        let km = Double(meters) / 1000.0
        let tenths = Int((km * 10.0).rounded())
        if km >= 10 {
            return "\(Int(km.rounded())) kilomètres"
        }
        // "1,0 kilomètre" reads badly out loud: say "1 kilomètre".
        if tenths % 10 == 0 {
            return "\(tenths / 10) kilomètre" + (tenths >= 20 ? "s" : "")
        }
        return frenchOneDecimal(km) + " kilomètre" + (km >= 2 ? "s" : "")
    }

    /// Full spoken heads-up ("Dans 300 mètres, tournez à droite sur Rue de la Paix").
    public static func spokenFar(_ step: RouteStep, meters: Int) -> String {
        if step.type == "arrive" { return "Vous êtes bientôt arrivé" }
        let head = "Dans \(spokenDistance(meters)), \(lowerFirst(verb(step)))"
        let named = !step.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let road = named && step.type != "roundabout" && step.type != "rotary" ? step.name : nil
        if let road { return "\(head) sur \(road)" }
        return head
    }

    /// Short spoken cue at the maneuver ("Tournez à droite maintenant").
    public static func spokenNear(_ step: RouteStep) -> String {
        switch step.type {
        case "arrive":
            return "Vous êtes arrivé à destination"
        case "roundabout", "rotary", "roundabout turn", "merge", "on ramp", "off ramp", "fork":
            return verb(step)
        default:
            let phrase = verb(step)
            return phrase == "Continuez tout droit" ? phrase : "\(phrase) maintenant"
        }
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
