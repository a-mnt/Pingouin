import Foundation
import Observation
import PingouinCore

@MainActor
@Observable
final class SSHViewModel {
    static let defaultThemeKey = "ssh.defaultTheme"
    static let fontSizeKey = "ssh.fontSize"

    let store = JSONStore<[SSHProfile]>(fileName: "connexions-ssh")
    /// Nombre maximal d'onglets ouverts en même temps.
    static let sessionLimit = 12

    /// Les propriétés ci-dessous sont modifiables depuis l'extension des thèmes (autre fichier) ;
    /// les vues ne les modifient pas directement.
    var profiles: [SSHProfile] = []
    var selectedProfileID: UUID?
    /// Sessions ouvertes, dans l'ordre des onglets.
    private(set) var sessions: [SSHSession] = []
    var selectedSessionID: UUID?
    private(set) var message: String?

    /// Session de l'onglet affiché.
    var session: SSHSession? {
        get { sessions.first { $0.id == selectedSessionID } }
        set {
            guard let newValue, let index = sessions.firstIndex(where: { $0.id == newValue.id }) else { return }
            sessions[index] = newValue
        }
    }

    var draft = SSHProfile()
    var draftPortText = "22"
    var isEditing = false
    private(set) var draftIsNew = true
    /// Mot de passe saisi dans la feuille. Vide : le mot de passe déjà enregistré, s'il existe, est conservé.
    var draftPassword = ""
    private(set) var draftHasSavedPassword = false
    var draftRemovesPassword = false
    /// Session dont la feuille enregistre la connexion, s'il y en a une.
    private var draftSavesSessionID: UUID?
    var draftError: String?

    var defaultThemeID: String
    var fontSize: Double

    init() {
        let defaults = UserDefaults.standard
        defaultThemeID = TerminalTheme.named(defaults.string(forKey: Self.defaultThemeKey)).id
        let savedSize = defaults.double(forKey: Self.fontSizeKey)
        fontSize = (9...24).contains(savedSize) ? savedSize : 13
        profiles = store.load() ?? []
        selectedProfileID = profiles.first?.id
    }

    var selectedProfile: SSHProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// Thème affiché : celui de la session en cours, sinon celui du profil choisi, sinon le thème par défaut.
    var currentTheme: TerminalTheme {
        TerminalTheme.named(session?.themeID ?? selectedProfile?.themeID ?? defaultThemeID)
    }

    var terminalIsAvailable: Bool { TerminalController.isAvailable }

    // MARK: Connexions enregistrées

    /// Vrai si la session en cours vient d'une connexion qui n'est pas enregistrée.
    var canSaveCurrentSession: Bool {
        session != nil && session?.profileID == nil && session?.unsavedProfile != nil
    }

    func beginAdding(host: String = "") {
        draft = SSHProfile(host: host)
        draftPortText = "22"
        draftIsNew = true
        resetDraftPassword(hasSaved: false)
        draftSavesSessionID = nil
        draftError = nil
        isEditing = true
    }

    /// Ouvre la feuille préremplie avec la connexion de la session en cours, pour l'enregistrer.
    func beginSavingCurrentSession() {
        guard canSaveCurrentSession, let profile = session?.unsavedProfile else {
            beginAdding()
            return
        }
        draft = profile
        draft.themeID = session?.themeID
        draftPortText = String(profile.port)
        draftIsNew = true
        resetDraftPassword(hasSaved: false)
        draftSavesSessionID = session?.id
        draftError = nil
        isEditing = true
    }

    /// Place le mot de passe enregistré dans le champ de la feuille, pour pouvoir le relire.
    func loadSavedPasswordIntoDraft() {
        guard draftHasSavedPassword, draftPassword.isEmpty,
              let password = KeychainStore.password(account: draft.keychainAccount) else { return }
        draftPassword = password
    }

    private func resetDraftPassword(hasSaved: Bool) {
        draftPassword = ""
        draftHasSavedPassword = hasSaved
        draftRemovesPassword = false
    }

    func beginEditing(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        draft = profile
        draftPortText = String(profile.port)
        draftIsNew = false
        resetDraftPassword(hasSaved: KeychainStore.hasPassword(account: profile.keychainAccount))
        draftSavesSessionID = nil
        draftError = nil
        isEditing = true
    }

