import SwiftUI

@main
struct XRadarApp: App {
    @State private var services = AppServices(configuration: .current)

    var body: some Scene {
        WindowGroup {
            AppRoot(services: services)
                .tint(XRadarColor.accent)
                .task {
                    await services.account.refresh()
                }
        }
    }
}
