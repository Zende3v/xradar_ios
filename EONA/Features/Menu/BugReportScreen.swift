import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import EonaCore
import EonaData

/// "Signaler un bug": what happened (required), how to see it again (optional), a category. The
/// account is the author and the app adds its own details, and for navigation the trip (D7.4):
/// nothing else is asked. The form only opens with the car stopped; the draft waits meanwhile.
struct BugReportScreen: View {
    let services: AppServices

    @Environment(\.dismiss) private var dismiss
    @State private var category = BugCategory.other
    @State private var description = ""
    @State private var steps = ""
    @State private var sending = false
    @State private var photo: PhotosPickerItem?
    @State private var screenshot: Data?
    @State private var loadingScreenshot = false
    @State private var message: String?

    private static let minLength = 10
    private static let maxLength = 1000
    /// At this speed or more the car is moving (m/s): the form waits for a stop.
    private static let movingMps = 1.5
    /// Navigation reports always carry the trip, even with driving stats off (journal P1.4): say so.
    private static let tripNote = " Le trajet en cours (ou le dernier) et son itinéraire sont joints."

    private var details: BugAppDetails { BugReportScreen.appDetails() }
    private var ready: Bool { description.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minLength && !sending && !loadingScreenshot }
    /// Driving: never a form to fill. No position, no speed known, or the signal searching or lost
    /// (the last speed is stale): nothing stops it.
    private var moving: Bool {
        let signal = services.location.signal
        guard signal != .searching, signal != .lost else { return false }
        return (services.location.location?.speedMps ?? 0) >= Self.movingMps
    }

    var body: some View {
        Group {
            if moving {
                EonaMessageState(
                    icon: .symbol(.bug),
                    title: "Disponible à l'arrêt",
                    message: "Pour ta sécurité, le formulaire s'ouvre quand la voiture est arrêtée. Il s'affichera ici dès l'arrêt."
                )
            } else {
                form
            }
        }
        .background(EonaColor.canvas)
        .navigationTitle("Signaler un bug")
    }

    private var form: some View {
        Form {
            Section("Catégorie") {
                Picker("Catégorie", selection: $category) {
                    ForEach(BugCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(EonaColor.accent)
            }
            Section {
                editor($description, prompt: "Ce qui ne va pas, en quelques mots")
            } header: {
                Text("Que s'est-il passé ?")
            }
            Section {
                editor($steps, prompt: "Facultatif : ce que tu faisais juste avant")
            } header: {
                Text("Comment le reproduire ?")
            } footer: {
                Text("Envoyé avec ton compte et \(details.platform) \(details.os) · EONA \(details.version) · \(details.model).\(category == .navigation ? Self.tripNote : "")")
            }
            Section("Capture (facultative)") {
                if let screenshot, let image = UIImage(data: screenshot) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                        .accessibilityLabel("Capture jointe")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Text(loadingScreenshot ? "Préparation…" : screenshot == nil ? "Ajouter une capture" : "Changer la capture")
                }
                .disabled(sending || loadingScreenshot)
                if screenshot != nil {
                    Button("Retirer la capture") { photo = nil; screenshot = nil }
                        .disabled(sending || loadingScreenshot)
                }
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    Text(sending ? "Envoi…" : "Envoyer")
                        .font(.xrBodyStrong)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!ready)
            } footer: {
                if let message {
                    Text(message).foregroundStyle(EonaColor.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task(id: photo) {
            if let photo { await loadScreenshot(photo) }
        }
    }

    private func editor(_ text: Binding<String>, prompt: String) -> some View {
        TextField(prompt, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(Self.maxLength)) }), axis: .vertical)
            .font(.xrBody)
            .lineLimit(3...8)
    }

    private func loadScreenshot(_ item: PhotosPickerItem) async {
        loadingScreenshot = true
        message = nil
        defer { loadingScreenshot = false }
        guard let data = try? await item.loadTransferable(type: Data.self), !Task.isCancelled else {
            if !Task.isCancelled { message = "Capture illisible. Choisis une autre image." }
            return
        }
        let encoded = await Task.detached(priority: .userInitiated) {
            Self.encodeScreenshot(data)
        }.value
        guard !Task.isCancelled, photo == item else { return }
        if let encoded { screenshot = encoded }
        else { message = "Capture illisible. Choisis une autre image." }
    }

    /// ImageIO prépare miniature orientée sans décoder original complet.
    nonisolated private static func encodeScreenshot(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
              ] as CFDictionary) else { return nil }
        let thumbnail = UIImage(cgImage: image)
        for quality in [CGFloat(0.8), 0.65, 0.5] {
            if let jpeg = thumbnail.jpegData(compressionQuality: quality), jpeg.count <= 1024 * 1024 { return jpeg }
        }
        return nil
    }

    private func send() async {
        sending = true
        message = nil
        let outcome = await BugAPI(client: services.client).send(
            category: category,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps.trimmingCharacters(in: .whitespacesAndNewlines),
            app: details,
            // Navigation: the engine, the map and the trip, as they stand when it goes.
            context: category == .navigation ? services.bugContext.current() : nil,
            screenshot: screenshot,
            token: services.account.token
        )
        sending = false
        switch outcome {
        case .sent: dismiss()
        case .tooMany: message = "Beaucoup de rapports envoyés récemment : réessaie plus tard."
        case .failed: message = "Envoi impossible pour l'instant. Vérifie ta connexion et réessaie."
        }
    }

    /// The platform, the system, the app's version and the exact model ("iPhone16,2").
    static func appDetails() -> BugAppDetails {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return BugAppDetails(
            platform: "iOS",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            os: UIDevice.current.systemVersion,
            model: model.isEmpty ? UIDevice.current.model : model
        )
    }
}

