import SwiftUI
import PingouinCore

struct AutomationView: View {
    @Bindable var model: AutomationViewModel
    @State private var pendingRemoval: AutomationTask?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            taskList
                .frame(width: 260)
            VStack(alignment: .leading, spacing: 14) {
                detail
                history
                    .frame(height: 210)
                Text(L("Les tâches planifiées s'exécutent uniquement quand Pingouin est ouvert et que le Mac est éveillé. Une seule tâche tourne à la fois."))
                    .footnoteStyle()
            }
        }
        .toolPage(L("Automatisation"))
        .toolbar {
            ToolbarItem {
                Button(L("Nouvelle tâche")) {
                    model.beginAdding()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if model.isRunning {
                    Button(L("Arrêter"), role: .cancel) {
                        model.cancel()
                    }
                } else {
                    Button(L("Exécuter")) {
                        model.runSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedTask == nil)
                }
            }
        }
        .sheet(isPresented: $model.isEditing) {
            AutomationTaskEditor(model: model)
        }
        .confirmationDialog(
            L("Supprimer la tâche « \(pendingRemoval?.name ?? "") » ?"),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented { pendingRemoval = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Supprimer"), role: .destructive) {
                if let task = pendingRemoval {
                    model.remove(task.id)
                }
                pendingRemoval = nil
            }
            Button(L("Annuler"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(L("L'historique de ses exécutions est conservé."))
        }
    }

    // MARK: Liste des tâches

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Tâches"))
                .font(.headline)
            if model.tasks.isEmpty {
                Text(L("Aucune tâche. Une tâche enchaîne des contrôles (ping, DNS, port, HTTP, certificat) sur les cibles de votre choix."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Nouvelle tâche")) {
                    model.beginAdding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.tasks) { task in
                            taskRow(task)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private func taskRow(_ task: AutomationTask) -> some View {
        let isSelected = task.id == model.selectedTaskID
        let isRunning = task.id == model.runningTaskID
        return Button {
            model.selectedTaskID = task.id
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(L(count: task.steps.count, one: "\(task.steps.count) étape", other: "\(task.steps.count) étapes") + " · " + (task.scheduleSeconds == nil ? L("manuelle") : L("planifiée")))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("Exécuter maintenant")) {
                model.selectedTaskID = task.id
                model.run(task.id, scheduled: false)
            }
            .disabled(model.isRunning)
            Button(L("Modifier…")) {
                model.beginEditing(task.id)
            }
            Button(L("Dupliquer")) {
                model.duplicate(task.id)
            }
            Divider()
            Button(L("Supprimer…"), role: .destructive) {
                pendingRemoval = task
            }
        }
    }

    // MARK: Détail

    @ViewBuilder
    private var detail: some View {
        if let task = model.selectedTask {
            let results = model.results(for: task.id)
            let isRunning = task.id == model.runningTaskID
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.name)
                        .font(.headline)
                    Spacer()
                    Button(L("Modifier…")) {
                        model.beginEditing(task.id)
                    }
                    .disabled(isRunning)
                }
                Text(subtitle(for: task, isRunning: isRunning))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                        ForEach(Array(task.steps.enumerated()), id: \.element.id) { index, step in
                            GridRow {
                                Text(verbatim: String(index + 1))
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(step.kind.title)
                                Text(step.summary)
                                    .font(.body.monospaced())
                                    .lineLimit(1)
                                stepStatus(step, result: results[step.id], isRunning: isRunning)
                                Text(results[step.id]?.milliseconds.map { NumberInput.milliseconds($0) } ?? "—")
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassCard()
        } else {
            ContentUnavailableView(
                L("Aucune tâche sélectionnée"),
                systemImage: "bolt",
                description: Text(L("Créer une tâche, ou en choisir une dans la liste."))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard()
        }
    }

    private func subtitle(for task: AutomationTask, isRunning: Bool) -> String {
        if isRunning { return L("Exécution en cours…") }
        var parts = [task.scheduleLabel]
        if task.stopOnFailure {
            parts.append(L("s'arrête au premier échec"))
        }
        if let lastRun = task.lastRun {
            parts.append(L("dernière exécution le \(lastRun.formatted(date: .abbreviated, time: .shortened))"))
        } else {
            parts.append(L("jamais exécutée"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func stepStatus(_ step: AutomationStep, result: AutomationStepResult?, isRunning: Bool) -> some View {
        if let result {
            StatusLabel(kind: kind(for: result.level), text: result.detail)
        } else if isRunning, model.currentStepID == step.id {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L("En cours…"))
                    .foregroundStyle(.secondary)
            }
        } else if isRunning {
            Text(L("En attente"))
                .foregroundStyle(.secondary)
        } else {
            Text(L("Pas de résultat"))
                .foregroundStyle(.secondary)
        }
    }

    private func kind(for level: CheckResult.Level) -> StatusKind {
        switch level {
        case .ok: return .ok
        case .warning: return .warning
        case .failure: return .failure
        }
    }

    // MARK: Historique

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Exécutions"))
                    .font(.headline)
                Spacer()
                Button(L("Effacer")) {
                    model.clearRuns()
                }
                .buttonStyle(.link)
                .disabled(model.runs.isEmpty)
            }
            if model.runs.isEmpty {
                Text(L("Les exécutions, manuelles ou planifiées, apparaîtront ici."))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                        ForEach(model.runs.prefix(40)) { run in
                            GridRow {
                                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(run.taskName)
                                    .lineLimit(1)
                                StatusLabel(kind: runKind(run), text: runText(run))
                                Text(run.wasScheduled ? L("Planifiée") : L("Manuelle"))
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

    private func runKind(_ run: AutomationRun) -> StatusKind {
        if run.failureCount > 0 { return .failure }
        if run.wasCancelled || run.results.count < run.stepCount { return .warning }
        if run.results.contains(where: { $0.level == .warning }) { return .warning }
        return .ok
    }

    private func runText(_ run: AutomationRun) -> String {
        var text = L(
            count: run.successCount,
            one: "\(run.successCount) étape réussie sur \(run.stepCount)",
            other: "\(run.successCount) étapes réussies sur \(run.stepCount)"
        )
        if run.wasCancelled {
            text += L(", interrompue")
        } else if run.results.count < run.stepCount {
            text += L(", arrêtée au premier échec")
        }
        return text
    }
}
