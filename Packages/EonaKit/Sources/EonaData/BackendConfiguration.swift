import Foundation

/// Where the EONA backend lives. Built from the app's Info.plist (`XRBackendURL`).
public struct BackendConfiguration: Sendable, Equatable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Parses a configured value; nil unless it is an absolute http(s) URL with a host.
    public init?(string: String?) {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else { return nil }
        self.baseURL = url
    }

    /// The live backend (the VPS through Cloudflare Tunnel) — same as the Android build.
    public static let production = BackendConfiguration(
        baseURL: URL(string: "https://api.lrda-mercuriale.uk/")!
    )
}
