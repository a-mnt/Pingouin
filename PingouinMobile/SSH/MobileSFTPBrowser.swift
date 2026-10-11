import Foundation
import Observation
import PingouinCore

/// Transfert de fichier d'une session, en cours ou terminé.
struct MobileTransfer: Identifiable {
    enum Direction {
        case upload
        case download
    }

    enum State: Equatable {
        case running
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let name: String
    let direction: Direction
    /// Taille à transférer, quand elle est connue.
    let totalBytes: UInt64?
    var doneBytes: UInt64 = 0
    var state: State = .running
    /// Fichier téléchargé, prêt à être remis à la feuille de partage.
    var localURL: URL?

    var isFinished: Bool { state != .running }

    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(Double(doneBytes) / Double(totalBytes), 1)
    }
}

/// Envoi en attente d'un accord, parce qu'il remplacerait des fichiers du dossier distant.
struct MobilePendingUpload: Identifiable {
    let id = UUID()
    let urls: [URL]
    let conflicts: [String]
}

/// Navigateur de fichiers d'une session SSH, par le canal SFTP de la connexion ouverte.
@MainActor
@Observable
final class MobileSFTPBrowser {
    enum Phase: Equatable {
        /// La session est fermée.
        case notConnected
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .notConnected
    /// Dossier affiché. Vide tant qu'il n'a pas été demandé au serveur.
    private(set) var path = ""
    private(set) var entries: [SFTPEntry] = []
    var transfers: [MobileTransfer] = []
    /// Dernier problème rencontré, à montrer sous la liste.
    var notice: String?
    /// Vrai pendant une action sur le dossier (création, renommage, suppression).
    private(set) var isBusy = false
    var pendingUpload: MobilePendingUpload?

    private(set) var link: SSHLink?
    private var loadTask: Task<Void, Never>?
    private var loadNumber = 0
    var transferTasks: [UUID: Task<Void, Never>] = [:]

    var canAct: Bool { phase == .ready && !isBusy }

    var runningTransferCount: Int { transfers.filter { !$0.isFinished }.count }

    // MARK: Connexion

    /// Rattache le navigateur à la connexion qui vient de s'ouvrir.
    func attach(_ link: SSHLink) {
        detach()
        self.link = link
        phase = .loading
    }

    /// La session est terminée : plus rien ne peut être lu ni transféré.
    func detach() {
        loadTask?.cancel()
        loadTask = nil
        loadNumber += 1
        for task in transferTasks.values {
            task.cancel()
        }
        transferTasks = [:]
        link = nil
        entries = []
        isBusy = false
        pendingUpload = nil
        phase = .notConnected
    }

    /// Appelé quand le navigateur devient visible : lit le dossier s'il ne l'a pas encore été.
    func activate() {
        guard link != nil, loadTask == nil, phase == .loading else { return }
        load(path.isEmpty ? nil : path)
    }

    // MARK: Navigation

    func refresh() {
        guard link != nil else { return }
        load(path.isEmpty ? nil : path)
    }

    func goUp() {
        guard canAct, path != "/" else { return }
        load(SFTPPath.parent(of: path))
    }

    /// Ouvre un dossier. Un lien peut mener à un dossier : on essaie, et le serveur répond.
    func open(_ entry: SFTPEntry) {
        guard canAct, entry.kind == .directory || entry.kind == .link else { return }
        load(SFTPPath.join(path, entry.name))
    }

    /// Lit un dossier. `nil` : le dossier d'arrivée de la session, demandé au serveur.
    func load(_ target: String?) {
        guard let link else { return }
        loadTask?.cancel()
        loadNumber += 1
        let number = loadNumber
        notice = nil
        if entries.isEmpty {
            phase = .loading
        }
        loadTask = Task {
            do {
                let folder: String
                if let target {
                    folder = target
                } else {
                    folder = try await link.homeDirectory()
                }
                let list = try await link.list(folder)
                guard number == loadNumber else { return }
                path = folder
                entries = list
                phase = .ready
            } catch {
                guard number == loadNumber else { return }
                let message = L("Le dossier n'a pas pu être lu : \(SSHLink.describe(error))")
                AppLog.shared.warning("SFTP", message)
                // On reste sur le dossier déjà affiché s'il y en a un.
                if path.isEmpty {
                    phase = .failed(message)
                } else {
                    notice = message
                    phase = .ready
                }
            }
            if number == loadNumber {
                loadTask = nil
            }
        }
    }

    // MARK: Actions sur le dossier

    /// Problème d'un nouveau nom, ou `nil` s'il convient.
    func problem(inNewName name: String) -> String? {
        guard SFTPMode.isValidName(name) else {
            return L("Ce nom ne convient pas : il ne doit pas être vide ni contenir « / ».")
        }
        guard !entries.contains(where: { $0.name == name }) else {
            return L("Un élément porte déjà le nom « \(name) » dans ce dossier.")
        }
        return nil
    }

    func makeFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        if let problem = problem(inNewName: name) {
            notice = problem
            return
        }
        let target = SFTPPath.join(path, name)
        perform(failure: L("Le dossier « \(name) » n'a pas pu être créé")) { link in
            try await link.makeDirectory(target)
        }
    }

    func rename(_ entry: SFTPEntry, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard name != entry.name else { return }
        if let problem = problem(inNewName: name) {
            notice = problem
            return
        }
        let source = SFTPPath.join(path, entry.name)
        let destination = SFTPPath.join(path, name)
        perform(failure: L("« \(entry.name) » n'a pas pu être renommé")) { link in
            try await link.rename(source, to: destination)
        }
    }

    /// Supprime un fichier, un lien ou un dossier vide. Un dossier non vide est refusé par le serveur.
    func delete(_ entry: SFTPEntry) {
        let target = SFTPPath.join(path, entry.name)
        let isDirectory = entry.kind == .directory
        perform(failure: L("« \(entry.name) » n'a pas pu être supprimé")) { link in
            try await link.remove(target, isDirectory: isDirectory)
        }
    }

    private func perform(failure: String, _ action: @escaping @Sendable (SSHLink) async throws -> Void) {
        guard let link, canAct else { return }
        notice = nil
        isBusy = true
        Task {
            var problem: String?
            do {
                try await action(link)
            } catch {
                problem = "\(failure) : \(SSHLink.describe(error))"
            }
            // La session a pu se terminer ou changer pendant l'action.
            guard self.link === link else { return }
            isBusy = false
            load(path)
            if let problem {
                notice = problem
                AppLog.shared.warning("SFTP", problem)
            }
        }
    }
}
