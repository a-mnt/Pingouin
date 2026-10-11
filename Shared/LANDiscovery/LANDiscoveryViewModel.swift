import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Ligne du tableau des hôtes. Tous les champs sont non optionnels pour rester triables.
struct LANHostRow: Identifiable, Hashable {
    let id: UInt32
    let address: String
    let addressValue: UInt32
    let hostname: String
    let macAddress: String
    /// Adresses IPv6 de l'appareil, séparées par des virgules. Vide si aucune n'est connue.
    let ipv6: String
    let responseText: String
    /// Clé de tri du temps de réponse : les hôtes sans réponse au ping sont classés en dernier.
    let responseSortKey: Double
    let status: String
    let statusKind: StatusKind
}

enum LANScanState: Equatable {
    case idle
    case running(phase: String, progress: Double?)
    case finished(summary: String)
    case failed(message: String)
}

@MainActor
@Observable
final class LANDiscoveryViewModel {
    private let service: any LANDiscovering

    var interfaces: [LocalInterface] = []
    var selectedInterfaceID: String? {
        didSet {
            if let interface = interfaces.first(where: { $0.id == selectedInterfaceID }) {
                rangeText = interface.subnet.description
            }
        }
    }
    var rangeText = ""
    var resolveNames = true
    /// Chercher aussi les adresses IPv6 des appareils, sur l'interface de la plage.
    var includeIPv6 = false
    /// Appareils vus seulement en IPv6 lors de la dernière découverte.
    private(set) var ipv6OnlyNeighbors: [IPv6OnlyNeighbor] = []
    var searchText = ""
    var sortOrder = [KeyPathComparator(\LANHostRow.addressValue)]
    var state: LANScanState = .idle
    /// Renseigné quand la plage demande une confirmation explicite avant de partir.
    var pendingConfirmationCount: Int?

    private var hosts: [UInt32: DiscoveredHost] = [:]
    private var scanTask: Task<Void, Never>?

