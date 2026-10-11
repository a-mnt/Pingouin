import Foundation
import Observation
import PingouinCore

/// Problème rencontré avec un fichier de données, à montrer à l'utilisateur.
struct StorageIssue: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let message: String
    /// Fichier mis de côté, quand il y en a un.
    let setAsideURL: URL?
}

/// Registre des problèmes de stockage de la session. Rien n'est perdu ni écrasé en silence :
/// tout fichier illisible y est signalé.
@MainActor
@Observable
final class StorageIssues {
    static let shared = StorageIssues()

    private(set) var issues: [StorageIssue] = []
    /// Fichiers illisibles qui n'ont pas pu être mis de côté : on ne réécrit pas par-dessus.
    private(set) var blockedFiles: Set<String> = []

    func report(_ issue: StorageIssue) {
        // Un seul message par fichier et par texte : un enregistrement périodique ne doit pas le répéter.
        guard !issues.contains(where: { $0.fileName == issue.fileName && $0.message == issue.message }) else { return }
        issues.append(issue)
        AppLog.shared.error("Stockage", issue.message)
    }

    func block(_ fileName: String) {
        blockedFiles.insert(fileName)
    }

    func dismiss(_ id: UUID) {
        issues.removeAll { $0.id == id }
    }
}

/// Stockage d'une valeur dans un fichier JSON du dossier « Application Support » de l'application.
///
/// Choix volontairement simple pour les petites données de l'application (profils, surveillances,
/// tâches, schéma) : un fichier lisible par valeur, écrit de façon atomique. Aucun secret n'y est écrit.
///
/// Chaque fichier porte un numéro de version (voir `VersionedFile`). À la lecture, un fichier plus
/// ancien est migré ; un fichier illisible est mis de côté sous un autre nom et signalé.
@MainActor
struct JSONStore<Value: Codable> {
    let fileName: String
    /// Version du format écrit par cette version de l'application.
    var version = 1
    /// `migrations[n]` transforme le contenu de la version n en version n + 1.
    /// La version 0 est le fichier d'avant l'enveloppe : son contenu est identique à la version 1.
    var migrations: [Int: VersionedFile.Migration] = [:]

    private var fileURL: URL? {
        AppDataFolder.url?.appendingPathComponent(fileName + ".json")
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Valeur enregistrée, ou `nil` s'il n'y a pas de fichier ou s'il est illisible.
    /// Dans le second cas, le fichier est mis de côté et le problème est signalé.
    func load() -> Value? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let opened = try VersionedFile.open(data)
            let payload = try VersionedFile.migrate(opened.payload, from: opened.version, to: version, using: migrations)
            let value = try Self.decoder.decode(Value.self, from: payload)
            if opened.version != version {
                AppLog.shared.info("Stockage", "« \(fileName).json » lu au format \(opened.version), converti au format \(version).")
            }
            return value
        } catch let failure as VersionedFile.Failure {
            switch failure {
            case .newerVersion(let found, let supported):
                setAside(fileURL, reason: L("a été écrit par une version plus récente de Pingouin (format \(found), cette version lit jusqu'au format \(supported))"))
            case .migrationFailed(let from):
                setAside(fileURL, reason: L("n'a pas pu être converti depuis l'ancien format \(from)"))
            case .notJSON:
                setAside(fileURL, reason: L("est endommagé"))
            }
            return nil
        } catch {
            setAside(fileURL, reason: L("n'a pas pu être lu (\(error.localizedDescription))"))
            return nil
        }
    }

    /// Enregistre la valeur. Renvoie faux si l'écriture a échoué ou si elle est suspendue.
    @discardableResult
    func save(_ value: Value) -> Bool {
        guard let fileURL else { return false }
        // Un fichier illisible resté en place n'est jamais écrasé.
        guard !StorageIssues.shared.blockedFiles.contains(fileName) else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(VersionedEnvelope(version: version, data: value)).write(to: fileURL, options: .atomic)
            return true
        } catch {
            StorageIssues.shared.report(StorageIssue(
                fileName: fileName,
                message: L("« \(fileName).json » n'a pas pu être enregistré : \(error.localizedDescription). Les changements récents ne sont pas conservés."),
                setAsideURL: nil
            ))
            return false
        }
    }

    /// Renomme un fichier illisible pour le conserver, et le signale. S'il ne peut pas être renommé,
    /// les enregistrements de ce fichier sont suspendus pour ne pas l'écraser.
    private func setAside(_ url: URL, reason: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(fileName).illisible-\(formatter.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            StorageIssues.shared.report(StorageIssue(
                fileName: fileName,
                message: L("Le fichier « \(fileName).json » \(reason). Il a été mis de côté sous le nom « \(destination.lastPathComponent) » ; Pingouin repart d'un fichier vide."),
                setAsideURL: destination
            ))
        } catch {
            StorageIssues.shared.block(fileName)
            StorageIssues.shared.report(StorageIssue(
                fileName: fileName,
                message: L("Le fichier « \(fileName).json » \(reason) et n'a pas pu être mis de côté. Pingouin ne l'écrase pas : rien ne sera enregistré dans ce fichier tant qu'il est en place."),
                setAsideURL: url
            ))
        }
    }
}
