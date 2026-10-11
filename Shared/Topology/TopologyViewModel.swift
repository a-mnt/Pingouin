import Foundation
import Observation
import PingouinCore

/// Statut d'un nœud, tel que constaté par le dernier ping.
struct TopologyNodeStatus: Equatable {
    let isOnline: Bool
    let detail: String
    let date: Date
}

@MainActor
@Observable
final class TopologyViewModel {
    /// Taille du plan de travail, en points.
    static let canvasSize = CGSize(width: 1_500, height: 900)

    private let store = JSONStore<Topology>(fileName: "topologie")
    private let runner = CheckRunner()

    private(set) var topology = Topology()
    private(set) var statuses: [UUID: TopologyNodeStatus] = [:]
    private(set) var isRefreshing = false
    private(set) var message: String?
    var selectedNodeID: UUID?

    init() {
        topology = store.load() ?? Topology()
    }

    var selectedNode: TopologyNode? {
        topology.nodes.first { $0.id == selectedNodeID }
    }

    /// Nœuds auxquels le nœud choisi peut encore être relié.
    var linkCandidates: [TopologyNode] {
        guard let selectedNodeID else { return [] }
        let linked = Set(topology.links.flatMap { link -> [UUID] in
            link.from == selectedNodeID ? [link.to] : (link.to == selectedNodeID ? [link.from] : [])
        })
        return topology.nodes.filter { $0.id != selectedNodeID && !linked.contains($0.id) }
    }

    /// Liens du nœud choisi, avec le nom du nœud d'en face.
    var selectedLinks: [(id: UUID, name: String, origin: TopologyOrigin)] {
        guard let selectedNodeID else { return [] }
        return topology.links.compactMap { link -> (id: UUID, name: String, origin: TopologyOrigin)? in
            guard link.from == selectedNodeID || link.to == selectedNodeID else { return nil }
            let otherID = link.from == selectedNodeID ? link.to : link.from
            let name = topology.nodes.first { $0.id == otherID }?.name ?? L("Nœud supprimé")
            return (id: link.id, name: name, origin: link.origin)
        }
    }

    func position(of id: UUID) -> CGPoint? {
        topology.nodes.first { $0.id == id }.map { CGPoint(x: $0.x, y: $0.y) }
    }

    // MARK: Nœuds

    func addNode() {
        let position = topology.nextGridPosition()
        let node = TopologyNode(name: L("Nouveau nœud"), x: position.x, y: position.y)
        topology.nodes.append(node)
        selectedNodeID = node.id
        save()
    }

    /// Ajoute un hôte venu d'un autre outil, s'il n'est pas déjà sur le schéma. Renvoie vrai s'il a été ajouté.
    @discardableResult
    func addDiscoveredNode(name: String, address: String) -> Bool {
        guard !address.isEmpty, !topology.nodes.contains(where: { $0.address == address }) else { return false }
        let position = topology.nextGridPosition()
        let node = TopologyNode(
            name: name.isEmpty ? address : name,
            address: address,
            kind: .other,
            origin: .detected,
            x: position.x,
            y: position.y
        )
        topology.nodes.append(node)
        selectedNodeID = node.id
        save()
        return true
    }

    /// Ajoute tous les hôtes de la dernière découverte LAN qui manquent au schéma, puis trace
    /// aussitôt les liens que la box constate avec eux.
    func importDiscovered(_ hosts: [(name: String, address: String)], attachments: [ObservedAttachment] = [], boxName: String? = nil) {
        guard !hosts.isEmpty else {
            message = L("Aucun hôte à importer : lancer d'abord une découverte LAN.")
            return
        }
        var added = 0
        for host in hosts where addDiscoveredNode(name: host.name, address: host.address) {
            added += 1
        }
        var text = L(count: added, one: "\(added) hôte ajouté depuis la découverte LAN.", other: "\(added) hôtes ajoutés depuis la découverte LAN.")
        let links = linkObserved(attachments, boxName: boxName, quiet: true)
        if links > 0 {
            text += " " + L(count: links, one: "\(links) lien constaté ajouté.", other: "\(links) liens constatés ajoutés.")
        } else if attachments.isEmpty {
            text += " " + L("Aucun lien tracé : la box n'a pas encore fourni de relevé (fenêtre Consommation).")
        }
        message = text
    }

    func updateSelected(_ change: (inout TopologyNode) -> Void) {
        guard let index = topology.nodes.firstIndex(where: { $0.id == selectedNodeID }) else { return }
        change(&topology.nodes[index])
        save()
    }

    /// Déplace un nœud pendant un glisser. L'enregistrement est fait à la fin du geste.
    func move(_ id: UUID, to point: CGPoint) {
        guard let index = topology.nodes.firstIndex(where: { $0.id == id }) else { return }
        topology.nodes[index].x = min(max(point.x, 60), Self.canvasSize.width - 60)
        topology.nodes[index].y = min(max(point.y, 30), Self.canvasSize.height - 30)
    }

    func endMove() {
        save()
    }

    func removeSelected() {
        guard let selectedNodeID else { return }
        topology.removeNode(selectedNodeID)
        statuses[selectedNodeID] = nil
        self.selectedNodeID = nil
        save()
    }

