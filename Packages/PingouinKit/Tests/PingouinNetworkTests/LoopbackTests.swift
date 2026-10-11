import Foundation
import Network
import os
import Security
import PingouinCore
import Testing
@testable import PingouinNetwork

/// Essais des services réseau contre la boucle locale (127.0.0.1) : aucun paquet ne quitte la machine.
/// Chaque essai monte son propre serveur sur un port libre choisi par le système.
@Suite("Services réseau sur la boucle locale", .serialized)
struct LoopbackTests {

    /// Petit serveur TCP local. Il répond à toute connexion par le texte donné, puis ferme.
    private final class LocalServer: @unchecked Sendable {
        let listener: NWListener
        private let queue = DispatchQueue(label: "pingouin.tests.serveur")

        init(response: Data) throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                // On attend la demande du client avant de répondre, comme un vrai serveur.
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
        }

        /// Démarre le serveur et renvoie le port sur lequel il écoute.
        func start() async throws -> UInt16 {
            try await withCheckedThrowingContinuation { continuation in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                listener.stateUpdateHandler = { [listener] state in
                    let first = resumed.withLock { done -> Bool in
                        if done { return false }
                        switch state {
                        case .ready, .failed, .cancelled:
                            done = true
                            return true
                        default:
                            return false
                        }
                    }
                    guard first else { return }
                    if case .ready = state, let port = listener.port?.rawValue {
                        continuation.resume(returning: port)
                    } else {
                        continuation.resume(throwing: CancellationError())
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
        }
    }

    /// Port TCP de la boucle locale sur lequel rien n'écoute : réservé un instant, puis relâché.
    private func closedPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(bound == 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        try #require(named == 0)
        return UInt16(bigEndian: address.sin_port)
    }

    @Test("Le scan voit ouvert un port qui écoute, et fermé un port où rien n'écoute")
    func portScan() async throws {
        let server = try LocalServer(response: Data("bonjour".utf8))
        let openPort = try await server.start()
        defer { server.stop() }
        let closed = try closedPort()

        var states: [UInt16: PortState] = [:]
        let options = PortScanOptions(timeoutMilliseconds: 2_000, concurrency: 2)
        for try await event in TCPPortScanner().scan(host: "127.0.0.1", ports: [openPort, closed], options: options) {
            if case .result(let result) = event {
                states[result.port] = result.state
            }
        }
        #expect(states.count == 2)
        #expect(states[openPort] == .open)
        #expect(states[closed] == .closed)
    }

    @Test("Le scan refuse une liste de ports vide")
    func portScanWithoutPorts() async {
        var failure: PortScanError?
        do {
            for try await _ in TCPPortScanner().scan(host: "127.0.0.1", ports: [], options: PortScanOptions()) {}
        } catch let error as PortScanError {
            failure = error
        } catch {}
        #expect(failure == .noPorts)
    }

    @Test("La requête HTTP lit le code et le corps d'un serveur local")
    func httpProbe() async throws {
        let body = "ok"
        let text = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let server = try LocalServer(response: Data(text.utf8))
        let port = try await server.start()
        defer { server.stop() }

        let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))
        let result = try await URLSessionHTTPProbe().send(url: url, options: HTTPProbeOptions(timeoutSeconds: 5))
        #expect(result.statusCode == 200)
        #expect(result.bodyByteCount == 2)
        #expect(result.redirects.isEmpty)
    }

    @Test("Le ping de la boucle locale reçoit une réponse")
    func pingLoopback() async throws {
        var replies = 0
        let options = PingOptions(count: 2, intervalSeconds: 0.2, timeoutMilliseconds: 1_000)
        for try await event in ICMPPinger().ping(host: "127.0.0.1", options: options) {
            if case .reply = event {
                replies += 1
            }
        }
        #expect(replies == 2)
    }

    @Test("Le ping de la boucle locale en IPv6 reçoit une réponse")
    func pingLoopbackV6() async throws {
        var replies = 0
        var resolved: HostAddress?
        let options = PingOptions(count: 2, intervalSeconds: 0.2, timeoutMilliseconds: 1_000)
        for try await event in ICMPPinger().ping(host: "::1", options: options) {
            switch event {
            case .resolved(let address): resolved = address
            case .reply: replies += 1
            default: break
            }
        }
        #expect(resolved == HostAddress("::1"))
        #expect(replies == 2)
    }

    @Test("Une adresse IPv4 n'est pas jointe quand l'IPv6 est imposé")
    func familyMismatch() async {
        let options = PingOptions(count: 1, family: .ipv6)
        await #expect(throws: PingError.familyUnavailable(.ipv6)) {
            for try await _ in ICMPPinger().ping(host: "127.0.0.1", options: options) {}
        }
    }
}

@Suite("Freebox : autorités de certification")
struct FreeboxAuthoritiesTests {

    @Test("Les deux autorités de Free embarquées se lisent comme des certificats")
    func embeddedCertificates() {
        let certificates = FreeboxAuthorities.certificates()
        #expect(certificates.count == 2)
        let names = certificates.compactMap { SecCertificateCopySubjectSummary($0) as String? }
        #expect(names == ["Freebox ECC Root CA", "Freebox Root CA"])
    }

    @Test("Un texte qui n'est pas un certificat est refusé")
    func invalidPEM() {
        #expect(FreeboxAuthorities.certificate(fromPEM: "-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----") == nil)
        #expect(FreeboxAuthorities.certificate(fromPEM: "ceci n'est pas un certificat") == nil)
    }
}
