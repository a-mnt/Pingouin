import SwiftUI
import PingouinCore

/// Fiche du nœud choisi sur le schéma : ses informations, ses liens, et les outils à lancer sur lui.
struct MobileTopologyNodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: TopologyViewModel
    let open: (AppModule, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let node = model.selectedNode {
                    Section {
                        TextField(L("Nom"), text: binding(node, \.name))
                        TextField(L("Adresse IP ou nom d'hôte"), text: binding(node, \.address), prompt: Text(L("Facultatif")))
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Picker(L("Type"), selection: binding(node, \.kind)) {
                            ForEach(TopologyNodeKind.allCases) { kind in
                                Text(MobileTopologyLabels.label(for: kind)).tag(kind)
                            }
                        }
                        TextField(L("Notes"), text: binding(node, \.notes), axis: .vertical)
                            .lineLimit(2...5)
                    } footer: {
                        Text(node.origin == .detected ? L("Trouvé par la découverte LAN") : L("Ajouté à la main"))
                    }

                    Section {
                        if let status = model.statuses[node.id] {
                            StatusLabel(
                                kind: status.isOnline ? .ok : .failure,
                                text: L("\(status.detail) à \(status.date.formatted(date: .omitted, time: .shortened))")
                            )
                        } else {
                            Text(L("Non contrôlé"))
                                .foregroundStyle(.secondary)
                        }
                        if !node.address.isEmpty {
                            Menu(L("Lancer un outil sur ce nœud")) {
                                HostToolsMenu(address: node.address, open: open)
                            }
                        }
                    } header: {
                        Text(L("Statut"))
                    }

                    Section {
                        ForEach(model.selectedLinks, id: \.id) { link in
                            HStack {
                                Text(link.name)
                                Text(link.origin == .detected ? L("constaté") : L("saisi"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    model.removeLink(link.id)
                                } label: {
                                    Label(L("Retirer ce lien"), systemImage: "minus.circle")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Menu(L("Relier à…")) {
                            ForEach(model.linkCandidates) { candidate in
                                Button(candidate.name) {
                                    model.connectSelected(to: candidate.id)
                                }
                            }
                        }
                        .disabled(model.linkCandidates.isEmpty)
                    } header: {
                        Text(L("Liens"))
                    }

                    Section {
                        Button(L("Supprimer ce nœud"), role: .destructive) {
                            model.removeSelected()
                            dismiss()
                        }
                    }
                } else {
                    Text(L("Ce nœud n'existe plus."))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Nœud sélectionné"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fermer")) {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Liaison vers une propriété du nœud choisi : chaque modification est enregistrée.
    private func binding<Value>(_ node: TopologyNode, _ keyPath: WritableKeyPath<TopologyNode, Value>) -> Binding<Value> {
        Binding(
            get: { model.selectedNode?[keyPath: keyPath] ?? node[keyPath: keyPath] },
            set: { newValue in
                model.updateSelected { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}
