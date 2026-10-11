import Foundation
import PingouinCore

/// Réponse d'un hôte au balayage ICMP.
public struct ICMPSweepReply: Hashable, Sendable {
    public let address: IPAddressV4
    public let roundTripMilliseconds: Double
}

public enum ICMPSweepError: Error, Equatable, Sendable {
    /// Le socket ICMP non privilégié n'a pas pu être ouvert.
    case socketUnavailable(code: Int32)
    /// Tous les envois ont été refusés avec « pas de route » : c'est le symptôme d'un accès
    /// au réseau local refusé par macOS (ou d'une interface déconnectée).
    case localNetworkUnreachable
}

/// Balayage ICMP Echo d'une liste d'adresses, sans privilèges (socket `SOCK_DGRAM`).
///
/// L'appel est **bloquant** : il doit être lancé hors de l'acteur principal et hors du pool
/// de tâches coopératif (voir `LANDiscoveryService`, qui l'exécute sur une file Dispatch).
struct ICMPSweeper {
    /// Nombre de passes d'envoi. La seconde ne vise que les hôtes restés muets.
    var rounds: UInt16 = 2
    /// Pause entre deux passes, en millisecondes.
    var pauseBetweenRoundsMilliseconds: Int32 = 250
    /// Nombre d'envois entre deux lectures du socket. Sert aussi à étaler la charge.
    var burstSize = 8

    func run(
        targets: [IPAddressV4],
        replyTimeout: TimeInterval,
        isCancelled: () -> Bool,
        onProgress: (Double) -> Void,
        onReply: (ICMPSweepReply) -> Void
    ) throws -> [ICMPSweepReply] {
        guard !targets.isEmpty else { return [] }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { throw ICMPSweepError.socketUnavailable(code: errno) }
        defer { close(descriptor) }

        let currentFlags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)

        let identifier = UInt16(truncatingIfNeeded: getpid())
        let targetSet = Set(targets.map(\.rawValue))
        var sendTimes: [UInt64: UInt64] = [:]
        var replied: Set<UInt32> = []
        var replies: [ICMPSweepReply] = []
        var buffer = [UInt8](repeating: 0, count: 2048)
        var successfulSends = 0
        var unreachableSends = 0

        func key(_ address: UInt32, _ sequence: UInt16) -> UInt64 {
            UInt64(address) << 16 | UInt64(sequence)
        }

        // Lit toutes les réponses disponibles, après une attente d'au plus `waitMilliseconds`.
        func drain(waitMilliseconds: Int32) {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&pollDescriptor, 1, waitMilliseconds) > 0 else { return }
            while true {
                var source = sockaddr_in()
                var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
                let received = buffer.withUnsafeMutableBytes { raw in
                    withUnsafeMutablePointer(to: &source) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                            recvfrom(descriptor, raw.baseAddress, raw.count, 0, generic, &sourceLength)
                        }
                    }
                }
                guard received > 0 else { return }
                let now = DispatchTime.now().uptimeNanoseconds

                guard let message = ICMPEcho.parse(datagram: Array(buffer[0..<received])),
                      message.isEchoReply,
                      message.payload.starts(with: ICMPEcho.defaultPayload) else { continue }

                let address = UInt32(bigEndian: source.sin_addr.s_addr)
                guard targetSet.contains(address), !replied.contains(address),
                      let sentAt = sendTimes[key(address, message.sequence)], now >= sentAt else { continue }

                replied.insert(address)
                let reply = ICMPSweepReply(
                    address: IPAddressV4(rawValue: address),
                    roundTripMilliseconds: Double(now - sentAt) / 1_000_000
                )
                replies.append(reply)
                onReply(reply)
            }
        }

        // Envoie une requête. Renvoie 0 en cas de succès, sinon le code d'erreur système.
        func send(to target: IPAddressV4, sequence: UInt16) -> Int32 {
            let packet = ICMPEcho.request(identifier: identifier, sequence: sequence)
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_addr = in_addr(s_addr: target.rawValue.bigEndian)

            sendTimes[key(target.rawValue, sequence)] = DispatchTime.now().uptimeNanoseconds
            let sent = packet.withUnsafeBytes { raw in
                withUnsafePointer(to: destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        sendto(descriptor, raw.baseAddress, raw.count, 0, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            return sent < 0 ? errno : 0
        }

        let totalSends = Double(targets.count) * Double(rounds)
        var attempted = 0.0

        for round in 1...rounds {
            var sinceLastDrain = 0
            for target in targets {
                if isCancelled() { throw CancellationError() }
                attempted += 1
                guard !replied.contains(target.rawValue) else { continue }

                var code = send(to: target, sequence: round)
                if code == ENOBUFS {
                    // File d'émission pleine : on laisse le système respirer puis on réessaie une fois.
                    drain(waitMilliseconds: 20)
                    code = send(to: target, sequence: round)
                }
                if code == 0 {
                    successfulSends += 1
                } else if code == EHOSTUNREACH || code == ENETUNREACH || code == EHOSTDOWN {
                    unreachableSends += 1
                }

                sinceLastDrain += 1
                if sinceLastDrain >= burstSize {
                    sinceLastDrain = 0
                    drain(waitMilliseconds: 4)
                    onProgress(attempted / totalSends)
                }
            }
            onProgress(attempted / totalSends)

            // Un envoi peut réussir même sans accès au réseau local : celui vers l'adresse de ce Mac.
            let expectedLocalSuccesses = targets.count > 1 ? 1 : 0
            if round == 1, unreachableSends > 0, successfulSends <= expectedLocalSuccesses {
                throw ICMPSweepError.localNetworkUnreachable
            }
            if round < rounds {
                var waited: Int32 = 0
                while waited < pauseBetweenRoundsMilliseconds {
                    if isCancelled() { throw CancellationError() }
                    drain(waitMilliseconds: 50)
                    waited += 50
                }
            }
        }

        // Attente finale des réponses tardives.
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, replyTimeout) * 1_000_000_000)
        while DispatchTime.now().uptimeNanoseconds < deadline, replied.count < targets.count {
            if isCancelled() { throw CancellationError() }
            drain(waitMilliseconds: 50)
        }
        return replies
    }
}
