import Foundation
import XRadarCore

/// Lenient reader over a JSON object, read like the Android app's org.json `opt*` calls: a
/// missing, null or mistyped field gives the fallback instead of failing the whole answer.
struct JSON {
    let raw: [String: Any]

    init(_ raw: [String: Any]) {
        self.raw = raw
    }

    init?(data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        raw = object
    }

    func has(_ key: String) -> Bool {
        raw[key] != nil
    }

    /// Missing or JSON null.
    func isNull(_ key: String) -> Bool {
        guard let value = raw[key] else { return true }
        return value is NSNull
    }

    func string(_ key: String, _ fallback: String = "") -> String {
        guard let value = raw[key] else { return fallback }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return fallback
    }

    /// The string, or nil when missing, null or blank.
    func nonBlankString(_ key: String) -> String? {
        let text = string(key)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        guard let value = raw[key] else { return fallback }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String,
           let parsed = Double(text.trimmingCharacters(in: .whitespaces)),
           parsed.isFinite, abs(parsed) < 9e18 {
            return Int(parsed)
        }
        return fallback
    }

    func double(_ key: String, _ fallback: Double = .nan) -> Double {
        guard let value = raw[key] else { return fallback }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let parsed = Double(text.trimmingCharacters(in: .whitespaces)) { return parsed }
        return fallback
    }

    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        guard let value = raw[key] else { return fallback }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        if let text = value as? String {
            if text.lowercased() == "true" { return true }
            if text.lowercased() == "false" { return false }
        }
        return fallback
    }

    func object(_ key: String) -> JSON? {
        (raw[key] as? [String: Any]).map { JSON($0) }
    }

    func array(_ key: String) -> [Any]? {
        raw[key] as? [Any]
    }

    /// The objects of an array, skipping anything else; nil when there is no array.
    func objects(_ key: String) -> [JSON]? {
        array(key).map { items in items.compactMap { item in (item as? [String: Any]).map { JSON($0) } } }
    }

    /// The non-blank strings of an array.
    func strings(_ key: String) -> [String] {
        (array(key) ?? []).compactMap { item in
            guard let text = item as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }
    }

    /// `[longitude, latitude]` pairs as points; malformed pairs are skipped.
    static func lonLat(_ value: Any?) -> GeoPoint? {
        guard let pair = value as? [Any], pair.count >= 2,
              let lon = pair[0] as? NSNumber, let lat = pair[1] as? NSNumber
        else { return nil }
        return GeoPoint(lat: lat.doubleValue, lon: lon.doubleValue)
    }
}
