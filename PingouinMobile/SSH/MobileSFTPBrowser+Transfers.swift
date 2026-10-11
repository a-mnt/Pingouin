import Foundation
import PingouinCore

/// Téléchargements et envois d'un navigateur de fichiers.
extension MobileSFTPBrowser {
    /// Dossier temporaire où arrivent les téléchargements, avant d'être remis à la feuille de partage.
    private static var downloadsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("telechargements-sftp", isDirectory: true)
    }

    // MARK: Téléchargement

    /// Télécharge un fichier dans le dossier temporaire de l'application.
    func download(_ entry: SFTPEntry) {
        guard let link, phase == .ready else { return }
        guard entry.kind == .file || entry.kind == .link else {
            notice = L("Seuls les fichiers se téléchargent : ouvrir le dossier pour choisir ses fichiers.")
            return
        }
        // Chaque téléchargement a son dossier : deux fichiers de même nom ne s'écrasent pas.
        var transfer = MobileTransfer(name: entry.name, direction: .download, totalBytes: entry.kind == .file ? entry.size : nil)
        let folder = Self.downloadsFolder.appendingPathComponent(transfer.id.uuidString, isDirectory: true)
        let localURL = folder.appendingPathComponent(entry.name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            notice = L("Le téléchargement n'a pas pu commencer : \(error.localizedDescription)")
            return
        }
        transfer.localURL = localURL
        transfers.insert(transfer, at: 0)
        let id = transfer.id
        let remotePath = SFTPPath.join(path, entry.name)
        transferTasks[id] = Task {
            do {
                try await link.download(remotePath, to: localURL) { done in
                    self.update(id) { $0.doneBytes = done }
                }
                finish(id, state: .done)
                AppLog.shared.info("SFTP", "Téléchargement terminé : \(entry.name).")
            } catch {
                try? FileManager.default.removeItem(at: folder)
                update(id) { $0.localURL = nil }
                finish(id, state: error is CancellationError ? .cancelled : .failed(SSHLink.describe(error)))
            }
        }
    }

    // MARK: Envoi

    /// Demande l'envoi de fichiers locaux dans le dossier affiché. Si des fichiers du même nom
    /// existent déjà sur le serveur, l'accord de l'utilisateur est demandé avant de les remplacer.
    func requestUpload(_ urls: [URL]) {
        guard phase == .ready, !urls.isEmpty else { return }
        let existing = Set(entries.map(\.name))
        let conflicts = urls.map(\.lastPathComponent).filter { existing.contains($0) }
        if conflicts.isEmpty {
            upload(urls)
        } else {
            pendingUpload = MobilePendingUpload(urls: urls, conflicts: conflicts.sorted())
        }
    }

    /// Suite d'un envoi mis en attente. `replacing` faux : seuls les fichiers nouveaux partent.
    func confirmPendingUpload(replacing: Bool) {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        let conflicts = Set(pending.conflicts)
        upload(replacing ? pending.urls : pending.urls.filter { !conflicts.contains($0.lastPathComponent) })
    }

    private func upload(_ urls: [URL]) {
        guard let link else { return }
        let folder = path
        for url in urls {
            let name = url.lastPathComponent
            guard SFTPMode.isValidName(name) else {
                notice = L("« \(name) » ne peut pas servir de nom sur le serveur. Ce fichier n'a pas été envoyé.")
                continue
            }
            // Un fichier choisi dans Fichiers n'est lisible qu'entre ces deux appels.
            let isScoped = url.startAccessingSecurityScopedResource()
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if isScoped { url.stopAccessingSecurityScopedResource() }
                notice = L("« \(name) » est un dossier : seuls les fichiers s'envoient.")
                continue
            }
            let transfer = MobileTransfer(name: name, direction: .upload, totalBytes: values?.fileSize.map { UInt64($0) })
            transfers.insert(transfer, at: 0)
            let id = transfer.id
            let remotePath = SFTPPath.join(folder, name)
            transferTasks[id] = Task {
                defer {
                    if isScoped { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    try await link.upload(url, to: remotePath) { done in
                        self.update(id) { $0.doneBytes = done }
                    }
                    finish(id, state: .done)
                    AppLog.shared.info("SFTP", "Envoi terminé : \(name).")
                    // Le dossier est relu s'il est toujours celui qui est affiché.
                    if self.link === link, path == folder {
                        load(folder)
                    }
                } catch {
                    finish(id, state: error is CancellationError ? .cancelled : .failed(SSHLink.describe(error)))
                }
            }
        }
    }

    // MARK: Suivi

    func cancel(_ id: UUID) {
        transferTasks[id]?.cancel()
    }

    /// Retire de la liste les transferts terminés, et supprime les fichiers téléchargés qu'ils gardaient.
    func clearFinished() {
        for transfer in transfers where transfer.isFinished {
            if let url = transfer.localURL {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        }
        transfers.removeAll(where: \.isFinished)
    }

    private func update(_ id: UUID, _ change: (inout MobileTransfer) -> Void) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        change(&transfers[index])
    }

    private func finish(_ id: UUID, state: MobileTransfer.State) {
        transferTasks[id] = nil
        update(id) { $0.state = state }
        if case .failed(let message) = state {
            AppLog.shared.warning("SFTP", "Transfert en échec : \(message)")
        }
    }
}