    // MARK: Liens

    func connectSelected(to other: UUID) {
        guard let selectedNodeID else { return }
        if topology.connect(selectedNodeID, other, origin: .manual) {
            save()
        }
    }

    /// Trace les relations que la box constate : chaque nœud du schéma qu'elle voit est relié à elle.
    /// Le nœud de la box est créé s'il n'existe pas. Aucun autre nœud n'est créé.
    ///
    /// `quiet` : appel fait sans demande explicite (ouverture de la fenêtre, import). Rien n'est alors
    /// créé ni annoncé si la box ne voit aucun nœud du schéma, et la sélection ne change pas.
    /// Renvoie le nombre de liens ajoutés.
    @discardableResult
    func linkObserved(_ attachments: [ObservedAttachment], boxName: String?, quiet: Bool = false) -> Int {
        guard !attachments.isEmpty else {
            if !quiet {
                message = L("Aucun appareil connu d'une box. Connecter une box dans Consommation et attendre un premier relevé.")
            }
            return 0
        }
        let seen = Set(attachments.map(\.address))
        let onSchema = topology.nodes.filter { seen.contains($0.address) }.count
        guard onSchema > 0 else {
            if !quiet {
                message = L("Aucun lien créé : aucun des \(attachments.count) appareils vus par la box n'est sur le schéma. Importer d'abord la découverte LAN.")
            }
            return 0
        }

        let hubID: UUID
        if let existing = boxNodeID() {
            hubID = existing
        } else {
            let position = topology.nextGridPosition()
            let node = TopologyNode(
                name: boxName ?? L("Box"),
                address: Self.boxAddress,
                kind: .router,
                origin: .detected,
                x: position.x,
                y: position.y
            )
            topology.nodes.append(node)
            hubID = node.id
        }
        let added = topology.linkObserved(attachments, to: hubID)
        if added > 0 || !quiet {
            let missing = attachments.count - onSchema
            var text = added > 0
                ? L(count: added, one: "\(added) lien constaté ajouté.", other: "\(added) liens constatés ajoutés.")
                : L("Aucun nouveau lien : les \(onSchema) nœuds que la box voit sont déjà reliés à elle.")
            if missing > 0 {
                text += L(
                    count: missing,
                    one: " \(missing) appareil vu par la box n'est pas sur le schéma : importer la découverte LAN pour l'ajouter.",
                    other: " \(missing) appareils vus par la box ne sont pas sur le schéma : importer la découverte LAN pour les ajouter."
                )
            }
            message = text
        }
        if !quiet {
            selectedNodeID = hubID
        }
        save()
        return added
    }

    private static let boxAddress = "mafreebox.freebox.fr"

    /// Nœud du schéma qui représente la box : celui qui porte son adresse ou son nom,
    /// sinon le seul routeur du schéma. `nil` s'il n'y en a pas, ou s'il y a un doute.
    private func boxNodeID() -> UUID? {
        if let node = topology.nodes.first(where: { $0.address == Self.boxAddress }) {
            return node.id
        }
        if let node = topology.nodes.first(where: { $0.name.lowercased().contains("freebox") }) {
            return node.id
        }
        let routers = topology.nodes.filter { $0.kind == .router }
        return routers.count == 1 ? routers[0].id : nil
    }

    func removeLink(_ id: UUID) {
        topology.links.removeAll { $0.id == id }
        save()
    }

    // MARK: Statuts

    /// Envoie un ping à chaque nœud qui a une adresse, en parallèle.
    func refreshStatuses() {
        guard !isRefreshing else { return }
        let targets = topology.nodes.filter { !$0.address.isEmpty }.map { ($0.id, $0.address) }
        guard !targets.isEmpty else {
            message = L("Aucun nœud n'a d'adresse à contrôler.")
            return
        }
        isRefreshing = true
        message = nil
        let runner = self.runner
        Task {
            let results = await withTaskGroup(of: (UUID, CheckResult).self) { group in
                for (id, address) in targets {
                    group.addTask {
                        (id, await runner.ping(host: address))
                    }
                }
                var collected: [(UUID, CheckResult)] = []
                for await item in group {
                    collected.append(item)
                }
                return collected
            }
            let now = Date()
            for (id, result) in results {
                statuses[id] = TopologyNodeStatus(isOnline: result.succeeded, detail: result.detail, date: now)
            }
            isRefreshing = false
            let online = results.filter { $0.1.succeeded }.count
            message = L(
                count: online,
                one: "\(online) nœud sur \(results.count) répond au ping.",
                other: "\(online) nœuds sur \(results.count) répondent au ping."
            )
        }
    }

    // MARK: Export

    /// Schéma au format JSON, clés triées, pour un export reproductible.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(topology)
        } catch {
            message = L("Le schéma n'a pas pu être préparé pour l'export : \(error.localizedDescription)")
            AppLog.shared.error("Topologie", "Export du schéma en échec : \(error.localizedDescription)")
            return nil
        }
    }

    func report(_ text: String) {
        message = text
    }

    private func save() {
        store.save(topology)
    }
}
