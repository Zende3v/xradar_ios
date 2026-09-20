import SwiftUI

@main
struct EonaApp: App {
    @State private var services = AppServices(configuration: .current)

    var body: some Scene {
        WindowGroup {
            AppRoot(services: services)
                .tint(EonaColor.accent)
                .task {
                    await services.account.refresh()
                }
        }
    }
}
