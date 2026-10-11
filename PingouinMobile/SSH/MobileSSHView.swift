import SwiftUI
import PingouinCore

/// Onglet SSH : connexion rapide, connexions enregistrées, clé de l'appareil.
struct MobileSSHView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: MobileSSHViewModel
    @State private var pendingRemoval: MobileSSHProfile?
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage("SSH") {
            quick
            Text(L("Connexions enregistrées"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            if model.profiles.isEmpty {
                MobileEmptyNote(text: L("Aucune connexion enregistrée. Le bouton + en crée une."))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                        if index > 0 {
                            Divider()
                        }
                        row(profile)
                    }
                }
                .glassCardPadded(cornerRadius: 22)
                MobileFootnote(text: L("Toucher une connexion pour l'ouvrir. Appui long : modifier, dupliquer, supprimer."))
            }
            Text(L("Clé"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            NavigationLink(value: MobileSSHRoute.deviceKey) {
                MobileToolRow(
                    systemImage: "key",
                    title: L("Clé de cet appareil"),
                    detail: keyDetail,
                    isRunning: false
                )
            }
            .buttonStyle(.plain)
            MobileFootnote(text: L("Les connexions du Mac ne sont pas reprises : chaque appareil garde les siennes, et ses secrets dans son Trousseau."))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.beginAdding()
                } label: {
                    Label(L("Nouvelle connexion"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $model.isEditing) {
            MobileSSHProfileEditor(model: model)
        }
        .confirmationDialog(
            L("Supprimer la connexion « \(pendingRemoval?.displayName ?? "") » ?"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingRemoval = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                if let profile = pendingRemoval {
                    model.remove(profile.id)
                }
                pendingRemoval = nil
            }
            Button(L("Annuler"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(L("Sa session est fermée et son mot de passe est retiré du Trousseau."))
        }
        .onAppear {
            model.discardEndedQuickSessions()
        }
    }

    private var keyDetail: String {
        guard model.deviceKeyLine != nil else { return L("Aucune clé pour l'instant") }
        guard let date = model.deviceKeyCreatedAt else { return "Ed25519" }
        return L("Ed25519 · créée le \(date.formatted(date: .long, time: .omitted))")
    }

    // MARK: Connexion rapide

    private var quick: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Connexion rapide"))
                .font(.headline)
            HStack(spacing: 8) {
                TextField(L("utilisateur@hôte"), text: $model.quickTarget, prompt: Text(verbatim: "utilisateur@192.168.1.20"))
                    .hostEntry()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(openQuick)
                Button(L("Ouvrir"), action: openQuick)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.quickTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = model.quickError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text(L("Port 22, ou utilisateur@hôte:port. Le mot de passe est demandé à la connexion et n'est pas gardé."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func openQuick() {
        isEditing = false
        if let id = model.quickSession() {
            state.sshPath.append(.session(id))
        }
    }

    // MARK: Connexions enregistrées

    private func row(_ profile: MobileSSHProfile) -> some View {
        Button {
            model.session(for: profile)
            state.sshPath.append(.session(profile.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(profile.summary)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(profile.auth.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.isOpen(profile) {
                    StatusLabel(kind: .ok, text: L("Ouverte"))
                        .font(.subheadline)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Modifier…")) {
                model.beginEditing(profile.id)
            }
            Button(L("Dupliquer")) {
                model.duplicate(profile.id)
            }
            Divider()
            Button(L("Supprimer…"), role: .destructive) {
                pendingRemoval = profile
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Feuille de création ou de modification d'une connexion.
struct MobileSSHProfileEditor: View {
    @Bindable var model: MobileSSHViewModel
    @State private var sharedFile: SharedFile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Nom affiché"), text: $model.draft.name, prompt: Text(L("Facultatif")))
                    TextField(L("Hôte"), text: $model.draft.host, prompt: Text(verbatim: "192.168.1.20"))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField(L("Port"), text: $model.draftPortText, prompt: Text(verbatim: "22"))
                        .font(.body.monospaced())
                        .keyboardType(.numberPad)
                    TextField(L("Utilisateur"), text: $model.draft.user, prompt: Text(verbatim: "utilisateur"))
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                authentication
                Section {
                    Picker(L("Thème"), selection: $model.draft.themeID) {
                        Text(L("Par défaut (\(TerminalTheme.named(model.defaultThemeID).name))")).tag(String?.none)
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(Optional(theme.id))
                        }
                    }
                } header: {
                    Text(L("Terminal"))
                } footer: {
                    Text(L("La taille du texte se règle dans Réglages › SSH."))
                }
                if let error = model.draftError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(model.isEditingExisting ? L("Modifier la connexion") : L("Nouvelle connexion"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) {
                        model.draftPassword = ""
                        model.isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Enregistrer")) {
                        model.commitDraft()
                    }
                }
            }
            .sheet(item: $sharedFile) { file in
                MobileShareSheet(file: file)
            }
        }
    }

    private var authentication: some View {
        Section {
            Picker(L("Authentification"), selection: $model.draft.auth) {
                ForEach(MobileSSHAuth.allCases) { auth in
                    Text(auth.title).tag(auth)
                }
            }
            .pickerStyle(.segmented)
            switch model.draft.auth {
            case .password:
                Toggle(L("Garder le mot de passe dans le Trousseau"), isOn: $model.keepsDraftPassword)
                if model.keepsDraftPassword {
                    SecureField(
                        L("Mot de passe"),
                        text: $model.draftPassword,
                        prompt: Text(model.isEditingExisting ? L("Inchangé") : L("Demandé à la connexion si vide"))
                    )
                }
            case .deviceKey:
                if let line = model.deviceKeyLine {
                    Button(L("Copier la clé publique")) {
                        Pasteboard.copy(line)
                    }
                    Button(L("Partager la clé publique…")) {
                        sharedFile = TemporaryFile.write(Data((line + "\n").utf8), named: "pingouin-cle-publique.pub")
                    }
                } else {
                    Button(L("Créer la clé de cet appareil")) {
                        model.createDeviceKey()
                    }
                    if let message = model.deviceKeyMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text(L("Authentification"))
        } footer: {
            switch model.draft.auth {
            case .password:
                Text(L("Décoché, le mot de passe n'est conservé nulle part : il est redemandé à chaque connexion."))
            case .deviceKey:
                Text(L("Le serveur doit connaître la clé publique de cet appareil : la copier, puis l'ajouter au fichier ~/.ssh/authorized_keys du compte."))
            }
        }
    }
}
