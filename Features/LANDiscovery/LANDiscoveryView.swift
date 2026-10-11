import PingouinCore
import SwiftUI

struct LANDiscoveryView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: LANDiscoveryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            parameters
            tiles
            hosts
            if !model.ipv6OnlyNeighbors.isEmpty {
                ipv6OnlyNeighbors
            }
            Text(L("Clic droit sur une ligne pour lancer aussitôt un outil sur cet hôte. Seul le sous-réseau directement raccordé est visible : un pare-feu, un autre VLAN ou l'isolation des clients Wi-Fi peuvent masquer des hôtes."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { PingouinBackdrop() }
        .navigationTitle(L("Découverte LAN"))
        .searchable(text: $model.searchText, prompt: L("Filtrer les hôtes"))
        .toolbar {
            ToolbarItem {
                Button {
                    Pasteboard.copy(model.rowsAsText)
                } label: {
                    Label(L("Copier la liste"), systemImage: "doc.on.doc")
                }
                .disabled(model.rows.isEmpty)
                .help(L("Copier les hôtes affichés dans le presse-papiers"))
            }
            ToolbarItem(placement: .primaryAction) {
                if model.isRunning {
                    Button(L("Arrêter"), role: .cancel) {
                        model.cancel()
                    }
                } else {
                    Button(L("Lancer la découverte")) {
                        model.requestScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .confirmationDialog(
            L("Lancer une découverte étendue ?"),
            isPresented: Binding(
                get: { model.pendingConfirmationCount != nil },
                set: { isPresented in
                    if !isPresented { model.pendingConfirmationCount = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Lancer la découverte")) {
                model.confirmScan()
            }
            Button(L("Annuler"), role: .cancel) {
                model.pendingConfirmationCount = nil
            }
        } message: {
            Text(L("Cette plage contient \(model.pendingConfirmationCount ?? 0) adresses. Chacune recevra deux requêtes ping, ce qui génère un trafic visible sur le réseau."))
        }
        .task {
            if model.interfaces.isEmpty {
                model.refreshInterfaces()
            }
        }
    }

    // MARK: Paramètres

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                LabeledField(L("Interface")) {
                    HStack(spacing: 6) {
                        Picker(L("Interface"), selection: $model.selectedInterfaceID) {
                            if model.interfaces.isEmpty {
                                Text(L("Aucune interface IPv4 active")).tag(String?.none)
                            }
                            ForEach(model.interfaces) { interface in
                                Text(verbatim: "\(interface.name) · \(interface.address.description)")
                                    .tag(Optional(interface.id))
                            }
                        }
                        .labelsHidden()

                        Button {
                            model.refreshInterfaces()
                        } label: {
                            Label(L("Actualiser les interfaces"), systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .help(L("Relire la liste des interfaces"))
                    }
                }
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)

                LabeledField(L("Plage")) {
                    TextField(L("Plage"), text: $model.rangeText, prompt: Text("192.168.1.0/24"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.requestScan() }
                }
                .frame(minWidth: 150, idealWidth: 190, maxWidth: 240)

                Toggle(L("Rechercher les noms"), isOn: $model.resolveNames)
                    .padding(.bottom, 3)

                Toggle(L("Adresses IPv6"), isOn: $model.includeIPv6)
                    .padding(.bottom, 3)
                    .help(L("Sollicite les voisins IPv6 de l'interface, puis rattache leurs adresses aux hôtes par leur adresse MAC"))

                Spacer(minLength: 0)
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
            Text(L("Choisir une interface ou saisir une plage, puis lancer la découverte."))
                .foregroundStyle(.secondary)
        case .running(let phase, let progress):
            HStack(spacing: 10) {
                if let progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(phase)
                    .foregroundStyle(.secondary)
                    .fixedSize()
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
            StatTile(label: L("Hôtes trouvés"), value: model.hostCount.formatted())
            StatTile(label: L("Répondent au ping"), value: model.pingReplyCount.formatted())
            StatTile(label: L("ARP uniquement"), value: model.arpOnlyCount.formatted())
            StatTile(label: L("Temps médian"), value: model.medianResponseText)
        }
    }

    // MARK: Hôtes

    private var hosts: some View {
        Table(model.rows, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn(L("Adresse"), value: \.addressValue) { row in
                Text(row.address)
                    .font(.body.monospaced())
            }
            TableColumn(L("Nom"), value: \.hostname) { row in
                Text(row.hostname.isEmpty ? "—" : row.hostname)
                    .foregroundStyle(row.hostname.isEmpty ? .secondary : .primary)
            }
            TableColumn(L("Adresse MAC"), value: \.macAddress) { row in
                Text(row.macAddress.isEmpty ? "—" : row.macAddress)
                    .font(.body.monospaced())
                    .foregroundStyle(row.macAddress.isEmpty ? .secondary : .primary)
            }
            TableColumn(L("IPv6"), value: \.ipv6) { row in
                Text(row.ipv6.isEmpty ? "—" : row.ipv6)
                    .font(.callout.monospaced())
                    .foregroundStyle(row.ipv6.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .help(row.ipv6)
            }
            TableColumn(L("Temps"), value: \.responseSortKey) { row in
                Text(row.responseText)
                    .font(.body.monospaced())
            }
            TableColumn(L("État"), value: \.status) { row in
                StatusLabel(kind: row.statusKind, text: row.status)
            }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UInt32.self) { ids in
            rowMenu(ids)
        }
        .overlay {
            if model.rows.isEmpty, !model.isRunning {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    /// Appareils de la table des voisins IPv6 qui n'ont pas d'adresse IPv4 sur la plage.
    private var ipv6OnlyNeighbors: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Vus seulement en IPv6"))
                .font(.headline)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(model.ipv6OnlyNeighbors) { neighbor in
                        GridRow {
                            Text(neighbor.macAddress.description)
                                .font(.callout.monospaced())
                            Text(neighbor.addresses.map(\.description).joined(separator: ", "))
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
        }
        .glassCardPadded()
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.hostCount > 0 {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            ContentUnavailableView(
                L("Aucun hôte à afficher"),
                systemImage: "dot.radiowaves.left.and.right",
                description: Text(L("Les hôtes apparaîtront ici au fil de la découverte."))
            )
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UInt32>) -> some View {
        if ids.count == 1, let id = ids.first, let row = model.row(id: id) {
            HostToolsMenu(address: row.address) { module, target in
                app.open(module, target: target)
            }
            Divider()
            Button(L("Ouvrir dans le navigateur (http)")) {
                Browser.open(scheme: "http", host: row.address)
            }
            Button(L("Ouvrir dans le navigateur (https)")) {
                Browser.open(scheme: "https", host: row.address)
            }
            Divider()
            Button(L("Ajouter à la supervision")) {
                // Surveillance par ping, toutes les minutes ; la supervision s'ouvre pour la montrer.
                app.monitoring.addPingMonitor(name: row.hostname, host: row.address)
                app.selection = .monitoring
            }
            Button(L("Ajouter à la topologie")) {
                app.topology.addDiscoveredNode(name: row.hostname, address: row.address)
                app.selection = .topology
            }
            Divider()
            Button(L("Copier l'adresse IP")) {
                Pasteboard.copy(row.address)
            }
            Button(L("Copier les adresses IPv6")) {
                Pasteboard.copy(row.ipv6)
            }
            .disabled(row.ipv6.isEmpty)
            Button(L("Copier l'adresse MAC")) {
                Pasteboard.copy(row.macAddress)
            }
            .disabled(row.macAddress.isEmpty)
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
