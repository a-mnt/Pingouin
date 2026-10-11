import Foundation
import Observation
import PingouinCore

/// SSH sur iOS : connexions enregistrées, hôtes connus, clé de l'appareil et sessions ouvertes.
@MainActor
@Observable
final class MobileSSHViewModel {
    private static let themeKey = "ssh.defaultThemeID"
    private static let fontSizeKey = "ssh.mobileFontSize"
    static let fontSizeRange = 9.0...20.0

    private let store = JSONStore<[MobileSSHProfile]>(fileName: "connexions-ssh-mobile")
    private let hostStore = JSONStore<KnownHostsBook>(fileName: "hotes-connus")

    private(set) var profiles: [MobileSSHProfile] = []
    private(set) var knownHosts = KnownHostsBook()
    private(set) var sessions: [UUID: MobileSSHSession] = [:]

    var quickTarget = ""
    var quickError: String?

    var draft = MobileSSHProfile()
    var draftPortText = "22"
    var draftPassword = ""
    var keepsDraftPassword = true
    var isEditing = false
    private(set) var isEditingExisting = false
    var draftError: String?

    private(set) var defaultThemeID: String
    private(set) var fontSize: Double
    private(set) var deviceKeyLine: String?
    private(set) var deviceKeyCreatedAt: Date?
    var deviceKeyMessage: String?

    init() {
        let defaults = UserDefaults.standard
        defaultThemeID = TerminalTheme.named(defaults.string(forKey: Self.themeKey)).id
        let size = defaults.double(forKey: Self.fontSizeKey)
        fontSize = Self.fontSizeRange.contains(size) ? size : 12
        profiles = store.load() ?? []
        knownHosts = hostStore.load() ?? KnownHostsBook()
        refreshDeviceKey()
    }

    // MARK: Sessions

    func session(id: UUID) -> MobileSSHSession? {
        sessions[id]
    }

    func isOpen(_ profile: MobileSSHProfile) -> Bool {
        sessions[profile.id]?.isOpen ?? false
    }

    /// Session d'une connexion enregistrée, créée au besoin. Elle n'est pas ouverte ici.
    @discardableResult
    func session(for profile: MobileSSHProfile) -> MobileSSHSession {
        if let existing = sessions[profile.id] {
            return existing
        }
        let session = MobileSSHSession(profile: profile, owner: self)
        sessions[profile.id] = session
        return session
    }

    /// Prépare une session vers la destination saisie, sans l'enregistrer. Renvoie son identifiant,
    /// ou `nil`, avec un message, si la saisie n'est pas « utilisateur@hôte ».
    func quickSession() -> UUID? {
        guard let destination = SSHDestination.parse(quickTarget) else {
            quickError = L("Saisir la destination sous la forme utilisateur@hôte, par exemple utilisateur@192.168.1.20.")
            return nil
        }
        quickError = nil
        var profile = MobileSSHProfile()
        profile.host = destination.host
        profile.port = destination.port
        profile.user = destination.user
        profile.auth = .password
        return session(for: profile).id
    }

    /// Prépare la connexion rapide vers un hôte choisi dans un autre outil : il reste à saisir le compte.
    func prepareQuick(host: String) {
        quickTarget = "@" + host
        quickError = L("Compléter avec le nom du compte, devant « @ », puis ouvrir.")
    }

    /// Ferme et oublie les sessions terminées des connexions qui ne sont pas enregistrées.
    func discardEndedQuickSessions() {
        for (id, session) in sessions where !profiles.contains(where: { $0.id == id }) {
            if case .ended = session.state {
                sessions[id] = nil
            }
        }
    }

    // MARK: Connexions enregistrées

    func beginAdding() {
        draft = MobileSSHProfile()
        draftPortText = "22"
        draftPassword = ""
        keepsDraftPassword = true
        draftError = nil
        isEditingExisting = false
        isEditing = true
    }

    func beginEditing(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        draft = profile
        draftPortText = String(profile.port)
        draftPassword = ""
        keepsDraftPassword = KeychainStore.hasPassword(account: profile.keychainAccount)
        draftError = nil
        isEditingExisting = true
        isEditing = true
    }

