import SwiftUI

@main
struct EonaApp: App {
    @State private var services = AppServices(configuration: .current)
    /// The trip someone shared, opened from "eona://t/<jeton>".
    @State private var followToken: String?

    var body: some Scene {
        WindowGroup {
            AppRoot(services: services, followToken: $followToken)
                .tint(EonaColor.accent)
                .task {
                    await services.account.refresh()
                }
                .onOpenURL { url in
                    guard url.scheme == "eona", url.host() == "t" else { return }
                    let token = url.pathComponents.filter { $0 != "/" }.first ?? ""
                    if !token.isEmpty { followToken = token }
                }
        }
    }
}
