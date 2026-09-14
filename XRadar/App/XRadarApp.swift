import SwiftUI

@main
struct XRadarApp: App {
    @State private var services = AppServices(configuration: .current)

    var body: some Scene {
        WindowGroup {
            AppRoot(services: services)
                .preferredColorScheme(services.preferences.settings.themeMode.colorScheme)
                .tint(XRadarColor.accent)
                .task {
                    await services.account.refresh()
                }
        }
    }
}
