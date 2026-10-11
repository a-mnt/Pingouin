import SwiftUI
import PingouinCore

/// Supervision sur iPhone et iPad. Les contrôles ne tournent que lorsque Pingouin est à l'écran :
/// iOS suspend les applications en arrière-plan.
struct MobileMonitoringView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: MonitoringViewModel
    @State private var pendingRemoval: Set<UUID> = []

    var body: some View {
        MobilePage(L("Supervision")) {
            HStack(spacing: 10) {
                StatTile(label: L("Surveillances actives"), value: model.activeCount.formatted())
                StatTile(label: L("En ligne"), value: model.onlineCount.formatted(), tint: model.onlineCount > 0 ? .green : nil)
            }
            HStack(spacing: 10) {
                StatTile(label: L("Dégradé"), value: model.degradedCount.formatted(), tint: model.degradedCount > 0 ? .orange : nil)
                StatTile(label: L("Hors ligne"), value: model.offlineCount.formatted(), tint: model.offlineCount > 0 ? .red : nil)
            }
            if model.rows.isEmpty {
                MobileEmptyNote(text: L("Ajouter un hôte ou un service à contrôler à intervalles réguliers."))
            } else {
                Picker(L("Période de disponibilité"), selection: $model.period) {
                    ForEach(MonitorPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                ForEach(model.rows) { row in
                    tile(row)
                }
            }
            events
            limits
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleAllPaused()
                } label: {
                    Label(model.allPaused ? L("Tout reprendre") : L("Tout mettre en pause"), systemImage: model.allPaused ? "play" : "pause")
                }
                .disabled(model.monitors.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.beginAdding()
                } label: {
                    Label(L("Ajouter une surveillance"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $model.isEditing) {
            MobileMonitorEditor(model: model)
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
                    StatusLabel(kind: row.statusKind, text: row.statusText)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(row.availability)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(row.availabilityFraction.map(availabilityColor) ?? Color.secondary)
                    Text(L("dispo."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("Disponibilité \(row.availability)"))
            }
            recentStrip(row)
            HStack(spacing: 0) {
                fact(L("Test"), "\(row.test) · \(row.every)")
                Spacer(minLength: 8)
                fact(L("Temps"), row.time)
                Spacer(minLength: 8)
                fact(L("Dernier contrôle"), row.lastCheck)
                Spacer(minLength: 8)
                Menu {
                    rowMenu(row.id)
                } label: {
                    Label(L("Actions pour \(row.name)"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
            }
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .opacity(row.isPaused ? 0.6 : 1)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: glassTint(for: row.statusKind))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contextMenu {
            rowMenu(row.id)
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private func availabilityColor(_ fraction: Double) -> Color {
        if fraction >= 0.99 { return .green }
        if fraction >= 0.95 { return .orange }
        return .red
    }

    /// Le vert reste discret : l'état normal ne doit pas attirer l'œil, les alertes si.
    private func glassTint(for kind: StatusKind) -> Color {
        switch kind {
        case .ok: Color.green.opacity(0.05)
        case .warning: Color.orange.opacity(0.26)
        case .failure: Color.red.opacity(0.26)
        case .neutral: Color.gray.opacity(0.10)
        }
    }

    @ViewBuilder
    private func rowMenu(_ id: UUID) -> some View {
        if let monitor = model.monitor(id: id) {
            Button(L("Contrôler maintenant")) {
                model.checkNow(ids: [id])
            }
            Button(monitor.isPaused ? L("Reprendre") : L("Mettre en pause")) {
                model.setPaused(!monitor.isPaused, ids: [id])
            }
            if monitor.kind != .http {
                Divider()
                HostToolsMenu(address: monitor.target) { module, target in
                    state.open(module, target: target)
                }
            }
            Divider()
            Button(L("Supprimer…"), role: .destructive) {
                pendingRemoval = [id]
            }
        }
    }

    // MARK: Événements et limites

    private var events: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Événements"))
                    .font(.headline)
                Spacer()
                Button(L("Effacer")) {
                    model.clearEvents()
                }
                .disabled(model.events.isEmpty)
            }
            if model.events.isEmpty {
                Text(L("Les pannes, les retours en ligne et les reprises après une interruption apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.events.prefix(30)) { event in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            StatusLabel(kind: kind(for: event.level), text: event.monitorName)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(event.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Ce que la supervision ne fait pas"))
                .font(.headline)
            Text(L("Elle tourne uniquement quand Pingouin est à l'écran. Dès que l'application passe en arrière-plan ou que l'appareil se verrouille, iOS la suspend : aucune mesure n'est prise, et ces périodes ne comptent ni comme disponibles ni comme en panne. Pour une surveillance continue, utiliser la version Mac."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Toggle(L("Notifications"), isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.setNotifications($0) }
            ))
            if let message = model.notificationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .glassCardPadded(cornerRadius: 22)
    }

    private func kind(for level: CheckResult.Level) -> StatusKind {
        switch level {
        case .ok: .ok
        case .warning: .warning
        case .failure: .failure
        }
    }
}

/// Feuille de création d'une surveillance.
struct MobileMonitorEditor: View {
    @Bindable var model: MonitoringViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("Type de contrôle"), selection: $model.draft.kind) {
                        ForEach(MonitorCheckKind.allCases) { kind in
                            Text(MonitoringViewModel.kindLabel(kind)).tag(kind)
                        }
                    }
                    TextField(targetLabel, text: $model.draft.target, prompt: Text(verbatim: targetPrompt))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if model.draft.kind == .tcp {
                        TextField(L("Port"), text: $model.draft.portText)
                            .keyboardType(.numberPad)
                    }
                    TextField(L("Nom affiché"), text: $model.draft.name, prompt: Text(L("Facultatif")))
                }
                Section {
                    Picker(L("Contrôler toutes les"), selection: $model.draft.intervalSeconds) {
                        ForEach(MonitorDraft.intervals, id: \.seconds) { interval in
                            Text(interval.label).tag(interval.seconds)
                        }
                    }
                    Stepper(
                        L(
                            count: model.draft.failuresBeforeOffline,
                            one: "Hors ligne après \(model.draft.failuresBeforeOffline) échec de suite",
                            other: "Hors ligne après \(model.draft.failuresBeforeOffline) échecs de suite"
                        ),
                        value: $model.draft.failuresBeforeOffline,
                        in: 1...10
                    )
                    TextField(L("Dégradé au-delà de (ms)"), text: $model.draft.degradedText, prompt: Text(L("Facultatif")))
                        .keyboardType(.decimalPad)
                }
                if let error = model.draftError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L("Nouvelle surveillance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) {
                        model.isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Ajouter")) {
                        model.commitDraft()
                    }
                }
            }
        }
    }

    private var targetLabel: String {
        switch model.draft.kind {
        case .ping, .tcp: L("Hôte")
        case .http: "URL"
        case .dns: L("Nom de domaine")
        }
    }

    private var targetPrompt: String {
        switch model.draft.kind {
        case .ping, .tcp: "192.168.1.1"
        case .http: "https://example.com/"
        case .dns: "example.com"
        }
    }
}