    /// Valide la saisie et enregistre la connexion. Renvoie faux, avec un message, si elle est incomplète.
    @discardableResult
    func commitDraft() -> Bool {
        var profile = draft
        profile.name = profile.name.trimmingCharacters(in: .whitespaces)
        profile.host = profile.host.trimmingCharacters(in: .whitespaces)
        profile.user = profile.user.trimmingCharacters(in: .whitespaces)
        guard HostInput.isPlausible(profile.host), !profile.host.contains(":") || HostAddress(profile.host) != nil else {
            draftError = L("Saisir un nom d'hôte ou une adresse IP, sans espace.")
            return false
        }
        guard let port = NumberInput.integer(draftPortText), (1...65_535).contains(port) else {
            draftError = L("Le port doit être compris entre 1 et 65535.")
            return false
        }
        guard SSHDestination.isValidUser(profile.user) else {
            draftError = L("Saisir le nom du compte sur le serveur, sans espace.")
            return false
        }
        profile.port = port

        if profile.auth == .password {
            if !keepsDraftPassword {
                KeychainStore.deletePassword(account: profile.keychainAccount)
            } else if !draftPassword.isEmpty, !KeychainStore.setPassword(draftPassword, account: profile.keychainAccount) {
                draftError = L("Le Trousseau a refusé d'enregistrer le mot de passe.")
                return false
            }
        } else {
            KeychainStore.deletePassword(account: profile.keychainAccount)
        }
        draftPassword = ""

        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        store.save(profiles)
        sessions[profile.id]?.update(profile: profile)
        isEditing = false
        return true
    }

    func duplicate(_ id: UUID) {
        guard var copy = profiles.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = L("\(copy.displayName) (copie)")
        profiles.append(copy)
        store.save(profiles)
    }

    /// Supprime une connexion, son mot de passe gardé et sa session.
    func remove(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        sessions[id]?.disconnect()
        sessions[id] = nil
        KeychainStore.deletePassword(account: profile.keychainAccount)
        profiles.removeAll { $0.id == id }
        store.save(profiles)
    }

    // MARK: Hôtes connus

    func trust(host: String, port: Int, keyLine: String) {
        knownHosts.trust(host: host, port: port, keyLine: keyLine)
        hostStore.save(knownHosts)
        AppLog.shared.info("SSH", "Clé d'hôte acceptée pour \(host):\(port).")
    }

    func forget(_ host: KnownHost) {
        knownHosts.forget(host: host.host, port: host.port)
        hostStore.save(knownHosts)
        AppLog.shared.info("SSH", "Hôte \(host.id) retiré des hôtes connus.")
    }

    // MARK: Clé de l'appareil

    var deviceKeyUsageCount: Int {
        profiles.filter { $0.auth == .deviceKey }.count
    }

    func refreshDeviceKey() {
        deviceKeyLine = DeviceKeyStore.publicKeyLine()
        deviceKeyCreatedAt = deviceKeyLine == nil ? nil : DeviceKeyStore.createdAt
    }

    /// Crée la clé de l'appareil, ou la remplace : l'ancienne est alors détruite.
    func createDeviceKey() {
        if DeviceKeyStore.create() {
            deviceKeyMessage = nil
            AppLog.shared.info("SSH", "Clé de l'appareil créée.")
        } else {
            deviceKeyMessage = L("Le Trousseau a refusé d'enregistrer la clé.")
            AppLog.shared.error("SSH", "Création de la clé de l'appareil refusée par le Trousseau.")
        }
        refreshDeviceKey()
    }

    // MARK: Apparence du terminal

    func theme(for profile: MobileSSHProfile) -> TerminalTheme {
        TerminalTheme.named(profile.themeID ?? defaultThemeID)
    }

    func setDefaultTheme(_ id: String) {
        defaultThemeID = TerminalTheme.named(id).id
        UserDefaults.standard.set(defaultThemeID, forKey: Self.themeKey)
        applyAppearance()
    }

    func setFontSize(_ size: Double) {
        fontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
        applyAppearance()
    }

    private func applyAppearance() {
        for session in sessions.values {
            session.applyAppearance()
        }
    }
}
