import SwiftUI
import PingouinCore

struct PortScanView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: PortScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            parameters
            tiles
            results
            Text(L("Fermé : l'hôte a refusé la connexion. Indéterminé : aucune réponse avant le délai, ce qui arrive souvent derrière un pare-feu."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { PingouinBackdrop() }
        .navigationTitle(L("Scan de ports"))
        .toolbar {
            ToolbarItem {
                Button {
                    Pasteboard.copy(model.text())
                } label: {
                    Label(L("Copier les résultats"), systemImage: "doc.on.doc")
                }
                .disabled(model.rows.isEmpty)
                .help(L("Copier les lignes affichées dans le presse-papiers"))
            }
            ToolbarItem(placement: .primaryAction) {
                if model.isRunning {
                    Button(L("Arrêter"), role: .cancel) {
                        model.cancel()
                    }
                } else {
                    Button(L("Lancer le scan")) {
                        model.requestScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .confirmationDialog(
            L("Lancer un scan étendu ?"),
            isPresented: Binding(
                get: { model.pendingConfirmationCount != nil },
                set: { isPresented in
                    if !isPresented { model.pendingConfirmationCount = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Lancer le scan")) {
                model.confirmScan()
            }
            Button(L("Annuler"), role: .cancel) {
                model.pendingConfirmationCount = nil
            }
        } message: {
            Text(L("Ce scan ouvrira \(model.pendingConfirmationCount ?? 0) connexions vers \(model.host). Il peut durer jusqu'à \(model.pendingWorstCaseMinutes) min si l'hôte ne répond pas, et ce trafic peut déclencher une alerte sur un équipement de sécurité."))
        }
    }

    // MARK: Paramètres

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField(L("Hôte")) {
                    TextField(L("Hôte"), text: $model.host, prompt: Text("192.168.1.20"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.requestScan() }
                }
                .frame(minWidth: 160, idealWidth: 220)

                LabeledField(L("Ports (liste et plages)")) {
                    TextField(L("Ports"), text: $model.portsText, prompt: Text("22, 80, 443, 8000-8100"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .disabled(model.scanAllPorts)
                        .onSubmit { model.requestScan() }
                    Toggle(L("Scanner tous les ports (1 à 65535)"), isOn: $model.scanAllPorts)
                        .toggleStyle(.checkbox)
                }
                .frame(minWidth: 200)

                LabeledField(L("Délai (ms)")) {
                    TextField(L("Délai"), text: $model.timeoutText)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .help(L("De 100 à 10 000 ms. C'est le temps d'attente sur chaque port qui ne répond pas."))
                }
                .frame(width: 90)

                LabeledField(L("Connexions simultanées")) {
                    TextField(L("Connexions simultanées"), text: $model.concurrencyText)
                        .labelsHidden()
                        .font(.body.monospaced())
                        .help(L("De 1 à 128. Une valeur élevée accélère le scan, mais certains équipements ignorent les connexions trop rapprochées."))
                    Button(L("Valeurs par défaut")) {
                        model.resetTuning()
                    }
                    .buttonStyle(.link)
                    .disabled(model.usesDefaultTuning)
                    .help(L("Revenir à 400 ms et 64 connexions"))
                }
                .frame(width: 150)
            }
            .disabled(model.isRunning)

            status
        }
        .glassCardPadded()
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle:
            Text(L("Saisir un hôte et des ports, puis lancer le scan. Depuis la Découverte LAN, un clic droit sur un hôte le lance directement."))
                .foregroundStyle(.secondary)
        case .running(let done, let total):
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text(L("\(done) sur \(total)"))
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
        case .finished(let summary):
            Label(summary, systemImage: "checkmark.circle")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    // MARK: Synthèse

    private var tiles: some View {
        HStack(spacing: 10) {
            StatTile(label: L("Ports testés"), value: model.testedCount.formatted())
            StatTile(label: L("Ouverts"), value: model.openCount.formatted(), tint: model.openCount > 0 ? .green : nil)
            StatTile(label: L("Fermés"), value: model.closedCount.formatted())
            StatTile(label: L("Indéterminés"), value: model.undeterminedCount.formatted(), tint: model.undeterminedCount > 0 ? .orange : nil)
        }
    }

    // MARK: Résultats

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Résultats"))
                    .font(.headline)
                Spacer()
                Picker(L("Filtre"), selection: $model.filter) {
                    ForEach(PortFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
                TableColumn(L("Port"), value: \.port) { row in
                    Text(String(row.port))
                        .font(.body.monospaced())
                }
                .width(min: 50, ideal: 70, max: 90)
                TableColumn(L("Service habituel"), value: \.service) { row in
                    Text(row.service.isEmpty ? "—" : row.service)
                        .foregroundStyle(row.service.isEmpty ? .secondary : .primary)
                }
                TableColumn(L("État"), value: \.stateOrder) { row in
                    StatusLabel(kind: row.stateKind, text: row.stateText)
                }
                TableColumn(L("Temps de connexion"), value: \.timeSortKey) { row in
                    Text(row.timeText)
                        .font(.body.monospaced())
                }
                TableColumn(L("Détail"), value: \.detail) { row in
                    Text(row.detail)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UInt16.self) { ids in
                rowMenu(ids)
            }
            .overlay {
                if model.rows.isEmpty, !model.isRunning {
                    emptyState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.testedCount > 0 {
            ContentUnavailableView(
                L("Aucun port ouvert ni indéterminé"),
                systemImage: "cable.connector.slash",
                description: Text(L("Tous les ports testés ont refusé la connexion. Choisir « Tous » pour les afficher."))
            )
        } else {
            ContentUnavailableView(
                L("Aucun résultat"),
                systemImage: "cable.connector",
                description: Text(L("Les ports apparaîtront ici au fil du scan."))
            )
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UInt16>) -> some View {
        if ids.count == 1, let id = ids.first, let row = model.row(id: id) {
            let host = model.scannedHost
            let port = Int(row.port)
            // Un port SSH propose la connexion SSH ; tout autre port propose le navigateur.
            if port == 22 || row.service.localizedCaseInsensitiveContains("ssh") {
                Button(L("Connexion SSH sur le port \(port)")) {
                    app.openSSH(host: host, port: port)
                }
                .disabled(host.isEmpty)
            } else {
                Button(L("Ouvrir dans le navigateur (http)")) {
                    Browser.open(scheme: "http", host: host, port: port)
                }
                .disabled(host.isEmpty)
                Button(L("Ouvrir dans le navigateur (https)")) {
                    Browser.open(scheme: "https", host: host, port: port)
                }
                .disabled(host.isEmpty)
                Divider()
                Button(L("Analyser en HTTP")) {
                    app.open(.http, target: "http://\(host):\(port)/")
                }
                .disabled(host.isEmpty)
                Button(L("Analyser en HTTPS")) {
                    app.open(.http, target: "https://\(host):\(port)/")
                }
                .disabled(host.isEmpty)
                Button(L("Analyser en TLS")) {
                    app.open(.tls, target: "\(host):\(port)")
                }
                .disabled(host.isEmpty)
            }
            Divider()
            Button(L("Copier le port")) {
                Pasteboard.copy(String(row.port))
            }
            Button(L("Copier la ligne")) {
                Pasteboard.copy(model.text(for: ids))
            }
        } else if ids.count > 1 {
            Button(L("Copier les \(ids.count) lignes")) {
                Pasteboard.copy(model.text(for: ids))
            }
        }
    }
}
