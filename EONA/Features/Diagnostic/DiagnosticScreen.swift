import SwiftUI
import EonaCore
import EonaData

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
                    .foregroundStyle(EonaColor.textSecondary)
                    .textSelection(.enabled)
            }

            Section("GPS") {
                Text(gpsText)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textSecondary)
            }

            Section {
                EonaButton(title: running ? "Test en cours…" : "Relancer le test", loading: running, fillWidth: true) {
                    Task { await runChecks() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            ForEach(results, id: \.name) { result in
                Section {
                    VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                        HStack(spacing: EonaSpacing.sm) {
                            Image(result.ok ? EonaSymbol.check : EonaSymbol.close)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(result.ok ? EonaColor.success : EonaColor.danger)
                            Text(result.name)
                                .font(.xrHeadline)
                                .foregroundStyle(EonaColor.textPrimary)
                        }
                        Text(result.detail)
                            .font(.xrFootnote)
                            .foregroundStyle(EonaColor.textSecondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
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
