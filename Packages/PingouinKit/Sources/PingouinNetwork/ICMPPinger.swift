import Foundation
import os
import PingouinCore

public struct PingOptions: Sendable {
    /// Nombre de requêtes, de 1 à 1 000.
    public var count: Int
    /// Intervalle entre deux requêtes, en secondes, de 0,2 à 60.
    public var intervalSeconds: Double
    /// Délai d'attente de chaque réponse, en millisecondes, de 100 à 10 000.
    public var timeoutMilliseconds: Int
    /// Protocole à utiliser. Automatique : l'adresse saisie décide ; pour un nom, IPv4 d'abord.
    public var family: IPFamilyChoice

    public init(
        count: Int = 20,
        intervalSeconds: Double = 1,
        timeoutMilliseconds: Int = 1_000,
        family: IPFamilyChoice = .automatic
    ) {
        self.count = count
        self.intervalSeconds = intervalSeconds
        self.timeoutMilliseconds = timeoutMilliseconds
        self.family = family
    }

    var clampedCount: Int { min(max(count, 1), 1_000) }
    var clampedInterval: Double { min(max(intervalSeconds, 0.2), 60) }
    var clampedTimeout: Int { min(max(timeoutMilliseconds, 100), 10_000) }
}

public enum PingEvent: Sendable {
    /// Adresse réellement interrogée, après résolution du nom.
    case resolved(HostAddress)
    /// `ttl` est absent en IPv6 : le système ne le fournit pas avec la réponse.
    case reply(sequence: Int, milliseconds: Double, ttl: Int?)
    case timeout(sequence: Int)
    /// La requête n'a pas pu partir (code d'erreur système).
    case sendFailure(sequence: Int, code: Int32)
    case finished
}

public enum PingError: Error, Equatable, Sendable {
    case invalidHost
    case hostNotFound
    /// L'hôte n'a pas d'adresse dans le protocole demandé.
    case familyUnavailable(IPFamilyChoice)
    case socketUnavailable(code: Int32)
}

/// Contrat du service de ping, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol Pinging: Sendable {
    /// Lance une série de pings. Le flux se termine après `.finished`, ou en erreur.
    /// Abandonner l'itération du flux arrête la série.
    func ping(host: String, options: PingOptions) -> AsyncThrowingStream<PingEvent, Error>
}

/// Ping ICMP Echo en IPv4 ou en IPv6, sans privilèges.
public struct ICMPPinger: Pinging {
    public init() {}

    public func ping(host: String, options: PingOptions) -> AsyncThrowingStream<PingEvent, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = OSAllocatedUnfairLock(initialState: false)
            // La boucle est bloquante : elle tourne sur une file Dispatch, hors du pool de tâches.
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

    private static func run(
        host: String,
        options: PingOptions,
        isCancelled: () -> Bool,
        emit: (PingEvent) -> Void
    ) throws {
        let name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(name) else { throw PingError.invalidHost }

        let target: ICMPTarget
        switch HostResolver.resolve(name, family: options.family) {
        case .success(let resolved):
            target = resolved
        case .failure(.familyUnavailable(let family)):
            throw PingError.familyUnavailable(family)
        case .failure(.notFound):
            throw PingError.hostNotFound
        }
        emit(.resolved(target.address))

        let socket: ICMPSocket
        do {
            socket = try ICMPSocket(ipv6: target.address.isIPv6)
        } catch ICMPSocketError.unavailable(let code) {
            throw PingError.socketUnavailable(code: code)
        }

        let count = options.clampedCount
        let interval = options.clampedInterval * 1_000
        let timeout = Double(options.clampedTimeout)

        for sequence in 1...count {
            if isCancelled() { throw CancellationError() }
            let wireSequence = UInt16(truncatingIfNeeded: sequence)
            let sentAt = monotonicMilliseconds()
            let code = socket.sendEcho(to: target, sequence: wireSequence)

            if code != 0 {
                emit(.sendFailure(sequence: sequence, code: code))
            } else {
                var answered = false
                while !answered {
                    if isCancelled() { throw CancellationError() }
                    let remaining = sentAt + timeout - monotonicMilliseconds()
                    guard remaining > 0 else { break }
                    guard let received = socket.receive(waitMilliseconds: Int32(min(remaining, 100).rounded(.up))) else { continue }
                    let now = monotonicMilliseconds()
                    guard received.source == target.address,
                          case .echoReply(_, let replySequence, let payload, let ttl)? = socket.classify(received.datagram),
                          replySequence == wireSequence,
                          payload.starts(with: ICMPEcho.defaultPayload) else { continue }
                    emit(.reply(sequence: sequence, milliseconds: now - sentAt, ttl: ttl.map { Int($0) }))
                    answered = true
                }
                if !answered {
                    emit(.timeout(sequence: sequence))
                }
            }

            // Attente jusqu'au prochain envoi, par petites tranches pour rester annulable.
            if sequence < count {
                while monotonicMilliseconds() < sentAt + interval {
                    if isCancelled() { throw CancellationError() }
                    usleep(20_000)
                }
            }
        }
        emit(.finished)
    }
}
