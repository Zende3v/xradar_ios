import Foundation

/// Seules les photos servies par le backend configuré peuvent être chargées.
public enum AvatarURL {
    public static func allowed(_ value: String?, baseURL: URL) -> URL? {
        guard let value, let url = URL(string: value),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.scheme?.lowercased() == base.scheme?.lowercased(),
              parts.host?.lowercased() == base.host?.lowercased(),
              parts.host != nil, parts.user == nil, parts.password == nil, parts.fragment == nil,
              port(parts) == port(base), parts.percentEncodedPath == parts.path else { return nil }
        let prefix = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let directory = prefix.isEmpty ? "/avatars/" : "/\(prefix)/avatars/"
        guard parts.path.hasPrefix(directory) else { return nil }
        let file = String(parts.path.dropFirst(directory.count))
        guard file.range(of: "^[A-Za-z0-9_-]+\\.(png|jpg|webp)$", options: .regularExpression) != nil else { return nil }
        let query = parts.queryItems ?? []
        guard query.count <= 1, query.allSatisfy({ item in
            guard item.name == "v", let value = item.value, !value.isEmpty else { return false }
            return value.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        return url
    }

    private static func port(_ parts: URLComponents) -> Int? {
        parts.port ?? (parts.scheme?.lowercased() == "https" ? 443 : parts.scheme?.lowercased() == "http" ? 80 : nil)
    }
}
