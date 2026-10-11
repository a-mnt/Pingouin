import SwiftUI
import PingouinCore

/// Découverte LAN sur iPhone et iPad. iOS ne laisse pas lire la table ARP : seuls les appareils qui
/// répondent au ping sont trouvés, sans leur adresse MAC.
struct MobileLANDiscoveryView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: LANDiscoveryViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage(L("Découverte LAN")) {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Hôtes trouvés"), value: model.hostCount.formatted())
                StatTile(label: L("Temps médian"), value: model.medianResponseText)
            }
            hosts
            MobileFootnote(text: L("Appui long sur un hôte pour lancer aussitôt un outil sur lui. Seul le réseau Wi-Fi directement raccordé est visible : un pare-feu, un autre VLAN ou l'isolation des clients Wi-Fi peuvent masquer des hôtes."))
        }
        .searchable(text: $model.searchText, prompt: L("Filtrer les hôtes"))
        .toolbar {
            MobileCopyItem(title: L("Copier la liste"), isDisabled: model.hostCount == 0) {
                model.rowsAsText
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

    // MARK: Saisie

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(L("Interface")) {
                HStack(spacing: 8) {
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
                    .pickerStyle(.menu)
                    Spacer(minLength: 0)
                    Button {
                        model.refreshInterfaces()
                    } label: {
                        Label(L("Actualiser les interfaces"), systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            LabeledField(L("Plage")) {
                TextField(L("Plage"), text: $model.rangeText, prompt: Text(verbatim: "192.168.1.0/24"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(start)
            }
            Toggle(L("Rechercher les noms"), isOn: $model.resolveNames)
            MobileRunButton(isRunning: model.isRunning, title: L("Lancer la découverte"), run: start) {
                model.cancel()
            }
            status
                .font(.subheadline)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func start() {
        isEditing = false
        model.requestScan()
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle:
            ToolStatusLine(content: .hint(L("Choisir une interface ou saisir une plage, puis lancer la découverte.")))
        case .running(let phase, let progress):
            ToolStatusLine(content: .progress(phase, fraction: progress))
        case .finished(let summary):
            ToolStatusLine(content: .done(summary))
        case .failed(let message):
            ToolStatusLine(content: .failure(message))
        }
    }

    // MARK: Hôtes

    @ViewBuilder
    private var hosts: some View {
        let rows = model.rows
        if rows.isEmpty {
            if !model.isRunning {
                MobileEmptyNote(text: model.hostCount > 0
                    ? L("Aucun hôte ne correspond au filtre.")
                    : L("Les hôtes apparaîtront ici au fil de la découverte."))
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    hostRow(row)
                }
            }
            .glassCardPadded(cornerRadius: 22)
        }
    }

    private func hostRow(_ row: LANHostRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.address)
                    .font(.body.monospaced())
                    .fontWeight(.semibold)
                Text(row.hostname.isEmpty ? "—" : row.hostname)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.responseText)
                    .font(.body.monospaced())
                StatusLabel(kind: row.statusKind, text: row.status)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            HostToolsMenu(address: row.address) { module, target in
                state.open(module, target: target)
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
                state.monitoring.addPingMonitor(name: row.hostname, host: row.address)
                state.show(.monitoring)
            }
            Button(L("Ajouter à la topologie")) {
                state.topology.addDiscoveredNode(name: row.hostname, address: row.address)
                state.show(.topology)
            }
            Divider()
            Button(L("Copier l'adresse IP")) {
                Pasteboard.copy(row.address)
            }
            Button(L("Copier la ligne")) {
                Pasteboard.copy(model.text(for: [row.id]))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
