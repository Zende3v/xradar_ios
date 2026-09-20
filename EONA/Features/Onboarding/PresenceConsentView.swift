import SwiftUI
import EonaData

/// Asked once, after onboarding: does the driver agree to share their position with the EONA
/// team? The wording says plainly what is shared and for how long — a consent that is not
/// informed is worth nothing, and the driver who feels tricked leaves. "Plus tard" is a real
/// answer, as reachable as the other, and everything is reversible from Confidentialité.
struct PresenceConsentView: View {
    let preferences: PreferencesStore
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: EonaSpacing.lg) {
            Spacer(minLength: 0)

            Image(EonaSymbol.privacy)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(EonaColor.accent)

            VStack(spacing: EonaSpacing.sm) {
                Text("Partager ta position avec l'équipe")
                    .font(.xrTitle)
                    .foregroundStyle(EonaColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Pendant que l'app est ouverte, l'équipe EONA voit où tu es. Ça nous sert à comprendre un bug que tu signales et à vérifier les alertes sur le terrain.")
                    .font(.xrBody)
                    .foregroundStyle(EonaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: EonaSpacing.sm) {
                point("Ta position est effacée au bout de 30 jours.")
                point("Elle n'est jamais vendue, ni montrée aux autres conducteurs.")
                point("Tu peux l'arrêter quand tu veux dans Menu ▸ Confidentialité.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: EonaSpacing.sm) {
                EonaButton(title: "Activer", fillWidth: true) {
                    preferences.updateSettings {
                        $0.presence = true
                        $0.presenceAsked = true
                    }
                    onDone()
                }
                EonaButton(title: "Plus tard", variant: .secondary, fillWidth: true) {
                    preferences.updateSettings { $0.presenceAsked = true }
                    onDone()
                }
            }
        }
        .padding(EonaSpacing.lg)
        .background(EonaColor.canvas)
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.sm) {
            Image(EonaSymbol.check)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EonaColor.success)
            Text(text)
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textSecondary)
        }
    }
}
