import Foundation
import Observation
import PingouinCore

/// Navigateur de fichiers d'un onglet SSH. Chaque action lance la commande `sftp` du système,
/// qui emprunte la connexion ouverte par le terminal de l'onglet.
@MainActor
@Observable
final class SFTPBrowser {
    enum Phase: Equatable {
        /// La session de l'onglet est fermée.
        case notConnected
        /// La session s'ouvre dans le terminal (mot de passe, clé d'hôte).
        case waiting
        case loading
        case ready
        case failed(String)
    }

    /// Ce qu'il faut exécuter pour un transfert en attente.
    struct Plan {
        let command: String
        /// Fichier provisoire d'un téléchargement, et son emplacement définitif.
        var partialURL: URL?
        var finalURL: URL?
        /// Dossier distant à relire après un envoi.
        var remoteFolder: String?
    }

    private(set) var phase: Phase = .notConnected
    /// Dossier affiché. Vide tant qu'il n'a pas été demandé au serveur.
    private(set) var path = ""
    var pathText = ""
    private(set) var entries: [SFTPEntry] = []
    var selection: Set<String> = []
    var transfers: [SFTPTransfer] = []
    /// Dernier problème rencontré, à montrer sous la liste.
    var notice: String?
    /// Vrai pendant une action sur le dossier (création, renommage, suppression).
    private(set) var isBusy = false
    var pendingUpload: SFTPPendingUpload?

    private(set) var connection: SFTPConnection?
    private var loadTask: Task<Void, Never>?
    private var loadNumber = 0
    /// Transferts : modifiés par l'extension des transferts (autre fichier), pas par les vues.
    var plans: [UUID: Plan] = [:]
    var runningJobs: [UUID: SFTPJob] = [:]

    var canAct: Bool { phase == .ready && !isBusy }

    var selectedEntries: [SFTPEntry] {
        entries.filter { selection.contains($0.name) }
    }

    var hasFinishedTransfers: Bool { transfers.contains(where: \.isFinished) }

    // MARK: Connexion

    /// Rattache le navigateur à la session qui vient d'être lancée dans l'onglet.
    func attach(_ connection: SFTPConnection) {
        detach()
        self.connection = connection
        phase = .waiting
    }

    /// La session de l'onglet est terminée : plus rien ne peut être lu ni transféré.
    func detach() {
        loadTask?.cancel()
        loadTask = nil
        loadNumber += 1
        for job in runningJobs.values {
            job.cancel()
        }
        for index in transfers.indices where transfers[index].state == .queued {
            transfers[index].state = .cancelled
        }
        plans = [:]
        connection = nil
        entries = []
        selection = []
        isBusy = false
        pendingUpload = nil
        phase = .notConnected
    }

    /// Appelé quand le navigateur devient visible : lit le dossier s'il ne l'a pas encore été.
    func activate() {
        guard connection != nil, loadTask == nil, phase == .waiting || phase == .loading else { return }
        load(path.isEmpty ? nil : path)
    }

    // MARK: Navigation

    func refresh() {
        guard connection != nil else { return }
        load(path.isEmpty ? nil : path)
    }

    func open(_ name: String) {
        guard canAct, let entry = entries.first(where: { $0.name == name }) else { return }
        // Un lien peut mener à un dossier : on essaie, et le serveur répond.
        guard entry.kind == .directory || entry.kind == .link else { return }
        selection = []
        load(SFTPPath.join(path, name))
    }

    func goUp() {
        guard canAct, path != "/" else { return }
        load(SFTPPath.parent(of: path))
    }

    func goToTypedPath() {
        guard connection != nil else { return }
        guard let target = SFTPPath.normalized(pathText) else {
            notice = L("Saisir un chemin absolu, commençant par « / », sans guillemet ni « * », « ? », « [ » ou « \\ ».")
            pathText = path
            return
        }
        load(target)
    }

