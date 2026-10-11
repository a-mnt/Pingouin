import AppKit
import PingouinCore
import SwiftUI
import UniformTypeIdentifiers

struct TopologyView: View {
    @Environment(AppState.self) private var app
    @Bindable var model: TopologyViewModel
    @State private var isOfferingDiscovery = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                legend
                schema
                if let message = model.message {
                    Text(message)
                        .footnoteStyle()
                }
                Text(L("Pingouin ne trace que les relations que vous avez saisies ou qu'il a constatées. Un trait plein vers la box signifie qu'elle voit l'appareil, pas qu'il y est branché directement : un switch ou une borne Wi-Fi peut se trouver entre les deux."))
                    .footnoteStyle()
            }
            inspector
                .frame(width: 290)
        }
        .toolPage(L("Topologie"))
        .toolbar {
            ToolbarItem {
                Button(L("Importer la découverte LAN")) {
                    let hosts = app.lanDiscovery.discoveredHosts
                    if hosts.isEmpty {
                        isOfferingDiscovery = true
                    } else {
                        model.importDiscovered(hosts, attachments: app.usage.observedAttachments, boxName: app.usage.boxName)
                    }
                }
                .help(L("Ajouter au schéma les hôtes trouvés par la dernière découverte LAN"))
            }
            ToolbarItem {
                Button(L("Détecter les liens")) {
                    model.linkObserved(app.usage.observedAttachments, boxName: app.usage.boxName)
                }
                .help(L("Relier à la box les nœuds qu'elle voit sur ses ports et son Wi-Fi (d'après le dernier relevé de Consommation)"))
            }
            ToolbarItem {
                Button(model.isRefreshing ? L("Contrôle en cours…") : L("Actualiser les statuts")) {
                    model.refreshStatuses()
                }
                .disabled(model.isRefreshing)
            }
            ToolbarItem {
                Button(L("Exporter…")) {
                    export()
                }
                .disabled(model.topology.nodes.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L("Ajouter un nœud")) {
                    model.addNode()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            // À l'ouverture : les liens que la box constate avec les nœuds déjà présents.
            model.linkObserved(app.usage.observedAttachments, boxName: app.usage.boxName, quiet: true)
        }
        .alert(L("Aucune découverte LAN à importer"), isPresented: $isOfferingDiscovery) {
            Button(L("Lancer la découverte")) {
                app.selection = .lanDiscovery
                app.lanDiscovery.refreshInterfaces()
                app.lanDiscovery.requestScan()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Aucune découverte n'a été faite depuis l'ouverture de Pingouin. La lancer maintenant ? La fenêtre Découverte LAN s'ouvre et le balayage part sur le réseau de l'interface choisie. Revenir ensuite ici pour importer les hôtes."))
        }
    }

    // MARK: Schéma

    private var legend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Rectangle()
                    .frame(width: 28, height: 2)
                Text(L("Relation constatée"))
            }
            HStack(spacing: 6) {
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 28, height: 2)
                Text(L("Relation saisie à la main"))
            }
            Spacer()
            Text(L("Glisser un nœud pour le déplacer."))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private var schema: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Fond cliquable : un clic dans le vide retire la sélection.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedNodeID = nil
                    }

                // Les données sont copiées avant le dessin : le tracé ne lit que des valeurs.
                let links = model.topology.links
                let positions = Dictionary(
                    model.topology.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) },
                    uniquingKeysWith: { first, _ in first }
                )
                Canvas { context, _ in
                    for link in links {
                        guard let start = positions[link.from], let end = positions[link.to] else { continue }
                        var path = Path()
                        path.move(to: start)
                        path.addLine(to: end)
                        let style = link.origin == .detected
                            ? StrokeStyle(lineWidth: 2)
                            : StrokeStyle(lineWidth: 2, dash: [6, 5])
                        context.stroke(path, with: .color(.primary.opacity(0.55)), style: style)
                    }
                }
                .allowsHitTesting(false)

                ForEach(model.topology.nodes) { node in
                    nodeView(node)
                        .position(x: node.x, y: node.y)
                        .gesture(
                            DragGesture(minimumDistance: 3, coordinateSpace: .named("schema"))
                                .onChanged { value in
                                    model.selectedNodeID = node.id
                                    model.move(node.id, to: value.location)
                                }
                                .onEnded { _ in
                                    model.endMove()
                                }
                        )
                        .onTapGesture {
                            model.selectedNodeID = node.id
                        }
                        .contextMenu {
                            if !node.address.isEmpty {
                                HostToolsMenu(address: node.address) { module, target in
                                    app.open(module, target: target)
                                }
                                Divider()
                            }
                            Button(L("Supprimer"), role: .destructive) {
                                model.selectedNodeID = node.id
                                model.removeSelected()
                            }
                        }
                }
            }
            .frame(width: TopologyViewModel.canvasSize.width, height: TopologyViewModel.canvasSize.height)
            .coordinateSpace(name: "schema")
        }
        .overlay {
            if model.topology.nodes.isEmpty {
                ContentUnavailableView(
                    L("Schéma vide"),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text(L("Ajouter un nœud, ou importer les hôtes de la découverte LAN."))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private func nodeView(_ node: TopologyNode) -> some View {
        let isSelected = node.id == model.selectedNodeID
        let status = model.statuses[node.id]
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol(for: node.kind))
                    .accessibilityHidden(true)
                Text(node.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            if !node.address.isEmpty {
                Text(node.address)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let status {
                StatusLabel(kind: status.isOnline ? .ok : .failure, text: status.isOnline ? L("En ligne") : L("Sans réponse"))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 110, maxWidth: 190)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        }
        .fixedSize()
    }

    private func symbol(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .router: "wifi.router"
        case .networkSwitch: "rectangle.connected.to.line.below"
        case .accessPoint: "wifi"
        case .server: "server.rack"
        case .workstation: "desktopcomputer"
        case .printer: "printer"
        case .internet: "cloud"
        case .other: "circle.dashed"
        }
    }

    // MARK: Fiche du nœud

    @ViewBuilder
    private var inspector: some View {
        SectionCard(L("Nœud sélectionné")) {
            if let node = model.selectedNode {
                LabeledField(L("Nom")) {
                    TextField(L("Nom"), text: binding(node, \.name))
                        .labelsHidden()
                }
                LabeledField(L("Adresse IP ou nom d'hôte")) {
                    TextField(L("Adresse"), text: binding(node, \.address), prompt: Text(L("Facultatif")))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                }
                LabeledField(L("Type")) {
                    Picker(L("Type"), selection: binding(node, \.kind)) {
                        ForEach(TopologyNodeKind.allCases) { kind in
                            Text(label(for: kind)).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
                LabeledField(L("Statut")) {
                    if let status = model.statuses[node.id] {
                        StatusLabel(
                            kind: status.isOnline ? .ok : .failure,
                            text: "\(status.detail) à \(status.date.formatted(date: .omitted, time: .shortened))"
                        )
                    } else {
                        Text(L("Non contrôlé"))
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledField(L("Origine")) {
                    Text(node.origin == .detected ? L("Trouvé par la découverte LAN") : L("Ajouté à la main"))
                }
                LabeledField(L("Notes")) {
                    TextField(L("Notes"), text: binding(node, \.notes), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...5)
                }

                Divider()

                LabeledField(L("Liens")) {
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
                }

                Button(L("Supprimer ce nœud"), role: .destructive) {
                    model.removeSelected()
                }
            } else {
                Text(L("Cliquer sur un nœud pour voir et modifier sa fiche."))
                    .foregroundStyle(.secondary)
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

    private func label(for kind: TopologyNodeKind) -> String {
        switch kind {
        case .router: L("Routeur")
        case .networkSwitch: L("Commutateur")
        case .accessPoint: L("Point d'accès")
        case .server: L("Serveur")
        case .workstation: L("Poste")
        case .printer: L("Imprimante")
        case .internet: L("Internet")
        case .other: L("Autre")
        }
    }

    // MARK: Export

    private func export() {
        guard let data = model.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "topologie-pingouin.json"
        panel.message = L("Choisir où enregistrer le schéma")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            model.report(L("Schéma exporté dans \(url.lastPathComponent)."))
        } catch {
            model.report(L("L'export a échoué : \(error.localizedDescription)"))
        }
    }
}

/// Trait horizontal, pour la légende.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
