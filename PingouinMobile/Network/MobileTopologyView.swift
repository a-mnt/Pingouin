import SwiftUI
import PingouinCore

/// Topologie sur iPhone et iPad : le schéma défile dans les deux sens ; toucher un nœud ouvre sa fiche,
/// un appui prolongé suivi d'un glissement le déplace.
struct MobileTopologyView: View {
    @Environment(MobileAppState.self) private var state
    @Bindable var model: TopologyViewModel
    @State private var isOfferingDiscovery = false
    @State private var isShowingNode = false
    @State private var sharedFile: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            schema
            if let message = model.message {
                MobileFootnote(text: message)
            }
        }
        .padding(12)
        .background { PingouinBackdrop() }
        .navigationTitle(L("Topologie"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Importer la découverte LAN")) {
                        let hosts = state.lanDiscovery.discoveredHosts
                        if hosts.isEmpty {
                            isOfferingDiscovery = true
                        } else {
                            model.importDiscovered(hosts, attachments: state.usage.observedAttachments, boxName: state.usage.boxName)
                        }
                    }
                    Button(L("Détecter les liens")) {
                        model.linkObserved(state.usage.observedAttachments, boxName: state.usage.boxName)
                    }
                    Button(model.isRefreshing ? L("Contrôle en cours…") : L("Actualiser les statuts")) {
                        model.refreshStatuses()
                    }
                    .disabled(model.isRefreshing)
                    Divider()
                    Button(L("Exporter…")) {
                        export()
                    }
                    .disabled(model.topology.nodes.isEmpty)
                } label: {
                    Label(L("Actions sur le schéma"), systemImage: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.addNode()
                    isShowingNode = true
                } label: {
                    Label(L("Ajouter un nœud"), systemImage: "plus")
                }
            }
        }
        .task {
            // À l'ouverture : les liens que la box constate avec les nœuds déjà présents.
            model.linkObserved(state.usage.observedAttachments, boxName: state.usage.boxName, quiet: true)
        }
        .sheet(isPresented: $isShowingNode) {
            MobileTopologyNodeSheet(model: model) { module, target in
                isShowingNode = false
                state.open(module, target: target)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $sharedFile) { file in
            MobileShareSheet(file: file)
        }
        .alert(L("Aucune découverte LAN à importer"), isPresented: $isOfferingDiscovery) {
            Button(L("Lancer la découverte")) {
                state.show(.lanDiscovery)
                state.lanDiscovery.refreshInterfaces()
                state.lanDiscovery.requestScan()
            }
            Button(L("Annuler"), role: .cancel) {}
        } message: {
            Text(L("Aucune découverte n'a été faite depuis l'ouverture de Pingouin. La lancer maintenant ? L'écran Découverte LAN s'ouvre et le balayage part sur le réseau Wi-Fi. Revenir ensuite ici pour importer les hôtes."))
        }
    }

    // MARK: Schéma

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Rectangle()
                        .frame(width: 24, height: 2)
                    Text(L("Relation constatée"))
                }
                HStack(spacing: 6) {
                    MobileTopologyLine()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .frame(width: 24, height: 2)
                    Text(L("Relation saisie à la main"))
                }
            }
            Text(L("Toucher un nœud pour ouvrir sa fiche. Appui prolongé, puis glisser, pour le déplacer."))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var schema: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
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
                        .onTapGesture {
                            model.selectedNodeID = node.id
                            isShowingNode = true
                        }
                        .gesture(moveGesture(for: node))
                        .accessibilityAddTraits(.isButton)
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
        .glassCard(cornerRadius: 22)
    }

    /// Un simple glissement fait défiler le schéma : le déplacement d'un nœud commence par un appui prolongé.
    private func moveGesture(for node: TopologyNode) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("schema")))
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    model.selectedNodeID = node.id
                    model.move(node.id, to: drag.location)
                }
            }
            .onEnded { _ in
                model.endMove()
            }
    }

    private func nodeView(_ node: TopologyNode) -> some View {
        let isSelected = node.id == model.selectedNodeID
        let status = model.statuses[node.id]
        return VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: MobileTopologyLabels.symbol(for: node.kind))
                    .accessibilityHidden(true)
                Text(node.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            if !node.address.isEmpty {
                Text(node.address)
                    .font(.footnote.monospaced())
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
        .accessibilityElement(children: .combine)
    }

    private func export() {
        guard let data = model.exportData() else { return }
        if let file = TemporaryFile.write(data, named: "topologie-pingouin.json") {
            sharedFile = file
        } else {
            model.report(L("L'export a échoué : le fichier n'a pas pu être écrit."))
        }
    }
}

/// Trait horizontal, pour la légende.
private struct MobileTopologyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

enum MobileTopologyLabels {
    static func symbol(for kind: TopologyNodeKind) -> String {
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

    static func label(for kind: TopologyNodeKind) -> String {
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
}
