import AppKit
import PingouinCore
import SwiftUI

/// Navigateur de fichiers d'un onglet SSH : dossier distant, actions et transferts.
struct SFTPBrowserView: View {
    @Bindable var browser: SFTPBrowser
    /// Vrai tant que la session de l'onglet est ouverte.
    let isSessionActive: Bool
    let showTerminal: () -> Void
    let reconnect: () -> Void

    @State private var isNamingFolder = false
    @State private var renamedEntry: String?
    @State private var typedName = ""
    @State private var pendingDeletion: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar
            list
            if let notice = browser.notice {
                // Hauteur bornée, sans « fixedSize » : un texte de hauteur libre fait calculer à la fenêtre
                // une hauteur minimale démesurée, et tout son contenu déborde vers le haut.
                Label(notice, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .lineLimit(2)
                    .help(notice)
                    .padding(.horizontal, 8)
            }
            if !browser.transfers.isEmpty {
                SFTPTransfersView(browser: browser)
            }
        }
        .task(id: browser.phase) {
            browser.activate()
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
            L("Renommer « \(renamedEntry ?? "") »"),
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
            deletionTitle,
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { isPresented in
                    if !isPresented { pendingDeletion = [] }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                browser.delete(pendingDeletion)
                pendingDeletion = []
            }
            Button(L("Annuler"), role: .cancel) {
                pendingDeletion = []
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

    private var deletionTitle: String {
        pendingDeletion.count == 1
            ? L("Supprimer « \(pendingDeletion[0]) » du serveur ?")
            : L("Supprimer \(pendingDeletion.count) éléments du serveur ?")
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
            .disabled(!browser.canAct || browser.path == "/")
            .help(L("Monter au dossier parent"))

            TextField(L("Chemin du dossier"), text: $browser.pathText)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit {
                    browser.goToTypedPath()
                }
                .disabled(browser.phase == .notConnected || browser.phase == .waiting)

            Button {
                browser.refresh()
            } label: {
                Label(L("Actualiser"), systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .disabled(browser.phase == .notConnected || browser.phase == .waiting)
            .help(L("Relire le dossier"))

            Button(L("Nouveau dossier")) {
                typedName = ""
                isNamingFolder = true
            }
            .disabled(!browser.canAct)

            Button(L("Envoyer…")) {
                chooseFilesToUpload()
            }
            .disabled(!browser.canAct)
            .help(L("Envoyer des fichiers ou des dossiers du Mac dans ce dossier"))

            Button(L("Télécharger…")) {
                download(Array(browser.selection))
            }
            .disabled(!browser.canAct || browser.selection.isEmpty)
            .help(L("Télécharger la sélection dans un dossier du Mac"))
        }
    }

    // MARK: Liste

    private var list: some View {
        Table(browser.entries, selection: $browser.selection) {
            TableColumn(L("Nom")) { entry in
                Label(entry.name, systemImage: symbol(for: entry))
                    .lineLimit(1)
            }
            TableColumn(L("Taille")) { entry in
                Text(entry.kind == .file ? ByteFormat.volume(entry.size) : "—")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn(L("Modifié")) { entry in
                Text(entry.modified?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160, max: 200)
            TableColumn(L("Droits")) { entry in
                Text(entry.permissions)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100, max: 120)
        }
        .contextMenu(forSelectionType: SFTPEntry.ID.self) { names in
            menu(for: names)
        } primaryAction: { names in
            if let name = names.first, names.count == 1 {
                browser.open(name)
            }
        }
        .scrollContentBackground(.hidden)
        // La liste n'est jamais désactivée : la désactiver pendant son propre double-clic lui retire
        // le clavier en plein événement. Les actions vérifient elles-mêmes qu'elles sont possibles.
        .dropDestination(for: URL.self) { urls, _ in
            guard browser.canAct else { return false }
            browser.requestUpload(urls.filter(\.isFileURL))
            return true
        }
        .overlay {
            status
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    @ViewBuilder
    private func menu(for names: Set<String>) -> some View {
        if names.isEmpty {
            Button(L("Actualiser")) {
                browser.refresh()
            }
            Button(L("Nouveau dossier…")) {
                typedName = ""
                isNamingFolder = true
            }
            Button(L("Envoyer…")) {
                chooseFilesToUpload()
            }
        } else {
            if names.count == 1, let name = names.first {
                Button(L("Ouvrir")) {
                    browser.open(name)
                }
                .disabled(!canOpen(name))
            }
            Button(L("Télécharger…")) {
                download(Array(names))
            }
            Divider()
            if names.count == 1, let name = names.first {
                Button(L("Renommer…")) {
                    typedName = name
                    renamedEntry = name
                }
                Button(L("Copier le chemin")) {
                    Pasteboard.copy(SFTPPath.join(browser.path, name))
                }
                Divider()
            }
            Button(L("Supprimer…"), role: .destructive) {
                pendingDeletion = Array(names).sorted()
            }
        }
    }

    private func canOpen(_ name: String) -> Bool {
        guard let entry = browser.entries.first(where: { $0.name == name }) else { return false }
        return entry.kind == .directory || entry.kind == .link
    }

    private func symbol(for entry: SFTPEntry) -> String {
        switch entry.kind {
        case .directory: "folder"
        case .file: "doc"
        case .link: "arrowshape.turn.up.right"
        case .other: "questionmark.square.dashed"
        }
    }

    /// Ce qui remplace la liste quand elle ne peut pas être montrée.
    @ViewBuilder
    private var status: some View {
        switch browser.phase {
        case .notConnected:
            ContentUnavailableView {
                Label(L("Session fermée"), systemImage: "bolt.horizontal.circle")
            } description: {
                Text(L("Les fichiers sont lus par la connexion de cet onglet."))
            } actions: {
                Button(L("Se reconnecter"), action: reconnect)
            }
        case .waiting:
            ContentUnavailableView {
                Label(L("Ouverture de la session…"), systemImage: "hourglass")
            } description: {
                Text(isSessionActive
                    ? L("Si le terminal attend un mot de passe ou votre accord sur la clé d'hôte, répondez-y : les fichiers s'afficheront ensuite.")
                    : L("La session n'est pas ouverte."))
            } actions: {
                Button(L("Afficher le terminal"), action: showTerminal)
            }
        case .loading:
            if browser.entries.isEmpty {
                ProgressView(L("Lecture du dossier…"))
            }
        case .failed(let message):
            ContentUnavailableView {
                Label(L("Dossier illisible"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(L("Réessayer")) {
                    browser.refresh()
                }
            }
        case .ready:
            if browser.entries.isEmpty {
                ContentUnavailableView(
                    L("Dossier vide"),
                    systemImage: "folder",
                    description: Text(L("Glisser des fichiers ici depuis le Finder pour les envoyer."))
                )
            }
        }
    }

    // MARK: Panneaux du Finder

    private func chooseFilesToUpload() {
        let panel = NSOpenPanel()
        panel.title = L("Envoyer vers « \(browser.path) »")
        panel.prompt = L("Envoyer")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            browser.requestUpload(panel.urls)
        }
    }

    private func download(_ names: [String]) {
        guard !names.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = L("Télécharger dans…")
        panel.prompt = L("Télécharger ici")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folder = panel.url {
            browser.download(names, to: folder)
        }
    }
}
