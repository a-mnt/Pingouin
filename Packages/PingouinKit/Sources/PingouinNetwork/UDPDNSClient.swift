import CPingouinSystem
import Foundation
import Network
import os
import PingouinCore

/// Ce qu'une requête DNS a donné. Les cas sont volontairement distincts : une absence
/// d'enregistrement n'est ni une panne, ni un délai dépassé.
public enum DNSOutcome: Equatable, Sendable {
    case answers([DNSRecord])
    /// Le nom existe, mais n'a aucun enregistrement du type demandé.
    case noRecords
    /// Le nom n'existe pas (NXDOMAIN).
    case nonexistentDomain
    /// Le serveur a répondu par une erreur (2 : échec, 5 : refusé…).
    case serverFailure(code: Int)
    /// Réponse trop longue pour l'UDP : les enregistrements reçus sont incomplets.
    case truncated([DNSRecord])
    case timedOut
    case networkError(String)
    case malformedResponse
}

public struct DNSQueryResult: Equatable, Sendable {
    /// Serveur réellement interrogé.
    public let server: String
    public let outcome: DNSOutcome
    /// Temps de résolution, absent quand aucune réponse n'est arrivée.
    public let milliseconds: Double?

    public init(server: String, outcome: DNSOutcome, milliseconds: Double?) {
        self.server = server
        self.outcome = outcome
        self.milliseconds = milliseconds
    }
}

public enum DNSQueryError: Error, Equatable, Sendable {
    /// Le nom ne peut pas être encodé (vide, trop long, caractères non ASCII).
    case invalidName
    case invalidServer
    /// Aucun serveur DNS n'a pu être lu dans la configuration du système.
    case noSystemServer
}

/// Contrat du client DNS, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol DNSQuerying: Sendable {
    /// Serveurs DNS configurés sur le système, dans l'ordre.
    func systemServers() -> [String]

    /// Interroge un serveur. `server` vaut `nil` pour le premier serveur du système.
    func query(name: String, type: DNSRecordType, server: String?, timeoutMilliseconds: Int) async throws -> DNSQueryResult
}

/// Client DNS sur UDP, qui parle directement au serveur choisi (port 53).
///
/// Limites : pas de repli sur TCP quand la réponse est tronquée, pas de DNSSEC,
/// pas de noms internationalisés (ils doivent être saisis sous leur forme ASCII « xn-- »).
public struct UDPDNSClient: DNSQuerying {
    public init() {}

    public func systemServers() -> [String] {
        var servers: [String] = []
        if let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) {
            for line in content.split(whereSeparator: \.isNewline) {
                let words = line.split(separator: " ", omittingEmptySubsequences: true)
                if words.count >= 2, words[0] == "nameserver" {
                    servers.append(String(words[1]))
                }
            }
        }
        // Sur iOS, ce fichier n'est pas lisible : on demande alors la liste au résolveur du système.
        return servers.isEmpty ? Self.resolverServers() : servers
    }

    /// Serveurs DNS connus du résolveur du système (libresolv). Rien n'est envoyé sur le réseau.
    static func resolverServers() -> [String] {
        var buffer = [CChar](repeating: 0, count: 512)
        guard pingouin_dns_servers(&buffer, buffer.count) > 0 else { return [] }
        return CText.string(buffer).split(whereSeparator: \.isNewline).map(String.init)
    }

    public func query(name: String, type: DNSRecordType, server: String?, timeoutMilliseconds: Int) async throws -> DNSQueryResult {
        let target: String
        if let server {
            target = server.trimmingCharacters(in: .whitespacesAndNewlines)
            guard HostInput.isPlausible(target) else { throw DNSQueryError.invalidServer }
        } else {
            guard let first = systemServers().first else { throw DNSQueryError.noSystemServer }
            target = first
        }

        let identifier = UInt16.random(in: 1...UInt16.max)
        let question = DNSMessage.questionName(for: name, type: type)
        guard let payload = DNSMessage.query(id: identifier, name: question, type: type) else {
            throw DNSQueryError.invalidName
        }

        let started = monotonicMilliseconds()
        let exchange = await Self.exchange(server: target, payload: payload, timeoutMilliseconds: min(max(timeoutMilliseconds, 100), 30_000))
        let elapsed = monotonicMilliseconds() - started

        switch exchange {
        case .timedOut:
            return DNSQueryResult(server: target, outcome: .timedOut, milliseconds: nil)
        case .failed(let reason):
            return DNSQueryResult(server: target, outcome: .networkError(reason), milliseconds: nil)
        case .data(let bytes):
            guard let response = DNSMessage.parse(bytes), response.id == identifier else {
                return DNSQueryResult(server: target, outcome: .malformedResponse, milliseconds: elapsed)
            }
            let outcome: DNSOutcome
            if response.isTruncated {
                outcome = .truncated(response.answers)
            } else if response.responseCode == 3 {
                outcome = .nonexistentDomain
            } else if response.responseCode != 0 {
                outcome = .serverFailure(code: response.responseCode)
            } else if response.answers.isEmpty {
                outcome = .noRecords
            } else {
                outcome = .answers(response.answers)
            }
            return DNSQueryResult(server: target, outcome: outcome, milliseconds: elapsed)
        }
    }

    private enum Exchange: Sendable {
        case data([UInt8])
        case timedOut
        case failed(String)
    }

    /// Envoie la question et attend un datagramme en retour, au plus `timeoutMilliseconds`.
    private static func exchange(server: String, payload: [UInt8], timeoutMilliseconds: Int) async -> Exchange {
        let queue = DispatchQueue(label: "fr.a-mnt.pingouin.dns")
        let connection = NWConnection(host: NWEndpoint.Host(server), port: 53, using: .udp)
        let alreadyResumed = OSAllocatedUnfairLock(initialState: false)

        let result: Exchange = await withCheckedContinuation { continuation in
            let finish: @Sendable (Exchange) -> Void = { outcome in
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
                case .waiting(let error), .failed(let error):
                    finish(.failed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // L'envoi et la réception sont mis en file dès maintenant : le framework les exécute
            // une fois la connexion prête.
            connection.send(content: Data(payload), completion: .contentProcessed { error in
                if let error {
                    finish(.failed(error.localizedDescription))
                }
            })
            connection.receiveMessage { content, _, _, error in
                if let content, !content.isEmpty {
                    finish(.data(Array(content)))
                } else if let error {
                    finish(.failed(error.localizedDescription))
                }
            }
            queue.asyncAfter(deadline: .now() + .milliseconds(timeoutMilliseconds)) {
                finish(.timedOut)
            }
        }

        connection.stateUpdateHandler = nil
        connection.cancel()
        return result
    }
}
