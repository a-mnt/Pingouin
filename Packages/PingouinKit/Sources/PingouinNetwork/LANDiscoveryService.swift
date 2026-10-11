import Foundation
import os
import PingouinCore

public struct LANDiscoveryOptions: Sendable {
    /// Durée d'attente des réponses tardives après le dernier envoi, en secondes.
    public var replyTimeout: TimeInterval
    /// Recherche inverse des noms d'hôtes (peut allonger la découverte de plusieurs secondes).
    public var resolveNames: Bool
    /// Interface sur laquelle chercher aussi les adresses IPv6 des appareils. `nil` : IPv4 seulement.
    public var ipv6InterfaceName: String?

    public init(replyTimeout: TimeInterval = 1.0, resolveNames: Bool = true, ipv6InterfaceName: String? = nil) {
        self.replyTimeout = replyTimeout
        self.resolveNames = resolveNames
        self.ipv6InterfaceName = ipv6InterfaceName
    }
}

public enum LANDiscoveryPhase: Sendable, Equatable {
    case sweeping
    case readingARPTable
    case readingIPv6Neighbors
    case resolvingNames
}

public struct LANDiscoverySummary: Sendable, Equatable {
    public let scannedAddressCount: Int
    public let hostCount: Int
    public let pingReplyCount: Int
    /// Faux si la table ARP n'a pas pu être lue : les adresses MAC manquent alors, et les hôtes muets au ping aussi.
    public let arpTableAvailable: Bool
    public let durationSeconds: Double
    /// Recherche IPv6 : `nil` si elle n'était pas demandée, faux si la table des voisins n'a pas pu être lue.
    public let ipv6TableAvailable: Bool?
    /// Appareils vus en IPv6 sans adresse IPv4 connue sur la plage.
    public let ipv6OnlyNeighbors: [IPv6OnlyNeighbor]

    public init(
        scannedAddressCount: Int,
        hostCount: Int,
        pingReplyCount: Int,
        arpTableAvailable: Bool,
        durationSeconds: Double,
        ipv6TableAvailable: Bool? = nil,
        ipv6OnlyNeighbors: [IPv6OnlyNeighbor] = []
    ) {
        self.scannedAddressCount = scannedAddressCount
        self.hostCount = hostCount
        self.pingReplyCount = pingReplyCount
        self.arpTableAvailable = arpTableAvailable
        self.durationSeconds = durationSeconds
        self.ipv6TableAvailable = ipv6TableAvailable
        self.ipv6OnlyNeighbors = ipv6OnlyNeighbors
    }
}

public enum LANDiscoveryEvent: Sendable {
    case phase(LANDiscoveryPhase)
    /// Avancement du balayage, de 0 à 1.
    case progress(Double)
    /// Hôte nouveau ou mis à jour (même adresse) : le dernier événement reçu fait foi.
    case host(DiscoveredHost)
    case finished(LANDiscoverySummary)
}

public enum LANDiscoveryError: Error, Equatable, Sendable {
    case rangeTooLarge(maximum: Int)
    case socketUnavailable(code: Int32)
    case localNetworkUnreachable
}

/// Contrat du service de découverte, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol LANDiscovering: Sendable {
    /// Lance une découverte. Le flux se termine après `.finished`, ou en erreur.
    /// Abandonner l'itération du flux annule la découverte.
    func discover(
        subnet: IPv4Subnet,
        localAddress: IPAddressV4?,
        options: LANDiscoveryOptions
    ) -> AsyncThrowingStream<LANDiscoveryEvent, Error>
}

/// Découverte par balayage ICMP, complétée par la table ARP puis par la recherche inverse des noms.
///
/// IPv6 : un réseau /64 ne se balaie pas. Sur demande, les voisins de l'interface sont sollicités
/// (ping à « tous les nœuds »), puis la table des voisins du système est lue ; ses adresses sont
/// rattachées aux hôtes trouvés en IPv4 par leur adresse MAC.
///
/// Limites assumées : seul le sous-réseau directement raccordé est visible. Les hôtes situés derrière
/// un routeur n'ont pas d'entrée ARP, et un pare-feu ou l'isolation des clients Wi-Fi peut masquer des hôtes.
public struct LANDiscoveryService: LANDiscovering {
    public init() {}

