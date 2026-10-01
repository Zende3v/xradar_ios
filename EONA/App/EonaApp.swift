import SwiftUI
import UIKit

@main
struct EonaApp: App {
    @State private var services = AppServices(configuration: .current)
    /// The trip someone shared, opened from "eona://t/<jeton>".
    @State private var followToken: String?
    /// A group trip shared to be watched, opened from "eona://g/<jeton>".
    @State private var watchToken: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRoot(services: services, followToken: $followToken, watchToken: $watchToken)
                .tint(EonaColor.accent)
                .task {
                    await services.account.refresh()
                }
                // App au premier plan : écran jamais en veille. Ailleurs : réglage iOS normal.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
                .onOpenURL { url in
                    guard url.scheme == "eona", let kind = url.host() else { return }
                    let token = url.pathComponents.filter { $0 != "/" }.first ?? ""
                    guard !token.isEmpty else { return }
                    // "t" : un conducteur. "g" : un groupe.
                    if kind == "t" { followToken = token }
                    if kind == "g" { watchToken = token }
                }
        }
    }
}