    /// Valide la saisie et enregistre la connexion. Renvoie faux, avec un message, si elle est invalide.
    @discardableResult
    func commitDraft() -> Bool {
        var profile = draft
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.host = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.user = profile.user.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.identityFile = profile.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SSHInput.isSafeHost(profile.host) else {
            draftError = L("Saisir un nom d'hôte ou une adresse, sans espace.")
            return false
        }
        guard SSHInput.isSafeUser(profile.user) else {
            draftError = L("Le nom d'utilisateur ne doit contenir ni espace ni « @ ».")
            return false
        }
        guard let port = NumberInput.integer(draftPortText), (1...65_535).contains(port) else {
            draftError = L("Le port doit être compris entre 1 et 65535.")
            return false
        }
        profile.port = port
        if !profile.identityFile.isEmpty {
            let path = (profile.identityFile as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                draftError = L("Le fichier de clé est introuvable à cet emplacement.")
                return false
            }
        }

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        store.save(profiles)
        selectedProfileID = profile.id

        // La session en cours devient celle de la connexion enregistrée, si l'hôte n'a pas été changé.
        if let index = sessions.firstIndex(where: { $0.id == draftSavesSessionID }),
           let unsaved = sessions[index].unsavedProfile,
           unsaved.host == profile.host, unsaved.port == profile.port {
            sessions[index].profileID = profile.id
            sessions[index].title = profile.displayName
            sessions[index].unsavedProfile = nil
        }
        draftSavesSessionID = nil

        // Le mot de passe va dans le Trousseau, jamais dans le fichier des connexions.
        // Un retour à la ligne collé avec le mot de passe n'en fait pas partie.
        let password = draftPassword.trimmingCharacters(in: .newlines)
        if !password.isEmpty {
            guard KeychainStore.setPassword(password, account: profile.keychainAccount) else {
                draftError = L("La connexion est enregistrée, mais le Trousseau a refusé le mot de passe.")
                draftIsNew = false
                return false
            }
        } else if draftRemovesPassword {
            KeychainStore.deletePassword(account: profile.keychainAccount)
        }
        draftPassword = ""
        isEditing = false
        return true
    }

    func duplicate(_ id: UUID) {
        guard var copy = profiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = copy.displayName + L(" (copie)")
        profiles.append(copy)
        store.save(profiles)
        selectedProfileID = copy.id
    }

    func remove(_ id: UUID) {
        if let profile = profiles.first(where: { $0.id == id }) {
            KeychainStore.deletePassword(account: profile.keychainAccount)
        }
        profiles.removeAll { $0.id == id }
        store.save(profiles)
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
    }

    // MARK: Sessions

