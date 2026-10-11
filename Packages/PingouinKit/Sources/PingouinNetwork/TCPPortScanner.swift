import Foundation
import Network
import os
import PingouinCore

public struct PortScanOptions: Sendable {
    /// Délai d'attente par port, en millisecondes. Borné entre 100 et 10 000.
    public var timeoutMilliseconds: Int
    /// Nombre de connexions ouvertes en même temps. Borné entre 1 et 128.
    public var concurrency: Int

    public static let defaultTimeoutMilliseconds = 400
    public static let defaultConcurrency = 64

    public init(
        timeoutMilliseconds: Int = PortScanOptions.defaultTimeoutMilliseconds,
        concurrency: Int = PortScanOptions.defaultConcurrency
    ) {
        self.timeoutMilliseconds = timeoutMilliseconds
        self.concurrency = concurrency
    }

    var clampedTimeout: Int { min(max(timeoutMilliseconds, 100), 10_000) }
    var clampedConcurrency: Int { min(max(concurrency, 1), 128) }
}

public enum PortScanEvent: Sendable {
    /// Résultat d'un port. Les ports arrivent dans l'ordre où ils répondent, pas dans l'ordre numérique.
    case result(PortScanResult)
    case finished(durationSeconds: Double)
}

public enum PortScanError: Error, Equatable, Sendable {
    case invalidHost
    case noPorts
    /// Le nom d'hôte n'a pas pu être résolu.
    case hostNotFound
}

/// Contrat du service de scan, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol PortScanning: Sendable {
    /// Lance un scan. Le flux se termine après `.finished`, ou en erreur.
    /// Abandonner l'itération du flux annule le scan.
    func scan(host: String, ports: [UInt16], options: PortScanOptions) -> AsyncThrowingStream<PortScanEvent, Error>
}

/// Scan par connexion TCP complète (framework Network), sans privilèges.
///
/// Ce que le test permet de conclure : connexion acceptée → ouvert ; connexion refusée → fermé ;
/// silence ou erreur réseau → indéterminé (souvent un pare-feu qui ignore la demande).
public struct TCPPortScanner: PortScanning {
    public init() {}

    public func scan(host: String, ports: [UInt16], options: PortScanOptions) -> AsyncThrowingStream<PortScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try await Self.run(host: host, ports: ports, options: options) { event in
                        _ = continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private enum ProbeOutcome: Sendable {
        case result(PortScanResult)
        case hostNotFound
    }

    private static func run(
        host: String,
        ports: [UInt16],
        options: PortScanOptions,
        emit: @escaping @Sendable (PortScanEvent) -> Void
    ) async throws {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(target) else { throw PortScanError.invalidHost }
        guard !ports.isEmpty else { throw PortScanError.noPorts }

        let queue = DispatchQueue(label: "fr.a-mnt.pingouin.port-scan", qos: .userInitiated, attributes: .concurrent)
        let timeout = options.clampedTimeout
        let width = options.clampedConcurrency
        let clock = ContinuousClock()
        let started = clock.now

        try await withThrowingTaskGroup(of: ProbeOutcome.self) { group in
            var remaining = ports.makeIterator()

            // Fenêtre glissante : jamais plus de `width` connexions en cours.
            for _ in 0..<width {
                guard let port = remaining.next() else { break }
                group.addTask {
                    await probe(host: target, port: port, timeoutMilliseconds: timeout, queue: queue)
                }
            }

            while let outcome = try await group.next() {
                try Task.checkCancellation()
                switch outcome {
                case .hostNotFound:
                    group.cancelAll()
                    throw PortScanError.hostNotFound
                case .result(let result):
                    emit(.result(result))
                }
                if let port = remaining.next() {
                    group.addTask {
                        await probe(host: target, port: port, timeoutMilliseconds: timeout, queue: queue)
                    }
                }
            }
        }

        emit(.finished(durationSeconds: seconds(started.duration(to: clock.now))))
    }

    /// Teste un port. Rend toujours un résultat, au plus tard à l'expiration du délai.
    private static func probe(
        host: String,
        port: UInt16,
        timeoutMilliseconds: Int,
        queue: DispatchQueue
    ) async -> ProbeOutcome {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return .result(PortScanResult(port: port, detail: .networkError(code: EINVAL)))
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let alreadyResumed = OSAllocatedUnfairLock(initialState: false)
        let clock = ContinuousClock()
        let started = clock.now

        let outcome: ProbeOutcome = await withCheckedContinuation { continuation in
            // La connexion et le minuteur peuvent conclure tous les deux : seul le premier compte.
            let finish: @Sendable (ProbeOutcome) -> Void = { outcome in
                let isFirst = alreadyResumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if isFirst {
                    continuation.resume(returning: outcome)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = seconds(started.duration(to: clock.now)) * 1_000
                    finish(.result(PortScanResult(port: port, detail: .accepted(milliseconds: elapsed))))
                case .waiting(let error), .failed(let error):
                    finish(interpret(error, port: port))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) {
                finish(.result(PortScanResult(port: port, detail: .timedOut)))
            }
        }

        connection.stateUpdateHandler = nil
        connection.cancel()
        return outcome
    }

    private static func interpret(_ error: NWError, port: UInt16) -> ProbeOutcome {
        switch error {
        case .posix(let code):
            if code == .ECONNREFUSED {
                return .result(PortScanResult(port: port, detail: .refused))
            }
            return .result(PortScanResult(port: port, detail: .networkError(code: code.rawValue)))
        case .dns:
            return .hostNotFound
        default:
            return .result(PortScanResult(port: port, detail: .networkError(code: 0)))
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
