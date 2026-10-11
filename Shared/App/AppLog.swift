import Foundation
import Observation
import os

/// Journal commun de l'application.
///
/// Chaque ligne est envoyée au journal unifié de macOS (visible dans Console.app, sous-système
/// `fr.a-mnt.pingouin`) et gardée en mémoire le temps de la session, pour être lue ou exportée
/// depuis Réglages > Journal.
///
/// Règle : jamais de secret ici — ni mot de passe, ni jeton, ni contenu de clé. On y écrit ce qui
/// s'est passé (quel outil, quelle cible, quel résultat), pas ce qui a été saisi.
@MainActor
@Observable
final class AppLog {
    static let shared = AppLog()

    enum Level: String {
        case info = "INFO"
        case warning = "ATTENTION"
        case error = "ERREUR"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String

        var line: String {
            "\(date.formatted(.iso8601))  \(level.rawValue)  [\(category)]  \(message)"
        }
    }

    /// Nombre de lignes gardées en mémoire ; les plus anciennes sont abandonnées.
    private static let limit = 1_000
    private static let subsystem = "fr.a-mnt.pingouin"

    private(set) var entries: [Entry] = []

    func record(_ level: Level, _ category: String, _ message: String) {
        entries.append(Entry(date: Date(), level: level, category: category, message: message))
        if entries.count > Self.limit {
            entries.removeFirst(entries.count - Self.limit)
        }
        let logger = Logger(subsystem: Self.subsystem, category: category)
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    func info(_ category: String, _ message: String) { record(.info, category, message) }
    func warning(_ category: String, _ message: String) { record(.warning, category, message) }
    func error(_ category: String, _ message: String) { record(.error, category, message) }

    /// Journal de la session, une ligne par entrée, de la plus ancienne à la plus récente.
    var exportText: String {
        entries.map(\.line).joined(separator: "\n")
    }

    func clear() {
        entries = []
    }
}