/// "Rapports de bugs" (admins): the most recent first, by status, a page at a time; each one
/// opens on its details and its status.
struct BugListScreen: View {
    let services: AppServices

    @State private var filter: BugStatus? = .new
    @State private var reports: [BugReport] = []
    @State private var loading = false
    @State private var failed = false
    @State private var more = false

    var body: some View {
        List {
            Section {
                Picker("Statut", selection: $filter) {
                    Text("Nouveaux").tag(BugStatus?.some(.new))
                    Text("En cours").tag(BugStatus?.some(.progress))
                    Text("Résolus").tag(BugStatus?.some(.resolved))
                    Text("Tous").tag(BugStatus?.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if failed && reports.isEmpty {
                Text("Chargement impossible. Tire vers le bas pour réessayer.")
                    .foregroundStyle(EonaColor.textSecondary)
            } else if !loading && reports.isEmpty {
                Text("Aucun rapport.")
                    .foregroundStyle(EonaColor.textSecondary)
            }
            ForEach(reports) { report in
                NavigationLink {
                    BugDetailScreen(services: services, report: report) { updated in
                        reports = reports.map { $0.id == updated.id ? updated : $0 }
                    }
                } label: {
                    BugRow(report: report)
                }
            }
            if more {
                Button("Plus anciens") { Task { await load(reset: false) } }
                    .disabled(loading)
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle("Rapports de bugs")
        .task(id: filter) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        loading = true
        let page = await BugAPI(client: services.client).list(status: filter, before: reset ? nil : reports.last?.createdAt, token: services.account.token)
        loading = false
        failed = page == nil
        guard let page else { return }
        reports = reset ? page : reports + page
        more = page.count >= Self.pageSize
    }

    /// The backend's page (bugPage).
    private static let pageSize = 50
}

private struct BugRow: View {
    let report: BugReport

    var body: some View {
        VStack(alignment: .leading, spacing: EonaSpacing.xs) {
            HStack {
                Text(report.category.label)
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.accent)
                Spacer(minLength: 0)
                Text(report.status.label)
                    .font(.xrCaption)
                    .foregroundStyle(EonaColor.textSecondary)
            }
            Text(report.description)
                .font(.xrBody)
                .foregroundStyle(EonaColor.textPrimary)
                .lineLimit(2)
            Text("\(AccountLabels.shortDate(report.createdAt)) · \(report.author ?? "Compte supprimé") · \(report.app.platform) \(report.app.version)")
                .font(.xrFootnote)
                .foregroundStyle(EonaColor.textTertiary)
        }
        .padding(.vertical, EonaSpacing.xs)
    }
}

/// One report in full, and its status.
private struct BugDetailScreen: View {
    let services: AppServices
    @State var report: BugReport
    let onChange: (BugReport) -> Void

    @State private var saving = false
    @State private var screenshot: Data?
    @State private var loadingScreenshot = false

    var body: some View {
        Form {
            Section("Description") {
                Text(report.description).textSelection(.enabled)
            }
            if let steps = report.steps {
                Section("Reproduction") {
                    Text(steps).textSelection(.enabled)
                }
            }
            if report.hasScreenshot {
                Section("Capture") {
                    if let screenshot, let image = UIImage(data: screenshot) {
                        Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Capture du rapport")
                    } else if loadingScreenshot {
                        ProgressView("Chargement…")
                    } else {
                        Button("Recharger la capture") { Task { await loadScreenshot() } }
                    }
                }
            }
            Section("Détails") {
                LabeledContent("Catégorie", value: report.category.label)
                LabeledContent("Auteur", value: report.author ?? "Compte supprimé")
                LabeledContent("Date", value: AccountLabels.shortDate(report.createdAt))
                LabeledContent("App", value: "\(report.app.platform) \(report.app.os) · \(report.app.version)")
                LabeledContent("Appareil", value: report.app.model)
            }
            Section("Statut") {
                Picker("Statut", selection: Binding(get: { report.status }, set: { status in Task { await set(status) } })) {
                    ForEach(BugStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(saving)
            }
        }
        .scrollContentBackground(.hidden)
        .background(EonaColor.canvas)
        .navigationTitle(report.category.label)
        .task(id: report.id) { if report.hasScreenshot { await loadScreenshot() } }
    }

    private func loadScreenshot() async {
        loadingScreenshot = true
        let data = await BugAPI(client: services.client).screenshot(of: report.id, token: services.account.token)
        screenshot = data.flatMap { UIImage(data: $0) == nil ? nil : $0 }
        loadingScreenshot = false
    }

    private func set(_ status: BugStatus) async {
        guard status != report.status else { return }
        saving = true
        if await BugAPI(client: services.client).setStatus(status, of: report.id, token: services.account.token) {
            report = BugReport(
                id: report.id, status: status, category: report.category, description: report.description,
                steps: report.steps, createdAt: report.createdAt, author: report.author, app: report.app, hasScreenshot: report.hasScreenshot
            )
            onChange(report)
        }
        saving = false
    }
}
