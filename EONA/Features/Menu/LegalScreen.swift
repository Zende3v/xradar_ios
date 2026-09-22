import SwiftUI

/// "À propos": the privacy policy, and where the map, the places and the figures come from.
/// On the map, the Plans credits are only a tiny line at the bottom (Arthur's choice).
struct LegalScreen: View {
    /// What was accepted, and when: shown under the terms row.
    var acceptedVersion: String?
    var acceptedAt: Date?

    /// The privacy policy, served by the backend machine through Cloudflare Tunnel.
    static let privacy = URL(string: "https://confidentialite.zylo-app.fr/")!
    static let appleData = URL(string: "https://gspe21-ssl.ls.apple.com/html/attribution.html")!
    private static let appleTerms = URL(string: "https://www.apple.com/legal/internet-services/maps/terms-en.html")!
    private static let openStreetMap = URL(string: "https://www.openstreetmap.org/copyright")!
    private static let fuelPrices = URL(string: "https://www.prix-carburants.gouv.fr/")!
    private static let addresses = URL(string: "https://adresse.data.gouv.fr/")!
    private static let routing = URL(string: "https://openrouteservice.org/")!
    private static let radars = URL(string: "https://www.data.gouv.fr/")!

    /// "Version 1.0 · acceptées le 22/09/2026", ou l'invitation à les lire.
    private var termsSubtitle: String {
        guard let acceptedVersion, !acceptedVersion.isEmpty else { return "Le texte qui encadre l'usage d'EONA" }
        guard let acceptedAt else { return "Version (acceptedVersion) acceptée" }
        return "Version (acceptedVersion) · acceptées le " + acceptedAt.formatted(date: .numeric, time: .omitted)
    }

    var body: some View {
        Form {
            Section {
                source("Politique de confidentialité", "Données collectées, durées de conservation et droits (RGPD)", Self.privacy)
                NavigationLink {
                    TermsTextScreen()
                } label: {
                    EonaListRow(title: "Conditions générales d'utilisation", subtitle: termsSubtitle, icon: .symbol(.info), tint: EonaColor.accent)
                }
            }

            Section {
                Text("Cartes : Plans d'Apple (MapKit). © Apple et ses fournisseurs de données.")
                    .font(.xrSubhead)
                    .foregroundStyle(EonaColor.textSecondary)
                source("Fournisseurs de données de Plans", "Mentions légales de la carte", Self.appleData)
                source("Conditions d'utilisation de Plans", "Apple", Self.appleTerms)
            } header: {
                Text("Apple")
            }

            Section {
                source("© contributeurs OpenStreetMap", "Services autour, horaires, signalisation et limitations (ODbL)", Self.openStreetMap)
                source("prix-carburants.gouv.fr", "Prix officiels des carburants", Self.fuelPrices)
                source("Base Adresse Nationale", "Recherche d'adresses", Self.addresses)
                source("openrouteservice", "Calcul des itinéraires (© HeiGIT, données OpenStreetMap)", Self.routing)
                source("data.gouv.fr", "Position des radars automatiques", Self.radars)
            } header: {
                Text("Autres")
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("À propos")
    }

    private func source(_ title: String, _ detail: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textPrimary)
                Text(detail)
                    .font(.xrFootnote)
                    .foregroundStyle(EonaColor.textTertiary)
            }
        }
    }
}
