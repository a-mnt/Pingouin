import Charts
import PingouinCore
import SwiftUI

struct PingView: View {
    @Bindable var model: PingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            parameters
            tiles
            chart
            HStack(alignment: .top, spacing: 14) {
                replies
                HistoryCard(entries: model.history) { entry in
                    model.launch(host: entry.target)
                }
                .frame(width: 300)
            }
        }
        .toolPage(L("Ping"))
        .toolbar {
            CopyToolbarItem(title: L("Copier les résultats"), isDisabled: !model.hasResults) {
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
                LabeledField(L("Hôte (adresse IP ou nom DNS)")) {
                    TextField(L("Hôte"), text: $model.host, prompt: Text("192.168.1.1"))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit { model.start() }
                }
                .frame(minWidth: 220)
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
                LabeledField(L("Tentatives")) {
                    TextField(L("Tentatives"), text: $model.countText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 90)
                LabeledField(L("Intervalle (s)")) {
                    TextField(L("Intervalle"), text: $model.intervalText)
                        .labelsHidden()
                        .font(.body.monospaced())
                }
                .frame(width: 100)
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

    private var tiles: some View {
        let stats = model.statistics
        return HStack(spacing: 10) {
            StatTile(label: L("Envoyés"), value: stats.sent.formatted())
            StatTile(label: L("Reçus"), value: stats.received.formatted())
            StatTile(
                label: L("Perte"),
                value: stats.sent == 0 ? "—" : (stats.lossPercent / 100).formatted(.percent.precision(.fractionLength(0...1))),
                tint: stats.lost > 0 ? .orange : nil
            )
            StatTile(label: L("Minimum"), value: stats.minimum.map { NumberInput.milliseconds($0) } ?? "—")
            StatTile(label: L("Moyenne"), value: stats.average.map { NumberInput.milliseconds($0) } ?? "—")
            StatTile(label: L("Maximum"), value: stats.maximum.map { NumberInput.milliseconds($0) } ?? "—")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Temps de réponse par tentative"))
                    .font(.headline)
                Spacer()
                Text(L("Barre : réponse · Trait pointillé orange : sans réponse"))
                    .foregroundStyle(.secondary)
            }
            // Chaque barre est un rectangle aux bornes explicites : sur un axe numérique,
            // une barre « automatique » n'a pas de largeur et reste invisible.
            Chart(model.bars) { bar in
                if let milliseconds = bar.milliseconds {
                    RectangleMark(
                        xStart: .value(L("Début"), Double(bar.id) - 0.35),
                        xEnd: .value(L("Fin"), Double(bar.id) + 0.35),
                        yStart: .value(L("Base"), 0.0),
                        yEnd: .value(L("Temps (ms)"), milliseconds)
                    )
                    .foregroundStyle(Color.primary.opacity(0.85))
                } else {
                    RuleMark(x: .value(L("Tentative"), Double(bar.id)))
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .chartXScale(domain: 0.5...(Double(model.plannedCount) + 0.5))
            .chartXAxisLabel(L("Tentative"))
            .chartYAxisLabel("ms")
            .frame(height: 130)
        }
        .glassCardPadded()
    }

    private var replies: some View {
        Table(model.rows, sortOrder: $model.sortOrder) {
            TableColumn(L("N°"), value: \.id) { row in
                Text(String(row.id))
                    .font(.body.monospaced())
            }
            .width(min: 40, ideal: 50, max: 70)
            TableColumn(L("Heure"), value: \.time) { row in
                Text(row.time)
                    .font(.body.monospaced())
            }
            TableColumn(L("Adresse"), value: \.address) { row in
                Text(row.address)
                    .font(.body.monospaced())
            }
            TableColumn("TTL", value: \.ttl) { row in
                Text(row.ttl)
                    .font(.body.monospaced())
            }
            .width(min: 40, ideal: 50, max: 70)
            TableColumn(L("Temps"), value: \.timeSortKey) { row in
                Text(row.timeText)
                    .font(.body.monospaced())
            }
            TableColumn(L("État"), value: \.status) { row in
                StatusLabel(kind: row.statusKind, text: row.status)
            }
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if model.rows.isEmpty, !model.isRunning {
                ContentUnavailableView(
                    L("Aucune réponse"),
                    systemImage: "waveform.path.ecg",
                    description: Text(L("Les réponses apparaîtront ici au fil du ping."))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}
