import Foundation
import Observation
import PingouinCore

/// Session SSH d'une connexion : son état, son terminal et son navigateur de fichiers. Elle survit
/// quand on quitte son écran, tant que Pingouin reste au premier plan.
@MainActor
@Observable
final class MobileSSHSession: Identifiable {
    enum State: Equatable {
        case idle
        case connecting
        /// Le mot de passe n'est pas dans le Trousseau, ou le serveur l'a refusé.
        case needsPassword(message: String?)
        /// Première connexion : la clé du serveur attend l'accord de l'utilisateur.
        case needsHostTrust(keyLine: String)
        /// Le serveur est connu sous une autre clé : la connexion est refusée.
        case hostKeyChanged(knownKeyLine: String, presentedKeyLine: String)
        case missingDeviceKey
        case connected
        case ended(String)
    }

    let id: UUID
    private(set) var profile: MobileSSHProfile
    private(set) var state: State = .idle
    var pane: MobileSSHPane = .terminal
    let terminal = MobileTerminalController()
    let files = MobileSFTPBrowser()

    @ObservationIgnored private weak var owner: MobileSSHViewModel?
    @ObservationIgnored private var link: SSHLink?
    /// Numéro de la tentative en cours : une tentative remplacée ne touche plus à l'état.
    @ObservationIgnored private var attempt = 0
    /// Mot de passe saisi, gardé en mémoire le temps d'accepter la clé du serveur.
    @ObservationIgnored private var pendingPassword: String?
    /// Mot de passe à ranger dans le Trousseau une fois que le serveur l'a accepté.
    @ObservationIgnored private var passwordToKeep: String?

    init(profile: MobileSSHProfile, owner: MobileSSHViewModel) {
        id = profile.id
        self.profile = profile
        self.owner = owner
    }

    var isOpen: Bool { state == .connected }

    var isBusy: Bool { state == .connecting }

    /// La connexion a été modifiée dans l'éditeur : la session en tient compte à sa prochaine ouverture.
    func update(profile: MobileSSHProfile) {
        self.profile = profile
        applyAppearance()
    }

    func applyAppearance() {
        guard let owner else { return }
        terminal.apply(theme: owner.theme(for: profile), fontSize: owner.fontSize)
    }

    // MARK: Ouverture

    /// Ouvre la session si elle ne l'est pas déjà. C'est le geste de l'utilisateur qui la demande.
    func startIfNeeded() {
        switch state {
        case .idle, .ended, .hostKeyChanged, .missingDeviceKey:
            // Un refus (clé d'hôte changée, clé de l'appareil absente) est réexaminé à chaque ouverture
            // de l'écran : sa cause a pu être levée entre-temps dans les réglages.
            connect(password: nil)
        case .connecting, .needsPassword, .needsHostTrust, .connected:
            break
        }
    }

    func reconnect() {
        connect(password: nil)
    }

    /// Suite d'une demande de mot de passe. `keep` : le ranger dans le Trousseau s'il est accepté.
    func submit(password: String, keep: Bool) {
        guard !password.isEmpty else { return }
        passwordToKeep = keep ? password : nil
        connect(password: password)
    }

    /// L'utilisateur accepte la clé présentée par le serveur : elle est enregistrée, puis la connexion reprend.
    func trustHostAndConnect() {
        guard case .needsHostTrust(let keyLine) = state, let owner else { return }
        owner.trust(host: profile.host, port: profile.port, keyLine: keyLine)
        let password = pendingPassword
        pendingPassword = nil
        connect(password: password)
    }

    func cancelPrompt() {
        pendingPassword = nil
        passwordToKeep = nil
        state = .ended(L("Connexion abandonnée."))
    }

    private func connect(password: String?) {
        guard let owner else { return }
        let credential: SSHCredential
        switch profile.auth {
        case .deviceKey:
            guard let key = DeviceKeyStore.privateKeyData() else {
                state = .missingDeviceKey
                return
            }
            credential = .deviceKey(key)
        case .password:
            guard let secret = password ?? KeychainStore.password(account: profile.keychainAccount) else {
                state = .needsPassword(message: nil)
                return
            }
            credential = .password(secret)
        }

        let profile = self.profile
        let expectedKeyLine = owner.knownHosts.known(host: profile.host, port: profile.port)?.keyLine
        attempt += 1
        let current = attempt
        let link = SSHLink()
        state = .connecting
        applyAppearance()
        AppLog.shared.info("SSH", "Connexion à \(profile.summary).")

        Task {
            do {
                let outcome = try await link.connect(
                    host: profile.host,
                    port: profile.port,
                    user: profile.user,
                    credential: credential,
                    expectedKeyLine: expectedKeyLine
                )
                guard current == attempt else {
                    await link.close()
                    return
                }
                switch outcome {
                case .connected:
                    didConnect(link, attempt: current)
                case .unknownHost(let keyLine):
                    pendingPassword = password
                    state = .needsHostTrust(keyLine: keyLine)
                case .changedHost(let presentedKeyLine):
                    passwordToKeep = nil
                    state = .hostKeyChanged(knownKeyLine: expectedKeyLine ?? "", presentedKeyLine: presentedKeyLine)
                    AppLog.shared.error("SSH", "Clé d'hôte changée pour \(profile.host):\(profile.port) : connexion refusée.")
                }
            } catch {
                await link.close()
                guard current == attempt else { return }
                passwordToKeep = nil
                if profile.auth == .password, SSHLink.isAuthenticationFailure(error) {
                    state = .needsPassword(message: L("Le serveur a refusé ce mot de passe."))
                } else {
                    state = .ended(SSHLink.describe(error))
                }
                AppLog.shared.warning("SSH", "Connexion à \(profile.summary) en échec : \(SSHLink.describe(error))")
            }
        }
    }

    private func didConnect(_ link: SSHLink, attempt current: Int) {
        self.link = link
        if let secret = passwordToKeep {
            KeychainStore.setPassword(secret, account: profile.keychainAccount)
            passwordToKeep = nil
        }
        state = .connected
        files.attach(link)
        terminal.attach(
            onInput: { bytes in link.send(bytes) },
            onResize: { columns, rows in link.resize(columns: columns, rows: rows) }
        )
        let terminal = self.terminal
        Task {
            var failure: String?
            do {
                try await link.runShell(columns: terminal.columns, rows: terminal.rows) { bytes in
                    terminal.feed(bytes)
                }
            } catch {
                failure = SSHLink.describe(error)
            }
            await link.close()
            guard current == attempt else { return }
            finish(message: failure ?? L("Session terminée."))
        }
    }

    // MARK: Fermeture

    /// Ferme la session à la demande de l'utilisateur.
    func disconnect() {
        attempt += 1
        let open = link
        Task {
            await open?.close()
        }
        finish(message: L("Session fermée."))
    }

    private func finish(message: String) {
        link = nil
        terminal.detach()
        files.detach()
        pane = .terminal
        if state == .connected {
            terminal.note(message)
        }
        state = .ended(message)
        AppLog.shared.info("SSH", "Session \(profile.summary) : \(message)")
    }
}
