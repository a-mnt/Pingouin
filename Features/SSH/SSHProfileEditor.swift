import AppKit
import SwiftUI
import PingouinCore

/// Feuille de création ou de modification d'une connexion.
struct SSHProfileEditor: View {
    @Bindable var model: SSHViewModel
    @State private var showsPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.draftIsNew ? L("Nouvelle connexion") : L("Modifier la connexion"))
                .font(.title3.weight(.bold))

            Form {
                TextField(L("Nom affiché"), text: $model.draft.name, prompt: Text(L("Facultatif")))
                TextField(L("Hôte"), text: $model.draft.host, prompt: Text("192.168.1.20"))
                    .autocorrectionDisabled()
                TextField(L("Port"), text: $model.draftPortText)
                TextField(L("Utilisateur"), text: $model.draft.user, prompt: Text(L("Celui de ce Mac si vide")))
                    .autocorrectionDisabled()
                HStack {
                    TextField(L("Fichier de clé"), text: $model.draft.identityFile, prompt: Text(L("Clés habituelles et agent SSH si vide")))
                        .autocorrectionDisabled()
                    Button(L("Choisir…")) {
                        chooseKeyFile()
                    }
                }
                HStack {
                    if showsPassword {
                        TextField(L("Mot de passe"), text: $model.draftPassword)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                    } else {
                        SecureField(
                            L("Mot de passe"),
                            text: $model.draftPassword,
                            prompt: Text(model.draftHasSavedPassword ? L("Enregistré — laisser vide pour le garder") : L("Facultatif"))
                        )
                    }
                    Button {
                        // Afficher relit d'abord le mot de passe enregistré, s'il y en a un.
                        if !showsPassword {
                            model.loadSavedPasswordIntoDraft()
                        }
                        showsPassword.toggle()
                    } label: {
                        Label(showsPassword ? L("Masquer le mot de passe") : L("Afficher le mot de passe"), systemImage: showsPassword ? "eye.slash" : "eye")
                            .labelStyle(.iconOnly)
                    }
                    .help(showsPassword ? L("Masquer le mot de passe") : L("Afficher le mot de passe"))
                }
                if model.draftHasSavedPassword {
                    Toggle(L("Supprimer le mot de passe enregistré"), isOn: $model.draftRemovesPassword)
                        .disabled(!model.draftPassword.isEmpty)
                }
                Picker(L("Couleurs"), selection: Binding(
                    get: { model.draft.themeID ?? "" },
                    set: { model.draft.themeID = $0.isEmpty ? nil : $0 }
                )) {
                    Text(L("Thème par défaut")).tag("")
                    ForEach(TerminalTheme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
            }
            .formStyle(.grouped)

            Text(L("Le mot de passe est gardé dans le Trousseau de macOS et saisi à votre place quand le serveur le demande. Pour la clé, seul le chemin du fichier est enregistré."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = model.draftError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L("Annuler"), role: .cancel) {
                    model.isEditing = false
                }
                .keyboardShortcut(.cancelAction)
                Button(L("Enregistrer")) {
                    model.commitDraft()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
        panel.message = L("Choisir le fichier de clé privée")
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.identityFile = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