    /// Lit un dossier. `nil` : le dossier d'arrivée de la session, demandé au serveur.
    func load(_ target: String?) {
        guard let connection else { return }
        loadTask?.cancel()
        loadNumber += 1
        let number = loadNumber
        notice = nil
        loadTask = Task {
            if !connection.isOpen {
                phase = .waiting
                while !connection.isOpen {
                    try? await Task.sleep(for: .milliseconds(500))
                    if Task.isCancelled { return }
                }
            }
            guard number == loadNumber else { return }
            phase = .loading

            var folder = target
            if folder == nil {
                let answer = await SFTPJob().run(connection: connection, commands: ["pwd"])
                guard number == loadNumber else { return }
                folder = SFTPListing.workingDirectory(in: answer.output)
                if folder == nil {
                    finishLoad(failure: L("Le dossier de départ n'a pas pu être lu : \(answer.failureText)"))
                    return
                }
            }
            guard let folder, let quoted = SFTPPath.quoted(folder) else {
                finishLoad(failure: L("Ce chemin contient un caractère que Pingouin ne sait pas transmettre à sftp."))
                return
            }
            // On entre dans le dossier avant de le lire : lu avec son chemin en argument,
            // `sftp` écrit le chemin complet devant chaque nom.
            let result = await SFTPJob().run(connection: connection, commands: ["cd \(quoted)", "ls -lan"])
            guard number == loadNumber else { return }
            guard result.succeeded else {
                finishLoad(failure: L("« \(folder) » n'a pas pu être lu : \(result.failureText)"))
                return
            }
            path = folder
            pathText = folder
            entries = SFTPListing.parse(result.output)
            selection = selection.intersection(entries.map(\.name))
            phase = .ready
            loadTask = nil
        }
    }

    /// Échec de lecture : on reste sur le dossier déjà affiché s'il y en a un.
    private func finishLoad(failure: String) {
        loadTask = nil
        AppLog.shared.warning("SFTP", failure)
        if path.isEmpty {
            phase = .failed(failure)
        } else {
            notice = failure
            pathText = path
            phase = .ready
        }
    }

    // MARK: Actions sur le dossier

    /// Problème d'un nouveau nom, ou `nil` s'il convient.
    func problem(inNewName name: String) -> String? {
        guard SFTPPath.isValidName(name) else {
            return L("Ce nom ne convient pas : il ne doit pas être vide ni contenir « / », guillemet, « * », « ? », « [ » ou « \\ ».")
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
        guard let quoted = SFTPPath.quoted(SFTPPath.join(path, name)) else { return }
        perform(["mkdir \(quoted)"], failure: L("Le dossier « \(name) » n'a pas pu être créé"))
    }

    func rename(_ oldName: String, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard name != oldName else { return }
        if let problem = problem(inNewName: name) {
            notice = problem
            return
        }
        guard let source = SFTPPath.quoted(SFTPPath.join(path, oldName)),
              let destination = SFTPPath.quoted(SFTPPath.join(path, name)) else {
            notice = unsupportedNotice(for: oldName)
            return
        }
        perform(["rename \(source) \(destination)"], failure: L("« \(oldName) » n'a pas pu être renommé"))
    }

    /// Supprime des fichiers, des liens et des dossiers vides. Un dossier non vide est refusé par le serveur.
    func delete(_ names: [String]) {
        var commands: [String] = []
        for entry in entries where names.contains(entry.name) {
            guard let quoted = SFTPPath.quoted(SFTPPath.join(path, entry.name)) else {
                notice = unsupportedNotice(for: entry.name)
                return
            }
            commands.append(entry.kind == .directory ? "rmdir \(quoted)" : "rm \(quoted)")
        }
        guard !commands.isEmpty else { return }
        perform(commands, failure: L("La suppression s'est arrêtée"))
    }

    func unsupportedNotice(for name: String) -> String {
        L("« \(name) » contient un caractère que Pingouin ne sait pas transmettre à sftp (guillemet, « * », « ? », « [ » ou « \\ »). Aucune action n'a été lancée.")
    }

    private func perform(_ commands: [String], failure: String) {
        guard let connection, canAct else { return }
        notice = nil
        isBusy = true
        Task {
            let result = await SFTPJob().run(connection: connection, commands: commands)
            // La session a pu se terminer ou changer pendant l'action.
            guard self.connection == connection else { return }
            isBusy = false
            // Le dossier est relu dans tous les cas : une suite de commandes a pu s'arrêter en chemin.
            load(path)
            if !result.succeeded {
                let text = "\(failure) : \(result.failureText)"
                notice = text
                AppLog.shared.warning("SFTP", text)
            }
        }
    }
}
