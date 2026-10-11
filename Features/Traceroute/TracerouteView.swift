import PingouinCore
import SwiftUI

struct TracerouteView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: TracerouteViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
            hops
            Text(L("Un saut sans réponse n'est pas forcément une panne : beaucoup de routeurs ignorent ces sondes tout en acheminant le trafic. Clic droit sur un saut pour lancer un outil sur cet équipement."))
                .footnoteStyle()
        }
        .toolPage(L("Traceroute"))
        .toolbar {
            CopyToolbarItem(title: L("Copier les résultats"), isDisabled: model.hopCount == 0) {
                model.resultsAsText
            }
            RunToolbarItem(
                isRunning: model.isRunning,
                title: L("Lancer"),
                run: { model.start() },
                stop: { model.cancel() }
            )
        }
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                LabeledField(L("Destination (adresse IP ou nom DNS)")) {
                    TextField(L("Destination"), text: $model.host, prompt: Text("example.com"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.start() }
                }
                .frame(minWidth: 240)
                LabeledField(L("Protocole")) {
                    Picker(L("Protocole"), selection: $model.family) {
                        Text(L("Automatique")).tag(IPFamilyChoice.automatic)
                        Text(L("IPv4")).tag(IPFamilyChoice.ipv4)
                        Text(L("IPv6")).tag(IPFamilyChoice.ipv6)
                    }
                    .labelsHidden()
                    .help(L("Automatique : l'adresse saisie décide ; pour un nom, l'IPv4 d'abord, l'IPv6 à défaut"))
                }
                .frame(width: 130)
                LabeledField(L("Sauts maximum")) {
                    TextField(L("Sauts maximum"), text: $model.maximumHopsText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 110)
                LabeledField(L("Sondes par saut")) {
                    TextField(L("Sondes par saut"), text: $model.probesText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 110)
                LabeledField(L("Délai (ms)")) {
                    TextField(L("Délai"), text: $model.timeoutText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 90)
            }
            .disabled(model.isRunning)

            ToolStatusLine(content: model.status)
        }
        .glassCardPadded()
    }

    private var hops: some View {
        Table(model.rows, selection: $model.selection) {
            TableColumn(L("Saut")) { row in
                Text(String(row.id))
                    .font(.body.monospaced())
            }
            .width(min: 40, ideal: 50, max: 60)
            TableColumn(L("Adresse")) { row in
                if row.answered {
                    Text(row.address)
                        .font(.body.monospaced())
                } else {
                    StatusLabel(kind: .warning, text: L("Aucune réponse"))
                }
            }
            TableColumn(L("Nom")) { row in
                Text(row.name.isEmpty ? "—" : row.name)
                    .foregroundStyle(row.name.isEmpty ? .secondary : .primary)
            }
            TableColumn(L("Sondes (ms)")) { row in
                Text(row.probes)
                    .font(.body.monospaced())
            }
            TableColumn(L("Moyenne")) { row in
                Text(row.averageText)
                    .font(.body.monospaced())
                    .fontWeight(.semibold)
            }
            TableColumn(L("Progression")) { row in
                if row.answered {
                    ProgressView(value: row.fraction)
                        .accessibilityLabel(L("Temps moyen relatif"))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: Int.self) { ids in
            rowMenu(ids)
        }
        .overlay {
            if model.rows.isEmpty, !model.isRunning {
                ContentUnavailableView(
                    L("Aucun saut"),
                    systemImage: "arrow.triangle.turn.up.right.diamond",
                    description: Text(L("Les sauts apparaîtront ici au fil du traceroute."))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<Int>) -> some View {
        if ids.count == 1, let id = ids.first, let row = model.row(id: id), row.answered {
            HostToolsMenu(address: row.address) { module, target in
                app.open(module, target: target)
            }
            Divider()
            Button(L("Copier l'adresse")) {
                Pasteboard.copy(row.address)
            }
        }
    }
}
