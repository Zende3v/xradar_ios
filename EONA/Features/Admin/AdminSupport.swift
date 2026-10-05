import Foundation
import Observation
import SwiftUI
import EonaData

/// Un refus ferme simultanément contenu de toutes pages du pilotage.
@Observable
final class AdminAccessState {
    var denied: String?

    func permits(_ services: AppServices) -> Bool {
        denied == nil && services.account.token != nil && services.account.account?.role == .admin && services.account.account?.isRestricted != true
    }

    func receive(_ error: Error, services: AppServices) async -> String? {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        if let refusal = error as? AdminAPIError {
            switch refusal {
            case .unauthorized, .forbidden:
                denied = refusal.localizedDescription
                await services.account.reload()
            default: break
            }
            return refusal.localizedDescription
        }
        return "Connexion impossible. Réessaie."
    }
}

struct AdminGate<Content: View>: View {
    let services: AppServices
    let access: AdminAccessState
    private let content: () -> Content

    init(services: AppServices, access: AdminAccessState, @ViewBuilder content: @escaping () -> Content) {
        self.services = services
        self.access = access
        self.content = content
    }

    var body: some View {
        if access.permits(services) { content() }
        else {
            AdminNotice(title: "Accès administrateur", message: access.denied ?? "Session administrateur requise.")
                .padding(EonaSpacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct AdminNotice: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            Text(title).font(.xrHeadline).foregroundStyle(EonaPlusStyle.primary)
            Text(message).font(.xrSubhead).foregroundStyle(EonaPlusStyle.secondary)
            if let retry {
                Button("Réessayer", action: retry)
                    .font(.xrBodyStrong)
                    .foregroundStyle(EonaPlusStyle.lavender)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdminLoading: View {
    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            ProgressView().tint(EonaPlusStyle.lavender)
            Text("Chargement…").font(.xrSubhead).foregroundStyle(EonaPlusStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EonaSpacing.lg)
    }
}

struct AdminSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.md) {
            EonaPlusLabel(title).padding(.leading, EonaSpacing.lg)
            EonaPlusGroup { VStack(alignment: .leading, spacing: 0) { content } }
        }
    }
}

struct AdminValueRow: View {
    let title: String
    let value: String
    var color: Color = EonaPlusStyle.primary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: EonaSpacing.xs) { label; amount }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: EonaSpacing.md) {
                    label
                    Spacer(minLength: EonaSpacing.sm)
                    amount.multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(EonaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: some View { Text(title).font(.xrSubhead).foregroundStyle(EonaPlusStyle.secondary) }
    private var amount: some View {
        Text(value).font(.xrBodyStrong).monospacedDigit().foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AdminNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = EonaPlusStyle.lavender

    var body: some View {
        HStack(spacing: EonaSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.14), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EonaSpacing.xs) {
                Text(title).font(.xrBodyStrong).foregroundStyle(EonaPlusStyle.primary)
                Text(subtitle).font(.xrFootnote).foregroundStyle(EonaPlusStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: EonaSpacing.sm)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(EonaPlusStyle.muted)
                .accessibilityHidden(true)
        }
        .padding(EonaSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct AdminPageStyle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .background(EonaPlusStyle.canvas.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .tint(EonaPlusStyle.lavender)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .scrollEdgeEffectHidden(true, for: .all)
    }
}

extension View {
    func adminPage(_ title: String) -> some View { modifier(AdminPageStyle(title: title)) }
}

enum AdminFormat {
    static func count(_ value: Int?) -> String { value.map { $0.formatted(.number.locale(Locale(identifier: "fr_FR"))) } ?? "—" }
    static func euros(_ value: Double?) -> String {
        value.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR"))) } ?? "—"
    }
    static func milliseconds(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) ms" } ?? "—" }
    static func date(_ text: String?) -> String {
        guard let text else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: text) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }()
        return date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }
    static func role(_ role: String) -> String {
        switch role { case "guest": "Invité"; case "client": "Client"; case "admin": "Admin"; default: role }
    }
    static func access(_ account: AdminAccount) -> String {
        if account.banned { return "Banni" }
        if account.suspended == true || account.revoked == true { return "Suspendu" }
        if account.role == "admin" { return "Admin" }
        if account.hasPlus == true { return account.access == "trial" ? "Essai EONA+" : "EONA+" }
        return "Gratuit"
    }
}
