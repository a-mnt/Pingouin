import SwiftUI
import PingouinCore

/// Scan de ports sur iPhone et iPad : la saisie, la synthèse, puis un port par ligne.
struct MobilePortScanView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: PortScanViewModel
    @FocusState private var isEditing: Bool
    @State private var showsTuning = false

    /// Nombre de lignes montrées : au-delà, l'écran ne suit plus. « Copier » donne la liste entière.
    private static let displayLimit = 300

    var body: some View {
        MobilePage(L("Scan de ports")) {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Ports testés"), value: model.testedCount.formatted())
                StatTile(label: L("Ouverts"), value: model.openCount.formatted(), tint: model.openCount > 0 ? .green : nil)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Fermés"), value: model.closedCount.formatted())
                StatTile(label: L("Indéterminés"), value: model.undeterminedCount.formatted(), tint: model.undeterminedCount > 0 ? .orange : nil)
            }
            results
            MobileFootnote(text: L("Fermé : l'hôte a refusé la connexion. Indéterminé : aucune réponse avant le délai, ce qui arrive souvent derrière un pare-feu."))
        }
        .toolbar {
            MobileCopyItem(title: L("Copier les résultats"), isDisabled: model.testedCount == 0) {
                model.text()
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

    // MARK: Saisie

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(L("Hôte")) {
                TextField(L("Hôte"), text: $model.host, prompt: Text(verbatim: "192.168.1.20"))
                    .hostEntry()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(start)
            }
            LabeledField(L("Ports (liste et plages)")) {
                TextField(L("Ports"), text: $model.portsText, prompt: Text(verbatim: "22, 80, 443, 8000-8100"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .focused($isEditing)
                    .disabled(model.scanAllPorts)
            }
            Toggle(L("Scanner tous les ports (1 à 65535)"), isOn: $model.scanAllPorts)
            DisclosureGroup(L("Réglages du scan"), isExpanded: $showsTuning) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        LabeledField(L("Délai (ms)")) {
                            TextField(L("Délai"), text: $model.timeoutText)
                                .numberEntry()
                                .focused($isEditing)
                        }
                        LabeledField(L("Connexions simultanées")) {
                            TextField(L("Connexions simultanées"), text: $model.concurrencyText)
                                .numberEntry()
                                .focused($isEditing)
                        }
                    }
                    Text(L("Délai : de 100 à 10 000 ms, attendu sur chaque port qui ne répond pas. Connexions : de 1 à 128 ; trop rapprochées, certains équipements les ignorent."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(L("Valeurs par défaut")) {
                        model.resetTuning()
                    }
                    .disabled(model.usesDefaultTuning)
                }
                .padding(.top, 8)
            }
            MobileRunButton(isRunning: model.isRunning, title: L("Lancer le scan"), run: start) {
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
            ToolStatusLine(content: .hint(L("Saisir un hôte et des ports, puis lancer le scan.")))
        case .running(let done, let total):
            ToolStatusLine(content: .progress(L("\(done) sur \(total)"), fraction: total > 0 ? Double(done) / Double(total) : nil))
        case .finished(let summary):
            ToolStatusLine(content: .done(summary))
        case .failed(let message):
            ToolStatusLine(content: .failure(message))
        }
    }

    // MARK: Résultats

    private var results: some View {
        let rows = model.rows
        return VStack(alignment: .leading, spacing: 0) {
            Picker(L("Filtre"), selection: $model.filter) {
                ForEach(PortFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 8)

            if rows.isEmpty {
                if !model.isRunning {
                    Text(model.testedCount > 0
                        ? L("Tous les ports testés ont refusé la connexion. Choisir « Tous » pour les afficher.")
                        : L("Les ports apparaîtront ici au fil du scan."))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.prefix(Self.displayLimit)) { row in
                        portRow(row)
                        Divider()
                    }
                }
                if rows.count > Self.displayLimit {
                    Text(L("Les \(Self.displayLimit) premières lignes sur \(rows.count.formatted()). « Copier les résultats » donne la liste entière."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func portRow(_ row: PortRow) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: String(row.port))
                .font(.body.monospaced())
                .fontWeight(.semibold)
                .frame(minWidth: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                StatusLabel(kind: row.stateKind, text: row.stateText)
                Text(row.service.isEmpty ? row.detail : "\(row.service) · \(row.detail)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(row.timeText)
                .font(.body.monospaced())
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            rowMenu(row)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rowMenu(_ row: PortRow) -> some View {
        let host = model.scannedHost
        let port = row.port
        if !host.isEmpty {
            Button(L("Ouvrir dans le navigateur (http)")) {
                Browser.open(scheme: "http", host: host, port: port)
            }
            Button(L("Ouvrir dans le navigateur (https)")) {
                Browser.open(scheme: "https", host: host, port: port)
            }
            Divider()
            Button(L("Analyser en HTTP")) {
                state.open(.http, target: "http://\(host):\(port)/")
            }
            Button(L("Analyser en HTTPS")) {
                state.open(.http, target: "https://\(host):\(port)/")
            }
            Button(L("Analyser en TLS")) {
                state.open(.tls, target: "\(host):\(port)")
            }
            Divider()
        }
        Button(L("Copier le port")) {
            Pasteboard.copy(String(row.port))
        }
        Button(L("Copier la ligne")) {
            Pasteboard.copy(model.text(for: [row.id]))
        }
    }
}
