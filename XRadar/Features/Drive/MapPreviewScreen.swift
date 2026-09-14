import SwiftUI
import XRadarCore
import XRadarData

/// Temporary main screen until the drive screen lands (step 9): the real map, with the radars,
/// reports and signs around the driver loaded once from the backend, to check the map on an
/// iPhone. The drive screen will load and refresh them the way Android does. The verification
/// screen opens from here.
struct MapPreviewScreen: View {
    let services: AppServices

    @State private var following = true
    @State private var content = DriveMapContent()
    @State private var loaded = false
    @State private var showCheck = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DriveMapView(
                location: services.location.location,
                content: content,
                following: following,
                mapStyle: services.preferences.settings.mapStyle,
                stadiaAPIKey: services.configuration.stadiaAPIKey,
                onUserGesture: { following = false }
            )
            .ignoresSafeArea()

            VStack(spacing: XRadarSpacing.md) {
                if !following {
                    XRadarIconButton(icon: .symbol(.recenter), label: "Recentrer", size: 56, tint: XRadarColor.accent) {
                        following = true
                    }
                }
                XRadarIconButton(icon: .symbol(.diagnostic), label: "Vérification", size: 56) {
                    showCheck = true
                }
            }
            .padding(XRadarSpacing.lg)
            .animation(.snappy, value: following)
        }
        .sheet(isPresented: $showCheck) {
            PlatformCheckView(services: services)
        }
        .task(id: services.location.location != nil) {
            await loadAround()
        }
    }

    private func loadAround() async {
        guard !loaded, let fix = services.location.location else { return }
        loaded = true
        let client = services.client
        async let radars = try? RadarAPI(client: client).near(lat: fix.latitude, lon: fix.longitude, radiusM: 50_000)
        async let reports = try? ReportsAPI(client: client).near(lat: fix.latitude, lon: fix.longitude, radiusM: 20_000)
        async let signs = SignAPI(client: client).near(lat: fix.latitude, lon: fix.longitude, radiusM: 10_000)
        let (foundRadars, foundReports, foundSigns) = await (radars, reports, signs)
        content.radars = foundRadars ?? []
        content.reports = foundReports?.reports ?? []
        content.zones = foundReports?.zones ?? []
        content.signs = foundSigns
    }
}
