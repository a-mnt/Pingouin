import Foundation

/// Serveur SSH dont la clé a été acceptée par l'utilisateur.
public struct KnownHost: Codable, Hashable, Identifiable, Sendable {
    public var host: String
    public var port: Int
    /// Clé publique du serveur, au format d'OpenSSH (« type base64 »).
    public var keyLine: String
    public var addedAt: Date

    public var id: String { KnownHostsBook.name(host: host, port: port) }

    public init(host: String, port: Int, keyLine: String, addedAt: Date) {
        self.host = host
        self.port = port
        self.keyLine = keyLine
        self.addedAt = addedAt
    }
}

/// Ce que vaut la clé présentée par un serveur, au regard des hôtes connus.
public enum HostKeyVerdict: Equatable, Sendable {
    /// La clé est celle qui a été acceptée pour cet hôte.
    case trusted
    /// Première connexion : l'hôte n'est pas connu.
    case unknown
    /// L'hôte est connu sous une autre clé : la connexion doit être refusée.
    case changed(known: KnownHost)
}

/// Liste des hôtes connus. Un hôte est désigné par son nom et son port, comparés sans tenir compte
/// de la casse : le même serveur sur deux ports peut présenter deux clés.
public struct KnownHostsBook: Codable, Equatable, Sendable {
    public private(set) var hosts: [KnownHost]

    public init(hosts: [KnownHost] = []) {
        self.hosts = hosts
    }

    public static func name(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    public func known(host: String, port: Int) -> KnownHost? {
        let name = Self.name(host: host, port: port)
        return hosts.first { $0.id == name }
    }

    public func verdict(host: String, port: Int, presentedKeyLine: String) -> HostKeyVerdict {
        guard let known = known(host: host, port: port) else { return .unknown }
        return OpenSSHPublicKey.isSameKey(known.keyLine, presentedKeyLine) ? .trusted : .changed(known: known)
    }

    /// Enregistre la clé d'un hôte. Une clé déjà connue pour cet hôte est remplacée : à n'appeler
    /// qu'après un accord explicite de l'utilisateur.
    public mutating func trust(host: String, port: Int, keyLine: String, now: Date = Date()) {
        forget(host: host, port: port)
        hosts.append(KnownHost(host: host, port: port, keyLine: keyLine, addedAt: now))
        hosts.sort { $0.id < $1.id }
    }

    public mutating func forget(host: String, port: Int) {
        let name = Self.name(host: host, port: port)
        hosts.removeAll { $0.id == name }
    }
}

/// Destination saisie d'un trait : « utilisateur@hôte » ou « utilisateur@hôte:port ».
public struct SSHDestination: Equatable, Sendable {
    public let user: String
    public let host: String
    public let port: Int

    /// `nil` si l'utilisateur ou l'hôte manque, ou si le port n'en est pas un.
    public static func parse(_ text: String) -> SSHDestination? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        let user = String(trimmed[..<at])
        let rest = String(trimmed[trimmed.index(after: at)...])
        guard isValidUser(user), let target = HostPort.split(rest, defaultPort: 22) else { return nil }
        return SSHDestination(user: user, host: target.host, port: Int(target.port))
    }

    /// Un nom de compte : non vide, sans espace ni caractère qui le ferait confondre avec l'hôte.
    public static func isValidUser(_ user: String) -> Bool {
        !user.isEmpty && user.count <= 64
            && !user.contains { $0.isWhitespace || $0 == "@" || $0 == ":" || $0 == "/" }
    }
}