    public func discover(
        subnet: IPv4Subnet,
        localAddress: IPAddressV4?,
        options: LANDiscoveryOptions
    ) -> AsyncThrowingStream<LANDiscoveryEvent, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await Self.run(
                        subnet: subnet,
                        localAddress: localAddress,
                        options: options,
                        isCancelled: { cancelled.withLock { $0 } },
                        emit: { event in _ = continuation.yield(event) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                cancelled.withLock { $0 = true }
                task.cancel()
            }
        }
    }

    private static func run(
        subnet: IPv4Subnet,
        localAddress: IPAddressV4?,
        options: LANDiscoveryOptions,
        isCancelled: @escaping @Sendable () -> Bool,
        emit: @escaping @Sendable (LANDiscoveryEvent) -> Void
    ) async throws {
        let started = DispatchTime.now().uptimeNanoseconds
        let targets = LANScanPlan.targets(in: subnet)
        guard !targets.isEmpty else {
            throw LANDiscoveryError.rangeTooLarge(maximum: LANScanPlan.maximumHosts)
        }

        // 1. Balayage ICMP, sur une file Dispatch car l'appel est bloquant.
        emit(.phase(.sweeping))
        let replyTimeout = options.replyTimeout
        let replies: [ICMPSweepReply] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try ICMPSweeper().run(
                        targets: targets,
                        replyTimeout: replyTimeout,
                        isCancelled: isCancelled,
                        onProgress: { emit(.progress($0)) },
                        onReply: { reply in
                            emit(.host(DiscoveredHost(
                                address: reply.address,
                                responseMilliseconds: reply.roundTripMilliseconds,
                                isLocalDevice: reply.address == localAddress
                            )))
                        }
                    )
                    continuation.resume(returning: result)
                } catch let error as ICMPSweepError {
                    switch error {
                    case .socketUnavailable(let code):
                        continuation.resume(throwing: LANDiscoveryError.socketUnavailable(code: code))
                    case .localNetworkUnreachable:
                        continuation.resume(throwing: LANDiscoveryError.localNetworkUnreachable)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()

        var hosts: [UInt32: DiscoveredHost] = [:]
        for reply in replies {
            hosts[reply.address.rawValue] = DiscoveredHost(
                address: reply.address,
                responseMilliseconds: reply.roundTripMilliseconds,
                isLocalDevice: reply.address == localAddress
            )
        }

        // 2. Table ARP : adresses MAC, et hôtes qui ignorent le ping mais répondent en ARP.
        emit(.phase(.readingARPTable))
        var arpTableAvailable = true
        var entries: [ARPEntry] = []
        do {
            entries = try ARPTableReader().read()
        } catch {
            arpTableAvailable = false
        }
        let targetSet = Set(targets.map(\.rawValue))
        for entry in entries {
            guard targetSet.contains(entry.address.rawValue),
                  let mac = entry.macAddress, !mac.isMulticast else { continue }
            var host = hosts[entry.address.rawValue]
                ?? DiscoveredHost(address: entry.address, isLocalDevice: entry.address == localAddress)
            host.macAddress = mac
            hosts[entry.address.rawValue] = host
            emit(.host(host))
        }

        // Ce Mac figure dans la liste même si personne ne lui a répondu.
        if let localAddress, targetSet.contains(localAddress.rawValue), hosts[localAddress.rawValue] == nil {
            let host = DiscoveredHost(address: localAddress, isLocalDevice: true)
            hosts[localAddress.rawValue] = host
            emit(.host(host))
        }
        try Task.checkCancellation()

        // 3. Adresses IPv6, rattachées aux hôtes par leur adresse MAC.
        var ipv6TableAvailable: Bool?
        var ipv6OnlyNeighbors: [IPv6OnlyNeighbor] = []
        if let interfaceName = options.ipv6InterfaceName {
            emit(.phase(.readingIPv6Neighbors))
            let table: [NDPEntry]? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    IPv6NeighborProbe.solicit(interfaceName: interfaceName, waitSeconds: 1.5, isCancelled: isCancelled)
                    continuation.resume(returning: try? NDPTableReader().read())
                }
            }
            try Task.checkCancellation()
            ipv6TableAvailable = table != nil
            if let table {
                let devices = NDPTableParser.addressesByDevice(table, interfaceName: interfaceName)
                var matched: Set<MACAddress> = []
                for (key, host) in hosts {
                    var addresses: [IPAddressV6] = []
                    if host.isLocalDevice {
                        addresses = devices.local
                    } else if let mac = host.macAddress, let found = devices.neighbors[mac] {
                        addresses = found
                        matched.insert(mac)
                    }
                    guard !addresses.isEmpty else { continue }
                    var updated = host
                    updated.ipv6Addresses = addresses
                    hosts[key] = updated
                    emit(.host(updated))
                }
                ipv6OnlyNeighbors = devices.neighbors
                    .filter { !matched.contains($0.key) }
                    .map { IPv6OnlyNeighbor(macAddress: $0.key, addresses: $0.value) }
                    .sorted { $0.id < $1.id }
            }
        }

        // 4. Noms d'hôtes.
        if options.resolveNames, !hosts.isEmpty {
            emit(.phase(.resolvingNames))
            let snapshot = hosts
            let addresses = snapshot.values.map(\.address).sorted()
            await ReverseDNS.hostnames(for: addresses) { address, name in
                guard var host = snapshot[address.rawValue] else { return }
                host.hostname = name
                emit(.host(host))
            }
            try Task.checkCancellation()
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        emit(.finished(LANDiscoverySummary(
            scannedAddressCount: targets.count,
            hostCount: hosts.count,
            pingReplyCount: replies.count,
            arpTableAvailable: arpTableAvailable,
            durationSeconds: elapsed,
            ipv6TableAvailable: ipv6TableAvailable,
            ipv6OnlyNeighbors: ipv6OnlyNeighbors
        )))
    }
}
