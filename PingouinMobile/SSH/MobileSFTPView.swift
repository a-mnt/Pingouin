import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import PingouinCore

/// Navigateur de fichiers d'une session SSH : dossier distant, actions et transferts.
struct MobileSFTPView: View {
    @Bindable var browser: MobileSFTPBrowser

    @State private var isNamingFolder = false
    @State private var renamedEntry: SFTPEntry?
    @State private var typedName = ""
    @State private var pendingDeletion: SFTPEntry?
    @State private var isImportingFiles = false
    @State private var isPickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var sharedFile: SharedFile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                bar
                list
                if let notice = browser.notice {
                    Label(notice, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                }
                if !browser.transfers.isEmpty {
                    MobileSFTPTransfersCard(browser: browser) { url in
                        sharedFile = SharedFile(url: url)
                    }
                }
                MobileFootnote(text: L("Toucher un dossier pour l'ouvrir, un fichier pour le télécharger. Appui long : renommer, copier le chemin, supprimer. Les transferts s'arrêtent si Pingouin quitte l'écran : iOS suspend l'application."))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .task {
            browser.activate()
        }
        .sheet(item: $sharedFile) { file in
            MobileShareSheet(file: file)
        }
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                browser.requestUpload(urls)
            }
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photoItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                let urls = await MobilePhotoExport.files(for: items)
                if urls.count < items.count {
                    browser.notice = L("Certaines photos n'ont pas pu être lues et n'ont pas été envoyées.")
                }
                browser.requestUpload(urls)
            }
        }
        .alert(L("Nouveau dossier"), isPresented: $isNamingFolder) {
            TextField(L("Nom du dossier"), text: $typedName)
            Button(L("Créer")) {
                browser.makeFolder(named: typedName)
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Le dossier est créé dans « \(browser.path) »."))
        }
        .alert(
            L("Renommer « \(renamedEntry?.name ?? "") »"),
            isPresented: Binding(
                get: { renamedEntry != nil },
                set: { isPresented in
                    if !isPresented { renamedEntry = nil }
                }
            )
        ) {
            TextField(L("Nouveau nom"), text: $typedName)
            Button(L("Renommer")) {
                if let renamedEntry {
                    browser.rename(renamedEntry, to: typedName)
                }
                renamedEntry = nil
            }
            Button(L("Annuler"), role: .cancel) {
                renamedEntry = nil
            }
        }
        .confirmationDialog(
            L("Supprimer « \(pendingDeletion?.name ?? "") » du serveur ?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                if let pendingDeletion {
                    browser.delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button(L("Annuler"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(L("La suppression sur le serveur est définitive. Un dossier doit être vide pour être supprimé."))
        }
        .confirmationDialog(
            L("Remplacer \(browser.pendingUpload?.conflicts.count ?? 0) élément(s) sur le serveur ?"),
            isPresented: Binding(
                get: { browser.pendingUpload != nil },
                set: { isPresented in
                    if !isPresented { browser.pendingUpload = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Remplacer"), role: .destructive) {
                browser.confirmPendingUpload(replacing: true)
            }
            Button(L("Envoyer seulement les nouveaux")) {
                browser.confirmPendingUpload(replacing: false)
            }
            Button(L("Annuler"), role: .cancel) {
                browser.pendingUpload = nil
            }
        } message: {
            Text(L("Déjà présents dans « \(browser.path) » : \((browser.pendingUpload?.conflicts ?? []).joined(separator: ", "))."))
        }
    }

    // MARK: Barre de chemin et d'actions

    private var bar: some View {
        HStack(spacing: 8) {
            Button {
                browser.goUp()
            } label: {
                Label(L("Dossier parent"), systemImage: "arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!browser.canAct || browser.path == "/")

            Text(browser.path.isEmpty ? "—" : browser.path)
                .font(.footnote.monospaced())
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 14)

            Menu {
                Button(L("Envoyer depuis Fichiers…")) {
                    isImportingFiles = true
                }
                .disabled(!browser.canAct)
                Button(L("Envoyer depuis Photos…")) {
                    isPickingPhotos = true
                }
                .disabled(!browser.canAct)
                Button(L("Nouveau dossier…")) {
                    typedName = ""
                    isNamingFolder = true
                }
                .disabled(!browser.canAct)
                Divider()
                Button(L("Actualiser")) {
                    browser.refresh()
                }
            } label: {
                Label(L("Actions sur le dossier"), systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(height: 20)
            }
            .buttonStyle(.bordered)
            .disabled(browser.phase == .notConnected)
        }
    }

    // MARK: Liste

    @ViewBuilder
    private var list: some View {
        switch browser.phase {
        case .notConnected:
            MobileEmptyNote(text: L("Les fichiers sont lus par la connexion de cette session : elle est fermée."))
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(L("Lecture du dossier…"))
                    .foregroundStyle(.secondary)
            }
            .glassCardPadded(cornerRadius: 22)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button(L("Réessayer")) {
                    browser.refresh()
                }
                .buttonStyle(.bordered)
            }
            .glassCardPadded(cornerRadius: 22)
        case .ready:
            if browser.entries.isEmpty {
                MobileEmptyNote(text: L("Dossier vide"))
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(browser.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                        }
                        row(entry)
                    }
                }
                .glassCardPadded(cornerRadius: 22)
            }
        }
    }

    private func row(_ entry: SFTPEntry) -> some View {
        Button {
            if entry.kind == .file {
                browser.download(entry)
            } else {
                browser.open(entry)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(for: entry))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.callout.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail(of: entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(entry.kind == .file ? ByteFormat.volume(entry.size) : "—")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!browser.canAct)
        .contextMenu {
            if entry.kind == .file || entry.kind == .link {
                Button(L("Télécharger")) {
                    browser.download(entry)
                }
            }
            Button(L("Renommer…")) {
                typedName = entry.name
                renamedEntry = entry
            }
            Button(L("Copier le chemin")) {
                Pasteboard.copy(SFTPPath.join(browser.path, entry.name))
            }
            Divider()
            Button(L("Supprimer…"), role: .destructive) {
                pendingDeletion = entry
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(of entry: SFTPEntry) -> String {
        let date = entry.modified?.formatted(date: .abbreviated, time: .shortened)
        return [date, entry.permissions].compactMap { $0 }.joined(separator: " · ")
    }

    private func symbol(for entry: SFTPEntry) -> String {
        switch entry.kind {
        case .directory: "folder"
        case .file: "doc"
        case .link: "arrowshape.turn.up.right"
        case .other: "questionmark.square.dashed"
        }
    }
}

/// Copie des photos choisies dans le dossier temporaire de l'application, pour pouvoir les envoyer.
enum MobilePhotoExport {
    static func files(for items: [PhotosPickerItem]) async -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("envois-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var urls: [URL] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let type = item.supportedContentTypes.first
            let prefix = type?.conforms(to: .movie) == true ? "video" : "photo"
            let url = folder.appendingPathComponent("\(prefix)-\(stamp)-\(index + 1).\(type?.preferredFilenameExtension ?? "jpg")")
            do {
                try data.write(to: url, options: .atomic)
                urls.append(url)
            } catch {
                continue
            }
        }
        return urls
    }
}
