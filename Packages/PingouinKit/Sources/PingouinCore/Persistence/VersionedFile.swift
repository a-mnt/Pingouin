import Foundation

/// Format des fichiers de données de l'application : le contenu est rangé dans une enveloppe
/// qui porte un numéro de version, pour pouvoir le faire évoluer sans perdre les fichiers existants.
///
///     { "format": "pingouin", "version": 1, "data": … }
///
/// Un fichier sans enveloppe est un fichier d'avant ce format : il est traité comme la version 0.
public enum VersionedFile {
    public static let formatName = "pingouin"

    public enum Failure: Error, Equatable, Sendable {
        /// Le fichier n'est pas du JSON lisible.
        case notJSON
        /// Le fichier vient d'une version plus récente de l'application.
        case newerVersion(found: Int, supported: Int)
        /// Une étape de migration a échoué.
        case migrationFailed(from: Int)
    }

    /// Transformation du contenu d'une version vers la suivante.
    public typealias Migration = @Sendable (Data) throws -> Data

    /// Version du fichier et contenu brut, hors enveloppe. Un fichier sans enveloppe donne la version 0
    /// et son contenu entier.
    public static func open(_ data: Data) throws -> (version: Int, payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw Failure.notJSON
        }
        guard let dictionary = object as? [String: Any],
              dictionary["format"] as? String == formatName,
              let version = dictionary["version"] as? Int,
              let content = dictionary["data"] else {
            return (0, data)
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: content, options: [.fragmentsAllowed]) else {
            throw Failure.notJSON
        }
        return (version, payload)
    }

    /// Amène un contenu de la version `version` à la version `target`, une étape à la fois.
    /// `migrations[n]` transforme la version n en version n + 1 ; une étape absente ne change rien.
    public static func migrate(
        _ payload: Data,
        from version: Int,
        to target: Int,
        using migrations: [Int: Migration]
    ) throws -> Data {
        guard version <= target else {
            throw Failure.newerVersion(found: version, supported: target)
        }
        var current = payload
        for step in version..<target {
            guard let migration = migrations[step] else { continue }
            do {
                current = try migration(current)
            } catch {
                throw Failure.migrationFailed(from: step)
            }
        }
        return current
    }
}

/// Enveloppe écrite sur le disque.
public struct VersionedEnvelope<Value: Codable>: Codable {
    public var format: String
    public var version: Int
    public var data: Value

    public init(version: Int, data: Value) {
        self.format = VersionedFile.formatName
        self.version = version
        self.data = data
    }
}
