import Foundation
import PingouinCore

/// Connexion SSH enregistrée. Aucun mot de passe ni contenu de clé n'y figure : le mot de passe,
/// s'il est enregistré, est dans le Trousseau ; pour la clé, seul le chemin du fichier est gardé.
struct SSHProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var host = ""
    var port = 22
    var user = ""
    /// Chemin d'une clé privée. Vide : `ssh` utilise ses clés habituelles et l'agent.
    var identityFile = ""
    /// Thème propre à cette connexion. `nil` : thème par défaut.
    var themeID: String?

    var displayName: String { name.isEmpty ? host : name }

    var destination: String { user.isEmpty ? host : "\(user)@\(host)" }

    var summary: String { port == 22 ? destination : "\(destination):\(port)" }

    /// Compte sous lequel le mot de passe de cette connexion est rangé dans le Trousseau.
    var keychainAccount: String { "ssh:\(id.uuidString)" }
}

/// Ce que montre l'onglet d'une machine : son terminal ou ses fichiers.
enum SSHPane: Hashable {
    case terminal
    case files
}

/// Session d'une machine, dans son onglet. Il n'y a qu'un onglet par machine : il porte le terminal
/// et le navigateur de fichiers, que la session soit ouverte ou terminée.
struct SSHSession: Identifiable {
    let id = UUID()
    let terminal: TerminalController
    /// Navigateur de fichiers de l'onglet. Il est conservé quand la session est relancée.
    let files: SFTPBrowser
    var pane: SSHPane
    /// Connexion utilisée, quand la session a été ouverte sans connexion enregistrée.
    var unsavedProfile: SSHProfile?
    var profileID: UUID?
    var title: String
    let target: String
    let startedAt: Date
    var themeID: String
    /// Renseigné quand le processus s'est terminé.
    var endMessage: String?

    var isActive: Bool { endMessage == nil }
}

/// Contrôle des saisies passées à la commande `ssh`.
enum SSHInput {
    /// Un hôte acceptable pour `ssh` : plausible, et ne commençant pas par un tiret
    /// (il serait lu comme une option de la commande).
    static func isSafeHost(_ host: String) -> Bool {
        HostInput.isPlausible(host) && !host.hasPrefix("-")
    }

    static func isSafeUser(_ user: String) -> Bool {
        user.isEmpty || (!user.hasPrefix("-") && !user.contains(where: { $0.isWhitespace || $0 == "@" || $0 == ":" || $0 == "/" }))
    }
}
