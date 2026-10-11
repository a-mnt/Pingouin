import SwiftUI
import PingouinCore

/// Feuille de création ou de modification d'une tâche.
struct AutomationTaskEditor: View {
    @Bindable var model: AutomationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.isEditingExisting ? L("Modifier la tâche") : L("Nouvelle tâche"))
                .font(.title3.weight(.bold))

            Form {
                TextField(L("Nom"), text: $model.draft.name, prompt: Text(L("Contrôle du matin")))
                Picker(L("Exécution"), selection: $model.draft.scheduleSeconds) {
                    ForEach(AutomationTask.schedules, id: \.label) { schedule in
                        Text(schedule.label).tag(schedule.seconds)
                    }
                }
                Toggle(L("Arrêter la tâche au premier échec"), isOn: $model.draft.stopOnFailure)
            }
            .formStyle(.grouped)
            .frame(height: 170)

            Text(L("Étapes"))
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($model.draft.steps) { $step in
                        stepRow($step)
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 260)

            Button(L("Ajouter une étape")) {
                model.addDraftStep()
            }
            .disabled(model.draft.steps.count >= AutomationViewModel.stepLimit)

            if let error = model.draftError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(L("Annuler"), role: .cancel) {
                    model.isEditing = false
                }
                .keyboardShortcut(.cancelAction)
                Button(model.isEditingExisting ? L("Enregistrer") : L("Créer")) {
                    model.commitDraft()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private func stepRow(_ step: Binding<AutomationStep>) -> some View {
        let id = step.wrappedValue.id
        return HStack(spacing: 8) {
            Picker(L("Type d'étape"), selection: step.kind) {
                ForEach(AutomationStepKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 140)
            TextField(L("Cible"), text: step.target, prompt: Text(step.wrappedValue.kind.targetPrompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .autocorrectionDisabled()
            if step.wrappedValue.kind == .tcp {
                TextField(L("Port"), text: step.portText, prompt: Text(L("Port")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 70)
            }
            Button {
                model.moveDraftStep(id, by: -1)
            } label: {
                Label(L("Monter l'étape"), systemImage: "chevron.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            Button {
                model.moveDraftStep(id, by: 1)
            } label: {
                Label(L("Descendre l'étape"), systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            Button {
                model.removeDraftStep(id)
            } label: {
                Label(L("Retirer l'étape"), systemImage: "minus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }
}
