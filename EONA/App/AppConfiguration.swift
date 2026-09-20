import Foundation
import EonaData

/// Build-time configuration, injected through the xcconfig files into Info.plist.
struct AppConfiguration {
    let backend: BackendConfiguration

    init(info: [String: Any]) {
        backend = BackendConfiguration(string: info["XRBackendURL"] as? String) ?? .production
    }

    static let current = AppConfiguration(info: Bundle.main.infoDictionary ?? [:])
}
