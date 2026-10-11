import PingouinCore
import SwiftUI

/// Feuille de création d'une surveillance.
struct MonitorEditor: View {
    @Bindable var model: MonitoringViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Nouvelle surveillance"))
                .font(.title3.weight(.bold))

            Form {
                Picker(L("Type de contrôle"), selection: $model.draft.kind) {
                    ForEach(MonitorCheckKind.allCases) { kind in
                        Text(MonitoringViewModel.kindLabel(kind)).tag(kind)
                    }
                }
                TextField(targetLabel, text: $model.draft.target, prompt: Text(targetPrompt))
                    .autocorrectionDisabled()
                if model.draft.kind == .tcp {
                    TextField(L("Port"), text: $model.draft.portText)
                }
                TextField(L("Nom affiché"), text: $model.draft.name, prompt: Text(L("Facultatif")))
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
            }
            .formStyle(.grouped)

            if let error = model.draftError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(L("Annuler"), role: .cancel) {
                    model.isEditing = false
                }
                .keyboardShortcut(.cancelAction)
                Button(L("Ajouter")) {
                    model.commitDraft()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
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
