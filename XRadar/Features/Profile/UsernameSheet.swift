import SwiftUI
import XRadarCore
import XRadarData

/// "Changer de pseudo": the new name, checked as it is typed (its form at once, then the backend
/// after a pause), and saved once free. The backend answers with the account, which replaces the
/// cached one: the menu, the profile and every other screen show the new name at once.
struct UsernameSheet: View {
    let account: AccountStore

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var name: String
    @State private var check = NameCheck.unchanged
    @State private var saving = false
    @State private var error: String?

    init(account: AccountStore) {
        self.account = account
        _name = State(initialValue: account.account?.username ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nouveau pseudo", text: $name)
                        .font(.xrBody)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit { Task { await save() } }
                } footer: {
                    VStack(alignment: .leading, spacing: XRadarSpacing.xs) {
                        if let line = check.line {
                            Text(line)
                                .foregroundStyle(check.color)
                        }
                        if let error {
                            Text(error)
                                .foregroundStyle(XRadarColor.danger)
                        }
                        Text("3 à 20 caractères : lettres sans accent, chiffres, _ et . Un changement par semaine ; ton ancien pseudo reste à toi pendant 30 jours. Pour te connecter, utilise ensuite le nouveau pseudo ou ton email.")
                            .foregroundStyle(XRadarColor.textTertiary)
                    }
                    .font(.xrFootnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(XRadarColor.canvas)
            .navigationTitle("Changer de pseudo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Envoi…" : "Enregistrer") {
                        Task { await save() }
                    }
                    .disabled(check != .available || saving)
                }
            }
        }
        .onAppear { focused = true }
        .task(id: name) {
            await verify()
        }
    }

    private var candidate: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The form at once; the backend only for a well-formed new name, after a pause (typing on
    /// cancels the pending check: one request per pause).
    private func verify() async {
        error = nil
        let wanted = candidate
        guard !wanted.isEmpty, wanted != account.account?.username else {
            check = .unchanged
            return
        }
        guard UsernameRules.isWellFormed(wanted) else {
            check = .invalid
            return
        }
        check = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let answer = await account.usernameAvailability(wanted)
        guard !Task.isCancelled else { return }
        check = NameCheck(answer)
    }

    private func save() async {
        guard check == .available, !saving else { return }
        saving = true
        defer { saving = false }
        switch await account.updateProfile(username: candidate) {
        case .success:
            dismiss()
        case .failure(let message):
            // Someone may have taken it in between: the backend has the last word.
            error = message
        }
    }
}

/// Where the typed name stands.
private enum NameCheck: Equatable {
    case unchanged
    case checking
    case available
    case taken
    case reserved
    case invalid
    case unknown

    init(_ answer: UsernameAvailability?) {
        switch answer {
        case .available?: self = .available
        case .taken?: self = .taken
        case .reserved?: self = .reserved
        case .invalid?: self = .invalid
        case nil: self = .unknown
        }
    }

    var line: String? {
        switch self {
        case .unchanged: nil
        case .checking: "Vérification…"
        case .available: "Disponible"
        case .taken: "Ce pseudo est déjà pris."
        case .reserved: "Ce pseudo est réservé."
        case .invalid: "Pseudo invalide."
        case .unknown: "Vérification impossible pour l'instant, réessaie."
        }
    }

    var color: Color {
        switch self {
        case .available: XRadarColor.success
        case .unchanged, .checking: XRadarColor.textTertiary
        case .taken, .reserved, .invalid, .unknown: XRadarColor.danger
        }
    }
}
