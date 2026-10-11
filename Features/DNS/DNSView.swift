import PingouinCore
import SwiftUI

struct DNSView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: DNSViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Réponse"), value: model.responseSummary, monospaced: false)
                StatTile(label: L("Code"), value: model.responseCode)
                StatTile(label: L("Temps de résolution"), value: model.responseTime)
                StatTile(label: L("Serveur interrogé"), value: model.serverUsed)
            }
            records
            HStack(alignment: .top, spacing: 14) {
                comparison
                HistoryCard(entries: model.history) { entry in
                    model.name = entry.target
                    model.start()
                }
                .frame(width: 300)
            }
        }
        .toolPage("DNS")
        .toolbar {
            CopyToolbarItem(title: L("Copier les enregistrements"), isDisabled: model.records.isEmpty) {
                model.recordsAsText
            }
            RunToolbarItem(
                isRunning: model.isRunning,
                title: L("Interroger"),
                run: { model.start() },
                stop: { model.cancel() }
            )
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField(L("Nom de domaine ou adresse IP")) {
                    TextField(L("Nom"), text: $model.name, prompt: Text("example.com"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.start() }
                }
                .frame(minWidth: 240)

                LabeledField(L("Type")) {
                    Picker(L("Type"), selection: $model.type) {
                        ForEach(DNSRecordType.displayOrder) { type in
                            Text(type.name).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                .frame(width: 110)

                LabeledField(L("Serveur DNS")) {
                    Picker(L("Serveur DNS"), selection: $model.serverChoice) {
                        ForEach(DNSServerChoice.presets) { choice in
                            Text(model.label(for: choice)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    if model.serverChoice == .custom {
                        TextField(L("Adresse du serveur"), text: $model.customServer, prompt: Text("192.168.1.2"))
                            .labelsHidden()
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                    }
                }
                .frame(minWidth: 220, maxWidth: 300)
            }
            .disabled(model.isRunning)

            ToolStatusLine(content: model.status)
        }
        .glassCardPadded()
    }

    private var records: some View {
        Table(model.records, selection: $model.selection) {
            TableColumn(L("Nom")) { row in
                Text(row.name)
                    .font(.body.monospaced())
            }
            TableColumn(L("Type")) { row in
                Text(row.type)
                    .font(.body.monospaced())
            }
            .width(min: 50, ideal: 70, max: 90)
            TableColumn("TTL") { row in
                Text(row.ttl)
                    .font(.body.monospaced())
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn(L("Valeur")) { row in
                Text(row.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .help(row.value)
            }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Int.self) { ids in
            rowMenu(ids)
        }
        .overlay {
            if model.records.isEmpty, !model.isRunning {
                ContentUnavailableView(
                    L("Aucun enregistrement"),
                    systemImage: "globe",
                    description: Text(L("Les enregistrements reçus apparaîtront ici."))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private var comparison: some View {
        SectionCard(L("Comparer les serveurs")) {
            if model.comparison.isEmpty {
                HStack {
                    Text(L("Pose la même question au résolveur du système, à 1.1.1.1 et à 9.9.9.9."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.isComparing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(L("Comparer")) {
                            model.compareServers()
                        }
                        .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(model.comparison) { row in
                        GridRow {
                            Text(row.server)
                                .font(.body.monospaced())
                            StatusLabel(kind: row.statusKind, text: row.status)
                            Text(row.time)
                                .font(.body.monospaced())
                            Text(row.answer)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .help(row.answer)
                        }
                    }
                }
                Button(L("Comparer de nouveau")) {
                    model.compareServers()
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<Int>) -> some View {
        if ids.count == 1, let id = ids.first, let row = model.row(id: id) {
            // Seules les valeurs qui sont des adresses peuvent recevoir un outil réseau.
            if row.type == "A" {
                HostToolsMenu(address: row.value) { module, target in
                    app.open(module, target: target)
                }
                Divider()
            }
            Button(L("Copier la valeur")) {
                Pasteboard.copy(row.value)
            }
            Button(L("Copier la ligne")) {
                Pasteboard.copy("\(row.name)\t\(row.type)\t\(row.ttl)\t\(row.value)")
            }
        }
    }
}