    init(service: any LANDiscovering = LANDiscoveryService()) {
        self.service = service
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var hostCount: Int { hosts.count }

    /// Lignes sélectionnées dans le tableau (identifiants d'hôtes).
    var selection: Set<UInt32> = []

    var pingReplyCount: Int { hosts.values.filter { $0.respondedToPing }.count }

    /// Hôtes vus seulement dans la table ARP. Ce Mac n'est pas compté : il ne se « répond » pas à lui-même.
    var arpOnlyCount: Int { hosts.values.filter { !$0.respondedToPing && !$0.isLocalDevice }.count }

    var medianResponseText: String {
        let times = hosts.values.compactMap { $0.responseMilliseconds }.sorted()
        guard !times.isEmpty else { return "—" }
        let middle = times.count / 2
        let median = times.count % 2 == 1 ? times[middle] : (times[middle - 1] + times[middle]) / 2
        return median.formatted(.number.precision(.fractionLength(1))) + " ms"
    }

    /// Hôtes de la dernière découverte, triés par adresse, pour les outils qui les réutilisent.
    var discoveredHosts: [(name: String, address: String)] {
        hosts.values
            .sorted { $0.address < $1.address }
            .map { (name: $0.hostname ?? "", address: $0.address.description) }
    }

    func row(id: UInt32) -> LANHostRow? {
        hosts[id].map { Self.row(for: $0) }
    }

    /// Lignes choisies au format tabulé, pour le presse-papiers.
    func text(for ids: Set<UInt32>) -> String {
        rows
            .filter { ids.contains($0.id) }
            .map { Self.line(for: $0) }
            .joined(separator: "\n")
    }

    private static func line(for row: LANHostRow) -> String {
        "\(row.address)\t\(row.hostname)\t\(row.macAddress)\t\(row.ipv6)\t\(row.responseText)\t\(row.status)"
    }

    var rows: [LANHostRow] {
        let filter = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return hosts.values
            .map { Self.row(for: $0) }
            .filter { row in
                filter.isEmpty
                    || row.address.contains(filter)
                    || row.hostname.lowercased().contains(filter)
                    || row.macAddress.contains(filter)
                    || row.ipv6.contains(filter)
            }
            .sorted(using: sortOrder)
    }

    /// Lignes au format tabulé, pour le presse-papiers.
    var rowsAsText: String {
        let header = L("Adresse\tNom\tAdresse MAC\tIPv6\tTemps\tÉtat")
        var lines = [header] + rows.map { Self.line(for: $0) }
        if !ipv6OnlyNeighbors.isEmpty {
            lines.append("")
            lines.append(L("Vus seulement en IPv6\tAdresse MAC"))
            lines += ipv6OnlyNeighbors.map { neighbor in
                "\(neighbor.addresses.map(\.description).joined(separator: ", "))\t\(neighbor.macAddress)"
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Interfaces

    func refreshInterfaces() {
        interfaces = InterfaceInventory.ipv4Interfaces()
        if interfaces.contains(where: { $0.id == selectedInterfaceID }) { return }
        selectedInterfaceID = interfaces.first?.id
    }

    // MARK: Lancement

    /// Valide la plage et lance la découverte, ou demande une confirmation si la plage est grande.
    func requestScan() {
        guard !isRunning else { return }
        switch parsedRange() {
        case .failure(let message):
            state = .failed(message: message)
        case .success(let subnet):
            switch LANScanPlan.decision(for: subnet) {
            case .allowed:
                start(subnet)
            case .needsConfirmation(let count):
                pendingConfirmationCount = count
            case .refused(let count, let maximum):
                state = .failed(message: L("Cette plage contient \(count.formatted()) adresses. La découverte est limitée à \(maximum.formatted()) adresses (un /20) : restreindre la plage."))
            }
        }
    }

    /// Appelé quand l'utilisateur confirme une découverte étendue.
    func confirmScan() {
        pendingConfirmationCount = nil
        guard !isRunning, case .success(let subnet) = parsedRange() else { return }
        start(subnet)
    }

    func cancel() {
        scanTask?.cancel()
    }

    private enum RangeResult {
        case success(IPv4Subnet)
        case failure(String)
    }

    private func parsedRange() -> RangeResult {
        switch IPSubnet.parse(rangeText) {
        case .success(.v4(let subnet)):
            return .success(subnet)
        case .success(.v6):
            return .failure(L("Un réseau IPv6 ne se balaie pas : saisir la plage IPv4, et cocher « Adresses IPv6 » pour les obtenir aussi."))
        case .failure:
            return .failure(L("Plage non valide. Attendu : une adresse IPv4 et un préfixe, par exemple 192.168.1.0/24."))
        }
    }

    private func start(_ subnet: IPv4Subnet) {
        hosts = [:]
        ipv6OnlyNeighbors = []
        selection = []
        state = .running(phase: L("Envoi des requêtes ping"), progress: 0)
        let interface = interfaces.first(where: { subnet.contains($0.address) })
        let localAddress = interface?.address
        // La recherche IPv6 a besoin de l'interface raccordée à la plage : sans elle, elle n'a pas lieu.
        let options = LANDiscoveryOptions(
            resolveNames: resolveNames,
            ipv6InterfaceName: includeIPv6 ? interface?.name : nil
        )
        let stream = service.discover(subnet: subnet, localAddress: localAddress, options: options)

        scanTask = Task {
            do {
                for try await event in stream {
                    handle(event)
                }
                if Task.isCancelled {
                    state = .finished(summary: L("Découverte interrompue. \(hosts.count) hôtes trouvés avant l'arrêt."))
                } else if case .running = state {
                    state = .finished(summary: L("\(hosts.count) hôtes trouvés."))
                }
            } catch is CancellationError {
                state = .finished(summary: L("Découverte interrompue. \(hosts.count) hôtes trouvés avant l'arrêt."))
            } catch {
                state = .failed(message: Self.message(for: error))
            }
        }
    }

    private func handle(_ event: LANDiscoveryEvent) {
        switch event {
        case .phase(let phase):
            switch phase {
            case .sweeping:
                state = .running(phase: L("Envoi des requêtes ping"), progress: 0)
            case .readingARPTable:
                state = .running(phase: L("Lecture de la table ARP"), progress: nil)
            case .readingIPv6Neighbors:
                state = .running(phase: L("Recherche des adresses IPv6"), progress: nil)
            case .resolvingNames:
                state = .running(phase: L("Recherche des noms d'hôtes"), progress: nil)
            }
        case .progress(let value):
            state = .running(phase: L("Envoi des requêtes ping"), progress: value)
        case .host(let host):
            // Les événements d'un même hôte se complètent : on ne perd jamais une information déjà obtenue.
            var merged = hosts[host.id] ?? host
            merged.macAddress = host.macAddress ?? merged.macAddress
            merged.hostname = host.hostname ?? merged.hostname
            merged.responseMilliseconds = host.responseMilliseconds ?? merged.responseMilliseconds
            merged.isLocalDevice = merged.isLocalDevice || host.isLocalDevice
            merged.ipv6Addresses = host.ipv6Addresses.isEmpty ? merged.ipv6Addresses : host.ipv6Addresses
            hosts[host.id] = merged
        case .finished(let summary):
            var text = L("\(summary.hostCount) hôtes trouvés sur \(summary.scannedAddressCount) adresses interrogées, dont \(summary.pingReplyCount) ont répondu au ping. Durée : \(summary.durationSeconds.formatted(.number.precision(.fractionLength(1)))) s.")
            #if os(macOS)
            if !summary.arpTableAvailable {
                text += L(" La table ARP n'a pas pu être lue : les adresses MAC et les hôtes muets au ping sont absents.")
            }
            #else
            // iOS ne laisse pas lire la table ARP : c'est la règle, pas une panne.
            text += L(" Sur iOS, seuls les appareils qui répondent au ping sont trouvés, sans leur adresse MAC.")
            #endif
            ipv6OnlyNeighbors = summary.ipv6OnlyNeighbors
            if summary.hostCount > 0 {
                // Première étape de « Pour commencer », sur le tableau de bord.
                AppSettings.discoveryDone = true
            }
            if summary.ipv6TableAvailable == false {
                text += L(" La table des voisins IPv6 n'a pas pu être lue : aucune adresse IPv6 n'est affichée.")
            } else if summary.ipv6TableAvailable == true, !summary.ipv6OnlyNeighbors.isEmpty {
                text += L(" \(summary.ipv6OnlyNeighbors.count) appareil(s) vu(s) seulement en IPv6.")
            } else if includeIPv6, summary.ipv6TableAvailable == nil {
                #if os(macOS)
                text += L(" La recherche IPv6 n'a pas eu lieu : la plage n'est raccordée à aucune interface de ce Mac.")
                #else
                text += L(" La recherche IPv6 n'a pas eu lieu : la plage n'est raccordée à aucune interface de cet appareil.")
                #endif
            }
            state = .finished(summary: text)
        }
    }

    // MARK: Présentation

    private static func row(for host: DiscoveredHost) -> LANHostRow {
        let status: String
        let statusKind: StatusKind
        if host.isLocalDevice {
            #if os(macOS)
            status = L("Ce Mac")
            #else
            status = L("Cet appareil")
            #endif
            statusKind = .warning
        } else if host.respondedToPing {
            status = L("Répond au ping")
            statusKind = .ok
        } else {
            status = L("ARP uniquement")
            statusKind = .neutral
        }
        let responseText: String
        if let milliseconds = host.responseMilliseconds {
            responseText = milliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
        } else {
            responseText = "—"
        }
        return LANHostRow(
            id: host.id,
            address: host.address.description,
            addressValue: host.address.rawValue,
            hostname: host.hostname ?? "",
            macAddress: host.macAddress?.description ?? "",
            ipv6: host.ipv6Addresses.map(\.description).joined(separator: ", "),
            responseText: responseText,
            responseSortKey: host.responseMilliseconds ?? .infinity,
            status: status,
            statusKind: statusKind
        )
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? LANDiscoveryError else {
            return L("La découverte a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .rangeTooLarge(let maximum):
            return L("La plage est trop grande : la découverte est limitée à \(maximum.formatted()) adresses.")
        case .socketUnavailable(let code):
            return L("Impossible d'ouvrir le socket ICMP (erreur système \(code)).")
        case .localNetworkUnreachable:
            #if os(macOS)
            return L("Aucune requête n'a pu partir vers ce réseau. Causes probables : l'accès au réseau local est refusé à Pingouin (Réglages Système > Confidentialité et sécurité > Réseau local), ou l'interface n'est plus connectée. Si macOS vient d'afficher la demande d'autorisation, l'accepter puis relancer.")
            #else
            return L("Aucune requête n'a pu partir vers ce réseau. Causes probables : l'accès au réseau local est refusé à Pingouin (Réglages > Confidentialité et sécurité > Réseau local), ou le Wi-Fi n'est plus connecté. Si iOS vient d'afficher la demande d'autorisation, l'accepter puis relancer.")
            #endif
        }
    }
}
