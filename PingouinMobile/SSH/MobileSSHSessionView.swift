import SwiftUI
import PingouinCore

/// Écran d'une session SSH : la connexion en cours, les demandes qu'elle fait (mot de passe, clé du
/// serveur), puis le terminal et les fichiers.
struct MobileSSHSessionView: View {
    @Environment(MobileAppState.self) private var state
    let model: MobileSSHViewModel
    @Bindable var session: MobileSSHSession
    @State private var password = ""
    @State private var keepsPassword = true
    @FocusState private var isTypingPassword: Bool

    var body: some View {
        content
            .background { PingouinBackdrop() }
            .navigationTitle(session.profile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if session.isOpen || session.isBusy {
                        Button(L("Déconnecter")) {
                            session.disconnect()
                        }
                    }
                }
            }
            .task {
                session.startIfNeeded()
            }
            .onChange(of: session.state) { _, newState in
                if newState == .connected, session.pane == .terminal {
                    session.terminal.focus()
                }
            }
            .onChange(of: session.pane) { _, pane in
                if pane == .terminal {
                    session.terminal.focus()
                } else {
                    session.terminal.unfocus()
                }
            }
            .onDisappear {
                session.terminal.unfocus()
            }
    }

    private var isSaved: Bool {
        model.profiles.contains { $0.id == session.id }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .idle, .connecting:
            prompt {
                ProgressView()
                Text(L("Connexion à \(session.profile.summary)…"))
                    .font(.headline)
                Button(L("Annuler")) {
                    session.disconnect()
                }
                .buttonStyle(.bordered)
            }
        case .needsPassword(let message):
            passwordPrompt(message)
        case .needsHostTrust(let keyLine):
            trustPrompt(keyLine)
        case .hostKeyChanged(let known, let presented):
            changedKey(known: known, presented: presented)
        case .missingDeviceKey:
            prompt {
                Label(L("Cet appareil n'a pas encore de clé"), systemImage: "key")
                    .font(.headline)
                Text(L("Cette connexion s'authentifie par la clé de l'appareil. La créer, déposer sa partie publique sur le serveur, puis revenir ici."))
                    .foregroundStyle(.secondary)
                Button(L("Ouvrir « Clé de cet appareil »")) {
                    state.sshPath = [.deviceKey]
                }
                .buttonStyle(.borderedProminent)
            }
        case .connected:
            connected
        case .ended(let message):
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "bolt.horizontal.circle")
                        .font(.subheadline)
                    Button {
                        session.reconnect()
                    } label: {
                        Text(L("Se reconnecter"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .glassCardPadded(cornerRadius: 22)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                // Ce que le terminal affichait reste lisible après la fermeture.
                terminal
                    .opacity(0.75)
            }
        }
    }

    // MARK: Session ouverte

    private var connected: some View {
        VStack(spacing: 8) {
            Picker(L("Affichage"), selection: $session.pane) {
                Text(L("Terminal")).tag(MobileSSHPane.terminal)
                Text(L("Fichiers")).tag(MobileSSHPane.files)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            switch session.pane {
            case .terminal:
                terminal
            case .files:
                MobileSFTPView(browser: session.files)
            }
        }
    }

    private var terminal: some View {
        MobileTerminalHostView(controller: session.terminal)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .accessibilityLabel(L("Terminal"))
    }

    // MARK: Demandes

    /// Carte centrée dans l'écran, pour une demande ou une attente.
    private func prompt<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .glassCardPadded(cornerRadius: 22)
            .padding(16)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func passwordPrompt(_ message: String?) -> some View {
        prompt {
            Text(L("Mot de passe de \(session.profile.destination)"))
                .font(.headline)
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            SecureField(L("Mot de passe"), text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .submitLabel(.go)
                .focused($isTypingPassword)
                .onSubmit(submitPassword)
            if isSaved {
                Toggle(L("Garder le mot de passe dans le Trousseau"), isOn: $keepsPassword)
            } else {
                Text(L("Connexion rapide : le mot de passe n'est conservé nulle part."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: submitPassword) {
                Text(L("Se connecter"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty)
            Button {
                password = ""
                session.cancelPrompt()
            } label: {
                Text(L("Annuler"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .onAppear {
            isTypingPassword = true
        }
    }

    private func submitPassword() {
        let typed = password
        // Le mot de passe ne reste pas dans le champ une fois transmis.
        password = ""
        session.submit(password: typed, keep: isSaved && keepsPassword)
    }

    private func trustPrompt(_ keyLine: String) -> some View {
        let type = OpenSSHPublicKey.keyType(ofLine: keyLine) ?? "—"
        return prompt {
            Text(L("Première connexion à cet hôte"))
                .font(.title3.weight(.bold))
            Text(L("Pingouin ne connaît pas encore \(session.profile.host). Vérifier que cette empreinte est bien celle du serveur avant de continuer."))
                .foregroundStyle(.secondary)
            fingerprint(L("Empreinte de la clé (\(type), SHA-256)"), keyLine)
            Text(L("Sur le serveur : \(Self.checkCommand(for: type))"))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button {
                session.trustHostAndConnect()
            } label: {
                Text(L("Faire confiance et se connecter"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button {
                session.cancelPrompt()
            } label: {
                Text(L("Annuler"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// La clé du serveur n'est plus celle qui avait été acceptée : aucun bouton ne permet de passer outre.
    private func changedKey(known: String, presented: String) -> some View {
        prompt {
            Label(L("La clé de ce serveur a changé"), systemImage: "exclamationmark.octagon")
                .font(.title3.weight(.bold))
                .foregroundStyle(.red)
            Text(L("La connexion à \(session.profile.host) est refusée. Soit le serveur a été réinstallé, soit quelqu'un se fait passer pour lui."))
            fingerprint(L("Empreinte acceptée auparavant"), known)
            fingerprint(L("Empreinte présentée aujourd'hui"), presented)
            Text(L("Si le changement est attendu, retirer cet hôte dans Réglages › SSH › Hôtes connus, puis se reconnecter : la nouvelle empreinte sera alors demandée."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func fingerprint(_ label: String, _ keyLine: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(OpenSSHPublicKey.fingerprint(ofLine: keyLine) ?? L("Empreinte illisible"))
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .accessibilityElement(children: .combine)
    }

    /// Commande qui affiche, sur le serveur, l'empreinte de sa clé de ce type.
    private static func checkCommand(for type: String) -> String {
        let file: String
        switch type {
        case "ssh-ed25519": file = "ssh_host_ed25519_key.pub"
        case "ssh-rsa", "rsa-sha2-256", "rsa-sha2-512": file = "ssh_host_rsa_key.pub"
        case let name where name.hasPrefix("ecdsa-"): file = "ssh_host_ecdsa_key.pub"
        default: file = "ssh_host_*_key.pub"
        }
        return "ssh-keygen -lf /etc/ssh/" + file
    }
}