    /// Ouvre une connexion enregistrée. Il n'y a qu'un onglet par machine, pour le terminal comme
    /// pour les fichiers : si la session est ouverte, son onglet est affiché ; si elle est terminée,
    /// elle est relancée dans le même onglet. `pane` : ce que l'onglet doit montrer, s'il faut en changer.
    func connect(_ id: UUID, pane: SSHPane? = nil) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        selectedProfileID = id
        if let index = sessions.firstIndex(where: { $0.profileID == id }) {
            if sessions[index].isActive {
                selectedSessionID = sessions[index].id
                if let pane {
                    sessions[index].pane = pane
                }
            } else {
                start(profile, saved: true, pane: pane, replacing: sessions[index].id)
            }
            return
        }
        start(profile, saved: true, pane: pane)
    }

    /// Choisit ce que montre l'onglet affiché.
    func showPane(_ pane: SSHPane) {
        session?.pane = pane
    }

    /// Relance la session terminée de l'onglet affiché, dans le même onglet.
    func reconnectCurrentSession() {
        guard let session, !session.isActive else { return }
        if let id = session.profileID {
            connect(id)
        } else if let profile = session.unsavedProfile {
            start(profile, saved: false, replacing: session.id)
        }
    }

    /// Ouvre aussitôt une session vers un hôte venu d'un autre outil, sans l'enregistrer.
    /// Si une connexion enregistrée vise déjà cet hôte, c'est elle qui est utilisée.
    func quickConnect(host: String, port: Int = 22) {
        if let known = profiles.first(where: { $0.host == host && $0.port == port }) {
            connect(known.id)
            return
        }
        guard SSHInput.isSafeHost(host) else {
            message = L("Cet hôte ne peut pas être utilisé pour une connexion SSH.")
            return
        }
        guard (1...65_535).contains(port) else {
            message = L("Ce port ne peut pas être utilisé pour une connexion SSH.")
            return
        }
        // Même règle pour un hôte non enregistré : un seul onglet, repris ou relancé.
        if let existing = sessions.first(where: { $0.unsavedProfile?.host == host && $0.unsavedProfile?.port == port }) {
            if existing.isActive {
                selectedSessionID = existing.id
            } else {
                start(SSHProfile(host: host, port: port), saved: false, replacing: existing.id)
            }
            return
        }
        start(SSHProfile(host: host, port: port), saved: false)
    }

    /// Met fin à la session de l'onglet affiché. L'onglet reste ouvert, pour relire l'écran.
    func disconnect() {
        session?.terminal.stop()
        if session?.isActive == true {
            session?.endMessage = L("Session fermée.")
            session?.files.detach()
        }
    }

    /// Ferme un onglet, en mettant fin à sa session si elle est encore ouverte.
    func closeSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].terminal.stop()
        sessions[index].files.detach()
        sessions.remove(at: index)
        if selectedSessionID == id {
            // L'onglet voisin prend la place : celui de droite, sinon celui de gauche.
            selectedSessionID = sessions.indices.contains(index) ? sessions[index].id : sessions.last?.id
        }
    }

    /// `replacing` : onglet dont la session terminée laisse sa place à la nouvelle.
    private func start(_ profile: SSHProfile, saved: Bool, pane: SSHPane? = nil, replacing: UUID? = nil) {
        guard SSHInput.isSafeHost(profile.host), SSHInput.isSafeUser(profile.user) else {
            message = L("Cette connexion contient un hôte ou un utilisateur non valide.")
            return
        }
        guard replacing != nil || sessions.count < Self.sessionLimit else {
            message = L("Trop d'onglets ouverts (\(Self.sessionLimit) au plus). Fermer un onglet pour ouvrir cette session.")
            return
        }
        message = nil
        let theme = TerminalTheme.named(profile.themeID ?? defaultThemeID)

        // L'option « -- » marque la fin des options : la destination ne peut pas être prise pour l'une d'elles.
        var arguments = ["-o", "StrictHostKeyChecking=ask", "-o", "ServerAliveInterval=30"]
        if !profile.identityFile.isEmpty {
            arguments += ["-i", (profile.identityFile as NSString).expandingTildeInPath]
        }
        // La connexion est partagée : le navigateur de fichiers de l'onglet l'emprunte,
        // sans s'authentifier une seconde fois.
        let connection = SFTPConnection(
            destination: profile.destination,
            port: profile.port,
            controlPath: SFTPConnection.newControlPath()
        )
        arguments += connection.sharingArguments
        arguments += ["-p", String(profile.port), "--", profile.destination]

        // L'onglet relancé garde son navigateur de fichiers, donc son dossier, et ce qu'il montrait.
        let previous = sessions.first { $0.id == replacing }
        let files = previous?.files ?? SFTPBrowser()
        let terminal = TerminalController()
        let session = SSHSession(
            terminal: terminal,
            files: files,
            pane: pane ?? previous?.pane ?? .terminal,
            unsavedProfile: saved ? nil : profile,
            profileID: saved ? profile.id : nil,
            title: profile.displayName,
            target: profile.summary,
            startedAt: Date(),
            themeID: theme.id,
            endMessage: nil
        )
        let sessionID = session.id
        let started = terminal.start(
            executable: "/usr/bin/ssh",
            arguments: arguments,
            theme: theme,
            fontSize: fontSize,
            password: saved && AppSettings.sshAutoPassword ? KeychainStore.password(account: profile.keychainAccount) : nil
        ) { [weak self] exitCode in
            self?.sessionEnded(exitCode: exitCode, id: sessionID)
        }
        guard started else {
            message = L("Le terminal intégré n'est pas disponible : la bibliothèque SwiftTerm n'a pas été chargée par Xcode.")
            AppLog.shared.error("SSH", "Terminal intégré indisponible : SwiftTerm n'est pas chargé.")
            return
        }
        AppLog.shared.info("SSH", "Session ouverte vers \(profile.summary)\(saved ? "" : " (connexion non enregistrée)").")
        if let index = sessions.firstIndex(where: { $0.id == replacing }) {
            // L'ancien terminal est arrêté par précaution ; la nouvelle session reprend sa place.
            sessions[index].terminal.stop()
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        files.attach(connection)
        selectedSessionID = sessionID
    }

    private func sessionEnded(exitCode: Int32?, id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].isActive else { return }
        sessions[index].files.detach()
        AppLog.shared.info("SSH", "Session vers \(sessions[index].target) terminée (code \(exitCode.map { String($0) } ?? "inconnu")).")
        if let exitCode, exitCode != 0 {
            // Selon sa version, SwiftTerm transmet le code de sortie ou l'état brut de waitpid (code × 256).
            let code = exitCode > 255 ? (exitCode >> 8) & 0xFF : exitCode
            sessions[index].endMessage = L("Session terminée (code \(code)).")
        } else {
            sessions[index].endMessage = L("Session terminée.")
        }
    }
}
