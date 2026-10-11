import Foundation
import PingouinCore

/// Transferts du navigateur de fichiers : téléchargements et envois, un seul à la fois.
extension SFTPBrowser {
    /// Télécharge les éléments choisis dans un dossier du Mac. Rien n'y est remplacé : un nom déjà pris
    /// reçoit un numéro.
    func download(_ names: [String], to folder: URL) {
        guard connection != nil else { return }
        for entry in entries where names.contains(entry.name) {
            let finalURL = Self.freeURL(for: entry.name, in: folder)
            let partialURL = folder.appendingPathComponent(".\(finalURL.lastPathComponent).pingouin-partiel")
            guard let remote = SFTPPath.quoted(SFTPPath.join(path, entry.name)),
                  let local = SFTPPath.quoted(partialURL.path) else {
                notice = unsupportedNotice(for: entry.name)
                continue
            }
            let isFolder = entry.kind == .directory
            let transfer = SFTPTransfer(
                name: entry.name,
                direction: .download,
                totalBytes: entry.kind == .file ? entry.size : nil,
                doneBytes: entry.kind == .file ? 0 : nil
            )
            plans[transfer.id] = Plan(
                command: "get \(isFolder ? "-r " : "")\(remote) \(local)",
                partialURL: partialURL,
                finalURL: finalURL
            )
            transfers.insert(transfer, at: 0)
        }
        startNextTransfer()
    }

    /// Demande l'envoi de fichiers ou de dossiers du Mac dans le dossier affiché.
    /// S'ils remplacent des éléments existants, l'accord est demandé d'abord.
    func requestUpload(_ urls: [URL]) {
        guard canAct, !urls.isEmpty else { return }
        let conflicts = urls.map(\.lastPathComponent).filter { name in entries.contains { $0.name == name } }
        if conflicts.isEmpty {
            upload(urls)
        } else {
            pendingUpload = SFTPPendingUpload(urls: urls, conflicts: conflicts)
        }
    }

    /// Lance l'envoi en attente. `replacing` faux : seuls les éléments sans homonyme sont envoyés.
    func confirmPendingUpload(replacing: Bool) {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        upload(replacing ? pending.urls : pending.urls.filter { !pending.conflicts.contains($0.lastPathComponent) })
    }

    private func upload(_ urls: [URL]) {
        guard connection != nil else { return }
        for url in urls {
            let name = url.lastPathComponent
            guard SFTPPath.isValidName(name),
                  let local = SFTPPath.quoted(url.path),
                  let remote = SFTPPath.quoted(SFTPPath.join(path, name)) else {
                notice = unsupportedNotice(for: name)
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isFolder = values?.isDirectory == true
            let transfer = SFTPTransfer(
                name: name,
                direction: .upload,
                totalBytes: isFolder ? nil : values?.fileSize.map { UInt64($0) },
                doneBytes: nil
            )
            plans[transfer.id] = Plan(command: "put \(isFolder ? "-r " : "")\(local) \(remote)", remoteFolder: path)
            transfers.insert(transfer, at: 0)
        }
        startNextTransfer()
    }

    func cancelTransfer(_ id: UUID) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        if transfers[index].state == .queued {
            transfers[index].state = .cancelled
            plans[id] = nil
        } else {
            runningJobs[id]?.cancel()
        }
    }

    func clearFinishedTransfers() {
        transfers.removeAll(where: \.isFinished)
    }

    /// Un seul transfert à la fois : un serveur SSH limite le nombre de canaux d'une même connexion.
    private func startNextTransfer() {
        guard let connection, runningJobs.isEmpty,
              let index = transfers.lastIndex(where: { $0.state == .queued }) else { return }
        let id = transfers[index].id
        guard let plan = plans.removeValue(forKey: id) else {
            transfers[index].state = .cancelled
            startNextTransfer()
            return
        }
        transfers[index].state = .running
        let job = SFTPJob()
        runningJobs[id] = job

        Task {
            // Avancement d'un téléchargement : la taille du fichier provisoire, relue deux fois par seconde.
            let watcher = Task {
                guard let partialURL = plan.partialURL else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    let size = (try? partialURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                    if let size, let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].doneBytes != nil {
                        transfers[index].doneBytes = UInt64(size)
                    }
                }
            }
            let result = await job.run(connection: connection, commands: [plan.command])
            watcher.cancel()
            runningJobs[id] = nil
            finishTransfer(id, plan: plan, result: result)
            startNextTransfer()
        }
    }

    private func finishTransfer(_ id: UUID, plan: Plan, result: SFTPResult) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        let name = transfers[index].name
        var state: SFTPTransfer.State
        if result.wasCancelled {
            state = .cancelled
        } else if result.succeeded {
            state = .done
        } else {
            state = .failed(result.failureText)
        }

        if let partialURL = plan.partialURL, let finalURL = plan.finalURL {
            let files = FileManager.default
            if state == .done {
                do {
                    try files.moveItem(at: partialURL, to: finalURL)
                    transfers[index].doneBytes = transfers[index].totalBytes
                } catch {
                    state = .failed(L("Le fichier reçu n'a pas pu être rangé sous son nom : \(error.localizedDescription)"))
                }
            } else if files.fileExists(atPath: partialURL.path) {
                // Un téléchargement incomplet ne reste pas sur le disque.
                do {
                    try files.removeItem(at: partialURL)
                } catch {
                    AppLog.shared.warning("SFTP", "Le fichier provisoire « \(partialURL.lastPathComponent) » n'a pas pu être retiré : \(error.localizedDescription)")
                }
            }
        }

        transfers[index].state = state
        let verb = transfers[index].direction == .upload ? L("Envoi") : L("Téléchargement")
        switch state {
        case .done:
            AppLog.shared.info("SFTP", "\(verb) de « \(name) » terminé.")
        case .failed(let reason):
            AppLog.shared.warning("SFTP", "\(verb) de « \(name) » en échec : \(reason)")
        default:
            AppLog.shared.info("SFTP", "\(verb) de « \(name) » interrompu.")
        }
        if let remoteFolder = plan.remoteFolder, remoteFolder == path, phase == .ready {
            load(path)
        }
    }

    /// Emplacement libre pour un nom dans un dossier : « nom », sinon « nom 2 », « nom 3 »…
    private static func freeURL(for name: String, in folder: URL) -> URL {
        let files = FileManager.default
        let first = folder.appendingPathComponent(name)
        guard files.fileExists(atPath: first.path) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for number in 2...999 {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            if !files.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return folder.appendingPathComponent("\(base) \(UUID().uuidString.prefix(8))" + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
