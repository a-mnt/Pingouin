import SwiftUI
import PingouinCore

/// DNS sur iPhone et iPad : la question, la réponse, les enregistrements, puis la comparaison de serveurs.
struct MobileDNSView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: DNSViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage("DNS") {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Réponse"), value: model.responseSummary, monospaced: false)
                StatTile(label: L("Code"), value: model.responseCode)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Temps de résolution"), value: model.responseTime)
                StatTile(label: L("Serveur interrogé"), value: model.serverUsed)
            }
            if model.records.isEmpty {
                if !model.isRunning {
                    MobileEmptyNote(text: L("Les enregistrements reçus apparaîtront ici."))
                }
            } else {
                records
            }
            comparison
        }
        .toolbar {
            MobileCopyItem(title: L("Copier les enregistrements"), isDisabled: model.records.isEmpty) {
                model.recordsAsText
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(L("Nom de domaine ou adresse IP")) {
                TextField(L("Nom"), text: $model.name, prompt: Text(verbatim: "example.com"))
                    .hostEntry()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(start)
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(L("Type")) {
                    Picker(L("Type"), selection: $model.type) {
                        ForEach(DNSRecordType.displayOrder) { type in
                            Text(type.name).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                LabeledField(L("Serveur DNS")) {
                    Picker(L("Serveur DNS"), selection: $model.serverChoice) {
                        ForEach(DNSServerChoice.presets) { choice in
                            Text(model.label(for: choice)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.serverChoice == .custom {
                TextField(L("Adresse du serveur"), text: $model.customServer, prompt: Text(verbatim: "192.168.1.2"))
                    .hostEntry()
                    .focused($isEditing)
            }
            MobileRunButton(isRunning: model.isRunning, title: L("Interroger"), run: start) {
                model.cancel()
            }
            ToolStatusLine(content: model.status)
                .font(.subheadline)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func start() {
        isEditing = false
        model.start()
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.records.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(row.type)
                            .font(.footnote.monospaced().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            }
                        Text(row.name)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(verbatim: "TTL \(row.ttl)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(row.value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .contextMenu {
                    // Seules les valeurs qui sont des adresses peuvent recevoir un outil réseau.
                    if row.type == "A" || row.type == "AAAA" {
                        HostToolsMenu(address: row.value) { module, target in
                            state.open(module, target: target)
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
                .accessibilityElement(children: .combine)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Comparer les serveurs"))
                .font(.headline)
            if model.comparison.isEmpty {
                Text(L("Pose la même question au résolveur du système, à 1.1.1.1 et à 9.9.9.9."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.comparison) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.server)
                                .font(.body.monospaced())
                            Spacer(minLength: 0)
                            Text(row.time)
                                .font(.body.monospaced())
                        }
                        StatusLabel(kind: row.statusKind, text: row.status)
                        if !row.answer.isEmpty {
                            Text(row.answer)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if model.isComparing {
                ProgressView()
            } else {
                Button(model.comparison.isEmpty ? L("Comparer") : L("Comparer de nouveau")) {
                    isEditing = false
                    model.compareServers()
                }
                .buttonStyle(.bordered)
                .disabled(model.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }
}
