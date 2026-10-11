import SwiftUI
import PingouinCore

/// Automatisation sur iPhone et iPad : des suites de contrôles, lancées d'un geste. Une tâche planifiée
/// ne s'exécute que lorsque Pingouin est à l'écran.
struct MobileAutomationView: View {
    @Bindable var model: AutomationViewModel
    @State private var pendingRemoval: AutomationTask?

    var body: some View {
        MobilePage(L("Automatisation")) {
            if model.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Aucune tâche. Une tâche enchaîne des contrôles (ping, DNS, port, HTTP, certificat) sur les cibles de votre choix."))
                        .foregroundStyle(.secondary)
                    Button(L("Nouvelle tâche")) {
                        model.beginAdding()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .glassCardPadded(cornerRadius: 22)
            } else {
                ForEach(model.tasks) { task in
                    taskCard(task)
                }
            }
            history
            MobileFootnote(text: L("Les tâches planifiées s'exécutent uniquement quand Pingouin est à l'écran : iOS suspend les applications en arrière-plan. Une seule tâche tourne à la fois."))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.beginAdding()
                } label: {
                    Label(L("Nouvelle tâche"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $model.isEditing) {
            MobileAutomationTaskEditor(model: model)
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

    // MARK: Tâche

    private func taskCard(_ task: AutomationTask) -> some View {
        let results = model.results(for: task.id)
        let isRunning = task.id == model.runningTaskID
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(task.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    Button(L("Modifier…")) {
                        model.beginEditing(task.id)
                    }
                    .disabled(isRunning)
                    Button(L("Dupliquer")) {
                        model.duplicate(task.id)
                    }
                    Divider()
                    Button(L("Supprimer…"), role: .destructive) {
                        pendingRemoval = task
                    }
                } label: {
                    Label(L("Actions pour \(task.name)"), systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                }
            }
            Text(subtitle(for: task, isRunning: isRunning))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(task.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text(verbatim: String(index + 1))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.kind.title + " · " + step.summary)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        stepStatus(step, result: results[step.id], isRunning: isRunning)
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    Text(results[step.id]?.milliseconds.map { NumberInput.milliseconds($0) } ?? "")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if isRunning {
                Button(role: .cancel) {
                    model.cancel()
                } label: {
                    Text(L("Arrêter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.selectedTaskID = task.id
                    model.run(task.id, scheduled: false)
                } label: {
                    Text(L("Exécuter"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRunning)
            }
        }
        .glassCardPadded(cornerRadius: 22)
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
        case .ok: .ok
        case .warning: .warning
        case .failure: .failure
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
                .disabled(model.runs.isEmpty)
            }
            if model.runs.isEmpty {
                Text(L("Les exécutions, manuelles ou planifiées, apparaîtront ici."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.runs.prefix(20)) { run in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(run.taskName)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        StatusLabel(kind: runKind(run), text: runText(run))
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCardPadded(cornerRadius: 22)
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
        return text + " · " + (run.wasScheduled ? L("Planifiée") : L("Manuelle"))
    }
}

/// Feuille de création ou de modification d'une tâche.
struct MobileAutomationTaskEditor: View {
    @Bindable var model: AutomationViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Nom"), text: $model.draft.name, prompt: Text(L("Contrôle du matin")))
                    Picker(L("Exécution"), selection: $model.draft.scheduleSeconds) {
                        ForEach(AutomationTask.schedules, id: \.label) { schedule in
                            Text(schedule.label).tag(schedule.seconds)
                        }
                    }
                    Toggle(L("Arrêter la tâche au premier échec"), isOn: $model.draft.stopOnFailure)
                }
                ForEach($model.draft.steps) { $step in
                    Section {
                        stepFields($step)
                    }
                }
                Section {
                    Button(L("Ajouter une étape")) {
                        model.addDraftStep()
                    }
                    .disabled(model.draft.steps.count >= AutomationViewModel.stepLimit)
                }
                if let error = model.draftError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(model.isEditingExisting ? L("Modifier la tâche") : L("Nouvelle tâche"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) {
                        model.isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isEditingExisting ? L("Enregistrer") : L("Créer")) {
                        model.commitDraft()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepFields(_ step: Binding<AutomationStep>) -> some View {
        let id = step.wrappedValue.id
        Picker(L("Type d'étape"), selection: step.kind) {
            ForEach(AutomationStepKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        TextField(L("Cible"), text: step.target, prompt: Text(verbatim: step.wrappedValue.kind.targetPrompt))
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        if step.wrappedValue.kind == .tcp {
            TextField(L("Port"), text: step.portText, prompt: Text(L("Port")))
                .font(.body.monospaced())
                .keyboardType(.numberPad)
        }
        HStack(spacing: 18) {
            Button {
                model.moveDraftStep(id, by: -1)
            } label: {
                Label(L("Monter l'étape"), systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            Button {
                model.moveDraftStep(id, by: 1)
            } label: {
                Label(L("Descendre l'étape"), systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            Spacer()
            Button(role: .destructive) {
                model.removeDraftStep(id)
            } label: {
                Label(L("Retirer l'étape"), systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
        }
        // Dans une ligne de formulaire, un appui déclencherait tous les boutons sans ce style.
        .buttonStyle(.borderless)
    }
}
