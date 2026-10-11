import Foundation
import os
import PingouinCore

public struct TracerouteOptions: Sendable {
    /// Nombre maximal de sauts, de 1 à 64.
    public var maximumHops: Int
    /// Sondes envoyées à chaque saut, de 1 à 5.
    public var probesPerHop: Int
    /// Délai d'attente de chaque sonde, en millisecondes, de 100 à 10 000.
    public var timeoutMilliseconds: Int
    /// Protocole à utiliser. Automatique : l'adresse saisie décide ; pour un nom, IPv4 d'abord.
    public var family: IPFamilyChoice

    public init(
        maximumHops: Int = 30,
        probesPerHop: Int = 3,
        timeoutMilliseconds: Int = 1_000,
        family: IPFamilyChoice = .automatic
    ) {
        self.maximumHops = maximumHops
        self.probesPerHop = probesPerHop
        self.timeoutMilliseconds = timeoutMilliseconds
        self.family = family
    }

    var clampedHops: Int { min(max(maximumHops, 1), 64) }
    var clampedProbes: Int { min(max(probesPerHop, 1), 5) }
    var clampedTimeout: Int { min(max(timeoutMilliseconds, 100), 10_000) }
}

public enum TracerouteEvent: Sendable {
    case resolved(HostAddress)
    /// Résultat d'une sonde. `address` et `milliseconds` sont absents quand rien n'a répondu.
    case probe(hop: Int, index: Int, address: HostAddress?, milliseconds: Double?)
    /// Nom trouvé pour l'équipement d'un saut. Peut arriver après les sondes des sauts suivants.
    case hopName(hop: Int, name: String)
    case finished(TracerouteOutcome)
}

public enum TracerouteOutcome: Sendable, Equatable {
    case destinationReached(hops: Int)
    /// Un équipement a signalé que la destination est injoignable.
    case destinationUnreachable(hops: Int)
    /// Le nombre maximal de sauts a été atteint sans réponse de la destination.
    case hopLimitReached
}

public enum TracerouteError: Error, Equatable, Sendable {
    case invalidHost
    case hostNotFound
    /// L'hôte n'a pas d'adresse dans le protocole demandé.
    case familyUnavailable(IPFamilyChoice)
    case socketUnavailable(code: Int32)
    /// Le système refuse de régler la durée de vie des paquets : traceroute impossible sans privilèges.
    case timeToLiveNotSupported
}

/// Contrat du service de traceroute, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol Tracing: Sendable {
    func trace(host: String, options: TracerouteOptions) -> AsyncThrowingStream<TracerouteEvent, Error>
}

/// Traceroute par requêtes ICMP Echo à durée de vie croissante, en IPv4 ou en IPv6, sans privilèges.
///
/// Chaque routeur qui jette une sonde le signale par un message « durée de vie épuisée »,
/// ce qui révèle son adresse. La destination, elle, répond par une réponse Echo.
public struct ICMPTracer: Tracing {
    public init() {}

    public func trace(host: String, options: TracerouteOptions) -> AsyncThrowingStream<TracerouteEvent, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.run(
                        host: host,
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
            }
        }
    }

    private enum ProbeAnswer {
        case router(HostAddress, Double)
        case destination(HostAddress, Double)
        case unreachable(HostAddress, Double)
        case silence
    }

    private static func run(
        host: String,
        options: TracerouteOptions,
        isCancelled: @escaping @Sendable () -> Bool,
        emit: @escaping @Sendable (TracerouteEvent) -> Void
    ) throws {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(name) else { throw TracerouteError.invalidHost }

        let target: ICMPTarget
        switch HostResolver.resolve(name, family: options.family) {
        case .success(let resolved):
            target = resolved
        case .failure(.familyUnavailable(let family)):
            throw TracerouteError.familyUnavailable(family)
        case .failure(.notFound):
            throw TracerouteError.hostNotFound
        }
        emit(.resolved(target.address))

        let socket: ICMPSocket
        do {
            socket = try ICMPSocket(ipv6: target.address.isIPv6)
        } catch ICMPSocketError.unavailable(let code) {
            throw TracerouteError.socketUnavailable(code: code)
        }

        let timeout = Double(options.clampedTimeout)
        let nameLookups = DispatchGroup()
        let lookupQueue = DispatchQueue(label: "fr.a-mnt.pingouin.traceroute-names", qos: .utility, attributes: .concurrent)
        var sequence: UInt16 = 0
        var outcome = TracerouteOutcome.hopLimitReached

        hops: for hop in 1...options.clampedHops {
            guard socket.setTimeToLive(hop) else { throw TracerouteError.timeToLiveNotSupported }
            var hopAddress: HostAddress?
            var reached = false
            var unreachable = false

            for index in 1...options.clampedProbes {
                if isCancelled() { throw CancellationError() }
                sequence &+= 1
                let sentAt = monotonicMilliseconds()
                var answer = ProbeAnswer.silence

                if socket.sendEcho(to: target, sequence: sequence) == 0 {
                    while true {
                        if isCancelled() { throw CancellationError() }
                        let remaining = sentAt + timeout - monotonicMilliseconds()
                        guard remaining > 0 else { break }
                        guard let received = socket.receive(waitMilliseconds: Int32(min(remaining, 100).rounded(.up))),
                              let message = socket.classify(received.datagram) else { continue }
                        let elapsed = monotonicMilliseconds() - sentAt

                        switch message {
                        case .timeExceeded(_, let original) where original == sequence:
                            answer = .router(received.source, elapsed)
                        case .echoReply(_, let reply, _, _) where reply == sequence && received.source == target.address:
                            answer = .destination(received.source, elapsed)
                        case .destinationUnreachable(_, _, let original) where original == sequence:
                            answer = .unreachable(received.source, elapsed)
                        default:
                            continue
                        }
                        break
                    }
                }

                switch answer {
                case .router(let address, let milliseconds):
                    hopAddress = hopAddress ?? address
                    emit(.probe(hop: hop, index: index, address: address, milliseconds: milliseconds))
                case .destination(let address, let milliseconds):
                    hopAddress = hopAddress ?? address
                    reached = true
                    emit(.probe(hop: hop, index: index, address: address, milliseconds: milliseconds))
                case .unreachable(let address, let milliseconds):
                    hopAddress = hopAddress ?? address
                    unreachable = true
                    emit(.probe(hop: hop, index: index, address: address, milliseconds: milliseconds))
                case .silence:
                    emit(.probe(hop: hop, index: index, address: nil, milliseconds: nil))
                }
            }

            // Recherche du nom en parallèle, sans retarder les sauts suivants.
            if let address = hopAddress {
                lookupQueue.async(group: nameLookups) {
                    if !isCancelled(), let name = ReverseDNS.hostname(for: address) {
                        emit(.hopName(hop: hop, name: name))
                    }
                }
            }

            if reached {
                outcome = .destinationReached(hops: hop)
                break hops
            }
            if unreachable {
                outcome = .destinationUnreachable(hops: hop)
                break hops
            }
        }

        // On laisse quelques secondes aux recherches de noms encore en cours.
        _ = nameLookups.wait(timeout: .now() + .seconds(3))
        emit(.finished(outcome))
    }
}
