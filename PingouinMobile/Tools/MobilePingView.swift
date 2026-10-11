import Charts
import SwiftUI
import PingouinCore

/// Ping sur iPhone et iPad : la saisie, la synthèse, le graphique, puis les réponses, en une colonne.
struct MobilePingView: View {
    @Bindable var model: PingViewModel
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                parameters
                tiles
                if model.hasResults {
                    chart
                    replies
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PingouinBackdrop() }
        .navigationTitle(L("Ping"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Pasteboard.copy(model.resultsAsText)
                } label: {
                    Label(L("Copier les résultats"), systemImage: "doc.on.doc")
                }
                .disabled(!model.hasResults)
            }
        }
    }

    // MARK: Saisie

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledField(L("Hôte (adresse IP ou nom DNS)")) {
                TextField(L("Hôte"), text: $model.host, prompt: Text(verbatim: "192.168.1.1"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
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
                LabeledField(L("Tentatives")) {
                    TextField(L("Tentatives"), text: $model.countText)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .keyboardType(.numberPad)
                        .focused($isEditing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.isRunning)

            if model.isRunning {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text(L("Arrêter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(action: start) {
                    Text(L("Lancer"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            ToolStatusLine(content: model.status)
                .font(.subheadline)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    /// Adresse qui a répondu, telle que le nom saisi a été résolu ; à défaut, la saisie.
    private var answeringAddress: String {
        model.rows.first { $0.statusKind == .ok }?.address ?? model.host
    }

    private func start() {
        isEditing = false
        model.start()
    }

    // MARK: Synthèse

    private var tiles: some View {
        let stats = model.statistics
        return HStack(spacing: 10) {
            StatTile(label: L("Reçus"), value: "\(stats.received)")
            StatTile(
                label: L("Perte"),
                value: stats.sent == 0 ? "—" : (stats.lossPercent / 100).formatted(.percent.precision(.fractionLength(0...1))),
                tint: stats.lost > 0 ? .orange : nil
            )
            StatTile(label: L("Moyenne"), value: stats.average.map { NumberInput.milliseconds($0) } ?? "—")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Temps de réponse par tentative"))
                .font(.headline)
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
            .chartYAxisLabel("ms")
            .frame(height: 130)
            .accessibilityLabel(L("Temps de réponse par tentative"))
            Text(L("Barre : réponse · Trait pointillé orange : sans réponse"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .glassCardPadded(cornerRadius: 22)
    }

    // MARK: Réponses

    /// Les réponses, la plus récente en premier. Les cent dernières suffisent à l'écran ;
    /// « Copier les résultats » donne la série entière.
    private var replies: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows.prefix(100)) { row in
                HStack(spacing: 12) {
                    Text(verbatim: String(row.id))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                    StatusLabel(kind: row.statusKind, text: row.status)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(row.timeText)
                        .font(.body.monospaced())
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                Divider()
            }
            Text(model.rows.count > 100
                ? L("Les 100 dernières réponses sur \(model.rows.count).")
                : L("Adresse interrogée : \(answeringAddress)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .glassCardPadded(cornerRadius: 22)
    }
}
