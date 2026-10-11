import Foundation

public enum TopologyNodeKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case router
    case networkSwitch
    case accessPoint
    case server
    case workstation
    case printer
    case internet
    case other

    public var id: String { rawValue }
}

/// D'où vient une information du schéma. La distinction est affichée : l'application ne
/// présente jamais une relation saisie à la main comme un fait constaté.
public enum TopologyOrigin: String, Codable, Sendable {
    /// Constaté par un outil de l'application.
    case detected
    /// Saisi par l'utilisateur.
    case manual
}

public struct TopologyNode: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Adresse IP ou nom d'hôte ; vide pour un nœud sans adresse (par exemple « Internet »).
    public var address: String
    public var kind: TopologyNodeKind
    public var notes: String
    public var origin: TopologyOrigin
    /// Position du centre du nœud sur le schéma, en points.
    public var x: Double
    public var y: Double

    public init(
        id: UUID = UUID(),
        name: String,
        address: String = "",
        kind: TopologyNodeKind = .other,
        notes: String = "",
        origin: TopologyOrigin = .manual,
        x: Double = 0,
        y: Double = 0
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.kind = kind
        self.notes = notes
        self.origin = origin
        self.x = x
        self.y = y
    }
}

public struct TopologyLink: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    public var origin: TopologyOrigin

    public init(id: UUID = UUID(), from: UUID, to: UUID, origin: TopologyOrigin = .manual) {
        self.id = id
        self.from = from
        self.to = to
        self.origin = origin
    }
}

/// Appareil qu'un équipement du réseau (la box, par exemple) dit voir, et où il le voit.
/// C'est un constat de l'équipement, pas une description du câblage : un appareil vu « derrière
/// le port 1 » peut en être séparé par un switch ou une borne Wi-Fi.
public struct ObservedAttachment: Hashable, Sendable {
    public let name: String
    public let address: String
    /// Endroit où l'appareil est vu : « Wi-Fi 5 GHz », « Port Ethernet 1 »…
    public let via: String

    public init(name: String, address: String, via: String) {
        self.name = name
        self.address = address
        self.via = via
    }
}

public struct Topology: Codable, Equatable, Sendable {
    public var nodes: [TopologyNode]
    public var links: [TopologyLink]

    public init(nodes: [TopologyNode] = [], links: [TopologyLink] = []) {
        self.nodes = nodes
        self.links = links
    }

    /// Ajoute un lien entre deux nœuds existants et distincts. Sans effet si le lien existe déjà,
    /// dans un sens ou dans l'autre. Renvoie vrai si un lien a été ajouté.
    @discardableResult
    public mutating func connect(_ first: UUID, _ second: UUID, origin: TopologyOrigin = .manual) -> Bool {
        guard first != second,
              nodes.contains(where: { $0.id == first }),
              nodes.contains(where: { $0.id == second }),
              !links.contains(where: { ($0.from == first && $0.to == second) || ($0.from == second && $0.to == first) })
        else { return false }
        links.append(TopologyLink(from: first, to: second, origin: origin))
        return true
    }

    /// Relie au nœud `hub` chaque nœud du schéma que l'équipement `hub` dit voir, d'après son adresse.
    ///
    /// Les liens ajoutés sont marqués « constatés ». Un lien déjà présent entre deux nœuds, saisi à la
    /// main ou non, n'est ni doublé ni modifié. La note d'un nœud relié reçoit l'endroit où il est vu,
    /// si elle était vide. Renvoie le nombre de liens ajoutés.
    @discardableResult
    public mutating func linkObserved(_ attachments: [ObservedAttachment], to hub: UUID) -> Int {
        guard nodes.contains(where: { $0.id == hub }) else { return 0 }
        var added = 0
        for attachment in attachments where !attachment.address.isEmpty {
            guard let index = nodes.firstIndex(where: { $0.address == attachment.address && $0.id != hub }) else {
                continue
            }
            if connect(hub, nodes[index].id, origin: .detected) {
                added += 1
                if nodes[index].notes.isEmpty, !attachment.via.isEmpty {
                    nodes[index].notes = L("Vu par la box : \(attachment.via)")
                }
            }
        }
        return added
    }

    /// Retire un nœud et tous les liens qui le touchent.
    public mutating func removeNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        links.removeAll { $0.from == id || $0.to == id }
    }

    /// Position libre pour un nouveau nœud : grille de `columns` colonnes, remplie ligne par ligne.
    public func nextGridPosition(columns: Int = 5, spacing: Double = 170, origin: Double = 110) -> (x: Double, y: Double) {
        let index = nodes.count
        let column = index % max(columns, 1)
        let row = index / max(columns, 1)
        return (origin + Double(column) * spacing, origin + Double(row) * 110)
    }
}
