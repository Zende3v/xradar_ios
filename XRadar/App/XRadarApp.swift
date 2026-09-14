import SwiftUI

@main
struct XRadarApp: App {
    @State private var services = AppServices(configuration: .current)

    var body: some Scene {
        WindowGroup {
            RootView(services: services)
                .task {
                    services.account.restore()
                    services.locationTracker.start()
                    await services.account.refresh()
                }
        }
    }
}
