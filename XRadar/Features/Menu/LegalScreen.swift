import SwiftUI

/// Mentions légales: where the map, the places and the figures come from. The Plans logo and legal
/// link live here instead of on the map (Arthur's choice).
struct LegalScreen: View {
    private static let appleData = URL(string: "https://gspe21-ssl.ls.apple.com/html/attribution.html")!
    private static let appleTerms = URL(string: "https://www.apple.com/legal/internet-services/maps/terms-en.html")!
    private static let openStreetMap = URL(string: "https://www.openstreetmap.org/copyright")!
    private static let fuelPrices = URL(string: "https://www.prix-carburants.gouv.fr/")!
    private static let addresses = URL(string: "https://adresse.data.gouv.fr/")!
    private static let routing = URL(string: "https://openrouteservice.org/")!
    private static let radars = URL(string: "https://www.data.gouv.fr/")!

    var body: some View {
        Form {
            Section {
                Text("Cartes : Plans d'Apple (MapKit). © Apple et ses fournisseurs de données.")
                    .font(.xrSubhead)
                    .foregroundStyle(XRadarColor.textSecondary)
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
        .background(XRadarColor.canvas)
        .navigationTitle("Mentions légales")
    }

    private func source(_ title: String, _ detail: String, _ url: URL) -> some View {
        Link(destination: url) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.xrBody)
                    .foregroundStyle(XRadarColor.textPrimary)
                Text(detail)
                    .font(.xrFootnote)
                    .foregroundStyle(XRadarColor.textTertiary)
            }
        }
    }
}
