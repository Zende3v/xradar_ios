import Foundation

/// The Apple-Plans-like basemap, as on Android: one layer structure (plans-style.json) painted with
/// the day or night palette (plans-palettes.json). Every "@token" becomes that palette's value; the
/// Stadia key fills the tile URLs. Vector tiles, glyphs and sprites are Stadia's, the look is ours.
enum PlansMapStyle {
    /// Loud on purpose: a token missing from a palette shows up magenta, never as a blank map.
    private static let missingToken = "#FF00FF"
    private static let keyPlaceholder = "{{STADIA_API_KEY}}"

    /// A file URL of the style for the night ([dark]) or day map, for MLNMapView.styleURL.
    static func url(dark: Bool, apiKey: String?) throws -> URL {
        guard let styleFile = Bundle.main.url(forResource: "plans-style", withExtension: "json"),
              let palettesFile = Bundle.main.url(forResource: "plans-palettes", withExtension: "json")
        else { throw CocoaError(.fileNoSuchFile) }
        let template = try String(contentsOf: styleFile, encoding: .utf8)
        let palettes = try JSONSerialization.jsonObject(with: Data(contentsOf: palettesFile)) as? [String: Any]
        let palette = palettes?[dark ? "dark" : "light"] as? [String: Any] ?? [:]
        let painted = template.replacing(/"@([A-Za-z0-9_]+)"/) { match in
            PlansMapStyle.quoted(palette[String(match.output.1)] as? String ?? PlansMapStyle.missingToken)
        }
        let json = painted.replacingOccurrences(of: keyPlaceholder, with: apiKey ?? "")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(dark ? "plans-dark.json" : "plans-light.json")
        try json.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// [value] as a JSON string literal.
    private static func quoted(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
              let text = String(data: data, encoding: .utf8)
        else { return "\"\(value)\"" }
        return text
    }
}
