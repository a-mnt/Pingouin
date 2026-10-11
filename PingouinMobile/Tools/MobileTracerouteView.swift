import SwiftUI
import PingouinCore

/// Traceroute sur iPhone et iPad : la saisie, la synthèse, puis un saut par ligne.
struct MobileTracerouteView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: TracerouteViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        MobilePage(L("Traceroute")) {
            parameters
            HStack(spacing: 10) {
                StatTile(label: L("Sauts"), value: model.hopCount.formatted())
                StatTile(
                    label: L("Sans réponse"),
                    value: model.silentHopCount.formatted(),
                    tint: model.silentHopCount > 0 ? .orange : nil
                )
                StatTile(label: L("Temps au dernier saut"), value: model.lastHopTimeText)
            }
            if model.rows.isEmpty {
                if !model.isRunning {
                    MobileEmptyNote(text: L("Les sauts apparaîtront ici au fil du traceroute."))
                }
            } else {
                hops
            }
            MobileFootnote(text: L("Un saut sans réponse n'est pas forcément une panne : beaucoup de routeurs ignorent ces sondes tout en acheminant le trafic. Appui long sur un saut pour lancer un outil sur cet équipement."))
        }
        .toolbar {
            MobileCopyItem(title: L("Copier les résultats"), isDisabled: model.hopCount == 0) {
                model.resultsAsText
            }
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(L("Destination (adresse IP ou nom DNS)")) {
                TextField(L("Destination"), text: $model.host, prompt: Text(verbatim: "example.com"))
                    .hostEntry()
                    .submitLabel(.go)
                    .focused($isEditing)
                    .onSubmit(start)
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(L("Protocole")) {
                    Picker(L("Protocole"), selection: $model.family) {
                        Text(L("Automatique")).tag(IPFamilyChoice.automatic)
                        Text(verbatim: "IPv4").tag(IPFamilyChoice.ipv4)
                        Text(verbatim: "IPv6").tag(IPFamilyChoice.ipv6)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LabeledField(L("Sauts maximum")) {
                    TextField(L("Sauts maximum"), text: $model.maximumHopsText)
                        .numberEntry()
                        .focused($isEditing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 12) {
                LabeledField(L("Sondes par saut")) {
                    TextField(L("Sondes par saut"), text: $model.probesText)
                        .numberEntry()
                        .focused($isEditing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LabeledField(L("Délai (ms)")) {
                    TextField(L("Délai"), text: $model.timeoutText)
                        .numberEntry()
                        .focused($isEditing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MobileRunButton(isRunning: model.isRunning, title: L("Lancer"), run: start) {
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

    private var hops: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider()
                }
                hop(row)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func hop(_ row: HopRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(row.id))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                if row.answered {
                    Text(row.address)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !row.name.isEmpty {
                        Text(row.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: row.fraction)
                        .accessibilityLabel(L("Temps moyen relatif"))
                } else {
                    StatusLabel(kind: .warning, text: L("Aucune réponse"))
                }
                Text(row.probes)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(row.averageText)
                .font(.body.monospaced())
                .fontWeight(.semibold)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if row.answered {
                HostToolsMenu(address: row.address) { module, target in
                    state.open(module, target: target)
                }
                Divider()
                Button(L("Copier l'adresse")) {
                    Pasteboard.copy(row.address)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
