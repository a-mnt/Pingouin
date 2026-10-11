import PingouinCore
import SwiftUI

struct MonitoringView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: MonitoringViewModel
    @State private var pendingRemoval: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatTile(label: L("Surveillances actives"), value: model.activeCount.formatted())
                StatTile(label: L("En ligne"), value: model.onlineCount.formatted(), tint: model.onlineCount > 0 ? .green : nil)
                StatTile(label: L("Dégradé"), value: model.degradedCount.formatted(), tint: model.degradedCount > 0 ? .orange : nil)
                StatTile(label: L("Hors ligne"), value: model.offlineCount.formatted(), tint: model.offlineCount > 0 ? .red : nil)
            }
            monitors
            HStack(alignment: .top, spacing: 14) {
                events
                limits
                    .frame(width: 320)
            }
            .frame(height: 220)
        }
        .toolPage(L("Supervision"))
        .toolbar {
            ToolbarItem {
                Button(model.allPaused ? L("Tout reprendre") : L("Tout mettre en pause")) {
                    model.toggleAllPaused()
                }
                .disabled(model.monitors.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("Ajouter une surveillance")) {
                    model.beginAdding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $model.isEditing) {
            MonitorEditor(model: model)
        }
        .confirmationDialog(
            L(
                count: pendingRemoval.count,
                one: "Supprimer \(pendingRemoval.count) surveillance ?",
                other: "Supprimer \(pendingRemoval.count) surveillances ?"
            ),
            isPresented: Binding(
                get: { !pendingRemoval.isEmpty },
                set: { isPresented in
                    if !isPresented { pendingRemoval = [] }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                model.remove(ids: pendingRemoval)
                pendingRemoval = []
            }
            Button(L("Annuler"), role: .cancel) {
                pendingRemoval = []
            }
        } message: {
            Text(L("L'historique de mesures correspondant sera effacé."))
        }
    }

    private var monitors: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Hôtes et services"))
                    .font(.headline)
                Spacer()
                Picker(L("Période de disponibilité"), selection: $model.period) {
                    ForEach(MonitorPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Les tuiles sont posées directement sur le fond de la fenêtre : chacune est un panneau
            // de verre, et du verre posé sur un autre panneau de verre perdrait son effet.
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 270, maximum: 380), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(model.rows) { row in
                        tile(row)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(
                        L("Aucune surveillance"),
                        systemImage: "eye",
                        description: Text(L("Ajouter un hôte ou un service à contrôler à intervalles réguliers."))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tuile

    private func tile(_ row: MonitorRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(row.target)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // L'état dans une pastille en capsule, teintée comme le verre de la tuile.
                    StatusLabel(kind: row.statusKind, text: row.statusText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(row.statusKind).opacity(0.16), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                        }
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                availabilityRing(row)
            }

            recentStrip(row)

            HStack(spacing: 0) {
                tileFact(L("Test"), "\(row.test) · \(row.every)")
                Spacer(minLength: 8)
                tileFact(L("Temps"), row.time)
                Spacer(minLength: 8)
                tileFact(L("Dernier contrôle"), row.lastCheck)
                Spacer(minLength: 8)
                Menu {
                    rowMenu([row.id])
                } label: {
                    Label(L("Actions pour \(row.name)"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.isPaused ? 0.6 : 1)
        // Verre teinté selon l'état, qui réagit au pointeur, sur un halo de la même couleur.
        // Le vert reste discret : l'état normal ne doit pas attirer l'œil, les alertes si.
        .glassTile(
            tint: glassTint(for: row.statusKind),
            halo: statusColor(row.statusKind),
            haloStrength: row.statusKind == .ok ? 0.3 : 1
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contextMenu {
            rowMenu([row.id])
        }
        .accessibilityElement(children: .combine)
    }

    /// Anneau de disponibilité : la part remplie est la part des contrôles réussis sur la période.
    private func availabilityRing(_ row: MonitorRow) -> some View {
        let fraction = row.availabilityFraction
        return ZStack {
            // Piste claire et translucide, comme gravée dans le verre.
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 8)
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 8)
            if let fraction {
                let color = availabilityColor(fraction)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.004))
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.004))),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.55), radius: 6)
            }
            VStack(spacing: 0) {
                Text(row.availability)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(L("dispo."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
        }
        .frame(width: 82, height: 82)
        .help(L("Disponibilité sur la période : \(row.availability)"))
        .accessibilityLabel(L("Disponibilité \(row.availability)"))
    }

    /// Derniers contrôles, un trait par contrôle : haut et vert s'il a réussi, bas et rouge s'il a échoué.
    private func recentStrip(_ row: MonitorRow) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(row.recentResults.enumerated()), id: \.offset) { _, success in
                Capsule()
                    .fill(success ? Color.green.opacity(0.85) : Color.red.opacity(0.9))
                    .frame(width: 4, height: success ? 16 : 7)
            }
            if row.recentResults.isEmpty {
                Text(L("Aucun contrôle pour l'instant"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 16, alignment: .bottomLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        }
        .help(L("Les \(MonitoringViewModel.recentResultCount) derniers contrôles, du plus ancien au plus récent"))
        .accessibilityHidden(true)
    }

    private func tileFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
        }
    }

    private func availabilityColor(_ fraction: Double) -> Color {
        if fraction >= 0.99 { return .green }
        if fraction >= 0.95 { return .orange }
        return .red
    }

    private func glassTint(for kind: StatusKind) -> Color {
        switch kind {
        case .ok: return Color.green.opacity(0.05)
        case .warning: return Color.orange.opacity(0.26)
        case .failure: return Color.red.opacity(0.26)
        case .neutral: return Color.gray.opacity(0.10)
        }
    }

    private func statusColor(_ kind: StatusKind) -> Color {
        switch kind {
        case .ok: return .green
        case .warning: return .orange
        case .failure: return .red
        case .neutral: return .gray
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Événements"))
                    .font(.headline)
                Spacer()
                Button(L("Effacer")) {
                    model.clearEvents()
                }
                .buttonStyle(.link)
                .disabled(model.events.isEmpty)
            }
            if model.events.isEmpty {
                Text(L("Les pannes, les retours en ligne et les reprises après veille apparaîtront ici."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.events.prefix(60)) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                StatusLabel(kind: kind(for: event.level), text: event.monitorName)
                                Text(event.text)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ce que la supervision ne fait pas"))
                .font(.headline)
            Text(L("Elle tourne uniquement quand Pingouin est ouvert et que le Mac est éveillé. Pendant la veille, après la fermeture de l'app ou un redémarrage, aucune mesure n'est prise : ces périodes ne comptent ni comme disponibles ni comme en panne."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L("Notifications macOS"), isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.setNotifications($0) }
            ))
            if let message = model.notificationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private func kind(for level: CheckResult.Level) -> StatusKind {
        switch level {
        case .ok: return .ok
        case .warning: return .warning
        case .failure: return .failure
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            let selected = ids.compactMap { model.monitor(id: $0) }
            let allPaused = selected.allSatisfy(\.isPaused)
            Button(L("Contrôler maintenant")) {
                model.checkNow(ids: ids)
            }
            Button(allPaused ? L("Reprendre") : L("Mettre en pause")) {
                model.setPaused(!allPaused, ids: ids)
            }
            if selected.count == 1, let monitor = selected.first, monitor.kind != .http {
                Divider()
                HostToolsMenu(address: monitor.target) { module, target in
                    app.open(module, target: target)
                }
            }
            Divider()
            Button(L("Supprimer…"), role: .destructive) {
                pendingRemoval = ids
            }
        }
    }
}
