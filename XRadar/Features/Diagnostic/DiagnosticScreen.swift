import SwiftUI
import XRadarCore
import XRadarData

/// Backend diagnostic (admin): the backend address, the GPS fix, and a check of each endpoint.
struct DiagnosticScreen: View {
    let services: AppServices

    @State private var running = false
    @State private var results: [CheckResult] = []

    var body: some View {
        Form {
            Section("Adresse du backend") {
                Text(BackendDiagnostics(client: services.client).baseURL.absoluteString)
                    .font(.xrFootnote.monospaced())
                    .foregroundStyle(XRadarColor.textSecondary)
                    .textSelection(.enabled)
            }

            Section("GPS") {
                Text(gpsText)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textSecondary)
            }

            Section {
                XRadarButton(title: running ? "Test en cours…" : "Relancer le test", loading: running, fillWidth: true) {
                    Task { await runChecks() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(results, id: \.name) { result in
                Section {
                    VStack(alignment: .leading, spacing: XRadarSpacing.sm) {
                        HStack(spacing: XRadarSpacing.sm) {
                            Image(result.ok ? XRadarSymbol.check : XRadarSymbol.close)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(result.ok ? XRadarColor.success : XRadarColor.danger)
                            Text(result.name)
                                .font(.xrHeadline)
                                .foregroundStyle(XRadarColor.textPrimary)
                        }
                        Text(result.detail)
                            .font(.xrFootnote)
                            .foregroundStyle(XRadarColor.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(XRadarColor.canvas)
        .navigationTitle("Diagnostic backend")
        .task { await runChecks() }
    }

    private func runChecks() async {
        guard !running else { return }
        running = true
        results = await BackendDiagnostics(client: services.client).run()
        running = false
    }

    private var gpsText: String {
        let signal: String = switch services.location.signal {
        case .searching: "recherche"
        case .good: "bon"
        case .weak: "faible"
        case .lost: "perdu"
        }
        guard let fix = services.location.location else {
            return "Pas encore de position (\(signal)) — sans fix GPS, l'app ne charge pas les radars."
        }
        return "Fix OK (\(signal)) — \(String(format: "%.5f", fix.latitude)), \(String(format: "%.5f", fix.longitude))"
    }
}
