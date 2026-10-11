import Foundation

/// Transfert de fichier, en attente, en cours ou terminé.
struct SFTPTransfer: Identifiable {
    enum Direction {
        case upload
        case download
    }

    enum State: Equatable {
        case queued
        case running
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let name: String
    let direction: Direction
    /// Taille à transférer, quand elle est connue (fichier seul).
    let totalBytes: UInt64?
    /// Octets déjà reçus. Connu pour un téléchargement de fichier uniquement.
    var doneBytes: UInt64?
    var state: State = .queued

    var isFinished: Bool { state != .queued && state != .running }

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0, let doneBytes else { return nil }
        return min(Double(doneBytes) / Double(totalBytes), 1)
    }
}

/// Envoi en attente d'un accord, parce qu'il remplacerait des éléments du dossier distant.
struct SFTPPendingUpload: Identifiable {
    let id = UUID()
    let urls: [URL]
    let conflicts: [String]
}
