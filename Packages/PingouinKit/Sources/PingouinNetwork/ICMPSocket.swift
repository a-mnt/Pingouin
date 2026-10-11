import Foundation
import PingouinCore

public enum HostResolutionError: Error, Equatable, Sendable {
    case notFound
    /// L'hôte existe, mais n'a pas d'adresse dans le protocole demandé.
    case familyUnavailable(IPFamilyChoice)
}

/// Destination d'un ping ou d'un traceroute : une adresse et, en IPv6, l'interface à emprunter.
struct ICMPTarget: Sendable, Equatable {
    let address: HostAddress
    /// Numéro de l'interface pour une adresse de liaison locale (« fe80::1%en0 »). 0 : sans objet.
    var scopeID: UInt32 = 0
}

/// Résolution d'un nom d'hôte en adresse par le résolveur du système.
enum HostResolver {

    /// Appel **bloquant**. Une adresse littérale est rendue telle quelle, sans requête DNS.
    static func resolve(_ host: String, family: IPFamilyChoice) -> Result<ICMPTarget, HostResolutionError> {
        if let literal = IPAddressV4(host) {
            return family == .ipv6 ? .failure(.familyUnavailable(.ipv6)) : .success(ICMPTarget(address: .v4(literal)))
        }
        // Adresse IPv6 littérale, zone comprise : `getaddrinfo` sait lire « fe80::1%en0 ».
        if host.contains(":") {
            guard let literal = lookup(host, family: AF_INET6, numericOnly: true) else { return .failure(.notFound) }
            return family == .ipv4 ? .failure(.familyUnavailable(.ipv4)) : .success(literal)
        }

        let families: [Int32]
        switch family {
        case .automatic: families = [AF_INET, AF_INET6]
        case .ipv4: families = [AF_INET]
        case .ipv6: families = [AF_INET6]
        }
        for candidate in families {
            if let target = lookup(host, family: candidate, numericOnly: false) {
                return .success(target)
            }
        }
        // Le nom existe peut-être dans l'autre protocole : le dire vaut mieux que « introuvable ».
        if family != .automatic, lookup(host, family: family == .ipv4 ? AF_INET6 : AF_INET, numericOnly: false) != nil {
            return .failure(.familyUnavailable(family))
        }
        return .failure(.notFound)
    }

    private static func lookup(_ host: String, family: Int32, numericOnly: Bool) -> ICMPTarget? {
        var hints = addrinfo()
        hints.ai_family = family
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_flags = numericOnly ? AI_NUMERICHOST : 0
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return nil }
        defer { freeaddrinfo(list) }
        guard let pointer = first.pointee.ai_addr else { return nil }

        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            let value = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            return ICMPTarget(address: .v4(IPAddressV4(rawValue: value)))
        case AF_INET6:
            return pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                ICMPTarget(address: .v6(SocketAddressV6.address(from: $0.pointee)), scopeID: $0.pointee.sin6_scope_id)
            }
        default:
            return nil
        }
    }
}

/// Passage entre `IPAddressV6` et la structure d'adresse IPv6 du système.
enum SocketAddressV6 {
    static func address(from socketAddress: sockaddr_in6) -> IPAddressV6 {
        var value: UInt128 = 0
        withUnsafeBytes(of: socketAddress.sin6_addr) { bytes in
            for byte in bytes {
                value = (value << 8) | UInt128(byte)
            }
        }
        return IPAddressV6(rawValue: value)
    }

    static func make(_ address: IPAddressV6, scopeID: UInt32) -> sockaddr_in6 {
        var result = sockaddr_in6()
        result.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        result.sin6_family = sa_family_t(AF_INET6)
        result.sin6_scope_id = scopeID
        withUnsafeMutableBytes(of: &result.sin6_addr) { bytes in
            for index in 0..<16 {
                bytes[index] = UInt8(truncatingIfNeeded: address.rawValue >> UInt128((15 - index) * 8))
            }
        }
        return result
    }
}

enum ICMPSocketError: Error, Equatable {
    case unavailable(code: Int32)
}

/// Socket ICMP non privilégié (`SOCK_DGRAM`), en IPv4 ou en IPv6, partagé par le ping et le traceroute.
///
/// Non protégé contre les accès concurrents : chaque instance est créée et utilisée
/// sur un seul fil d'exécution.
final class ICMPSocket {
    let isIPv6: Bool
    private let descriptor: Int32
    private var buffer = [UInt8](repeating: 0, count: 2048)
    let identifier = UInt16(truncatingIfNeeded: getpid())

    init(ipv6: Bool = false) throws {
        isIPv6 = ipv6
        descriptor = ipv6
            ? socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
            : socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { throw ICMPSocketError.unavailable(code: errno) }
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    deinit {
        if descriptor >= 0 {
            close(descriptor)
        }
    }

    /// Fixe la durée de vie des paquets émis (TTL en IPv4, nombre de sauts en IPv6).
    /// Renvoie faux si le système refuse.
    func setTimeToLive(_ ttl: Int) -> Bool {
        var value = Int32(ttl)
        let size = socklen_t(MemoryLayout<Int32>.size)
        if isIPv6 {
            return setsockopt(descriptor, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &value, size) == 0
        }
        return setsockopt(descriptor, IPPROTO_IP, IP_TTL, &value, size) == 0
    }

    /// Envoie une requête Echo. Renvoie 0 en cas de succès, sinon le code d'erreur système.
    /// Une destination de l'autre protocole que celui du socket est refusée (EAFNOSUPPORT).
    func sendEcho(to target: ICMPTarget, sequence: UInt16) -> Int32 {
        switch target.address {
        case .v4(let address):
            guard !isIPv6 else { return EAFNOSUPPORT }
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_addr = in_addr(s_addr: address.rawValue.bigEndian)
            return send(ICMPEcho.request(identifier: identifier, sequence: sequence), to: destination)
        case .v6(let address):
            guard isIPv6 else { return EAFNOSUPPORT }
            let destination = SocketAddressV6.make(address, scopeID: target.scopeID)
            return send(ICMPEcho.requestV6(identifier: identifier, sequence: sequence), to: destination)
        }
    }

    private func send<Address>(_ packet: [UInt8], to destination: Address) -> Int32 {
        let sent = packet.withUnsafeBytes { raw in
            withUnsafePointer(to: destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    sendto(descriptor, raw.baseAddress, raw.count, 0, generic, socklen_t(MemoryLayout<Address>.size))
                }
            }
        }
        return sent < 0 ? errno : 0
    }

    /// Attend au plus `waitMilliseconds` et rend le premier datagramme reçu, avec son émetteur.
    func receive(waitMilliseconds: Int32) -> (datagram: [UInt8], source: HostAddress)? {
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, max(waitMilliseconds, 0)) > 0 else { return nil }

        var source = sockaddr_storage()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let received = buffer.withUnsafeMutableBytes { raw in
            withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    recvfrom(descriptor, raw.baseAddress, raw.count, 0, generic, &sourceLength)
                }
            }
        }
        guard received > 0 else { return nil }

        let address: HostAddress
        switch Int32(source.ss_family) {
        case AF_INET:
            address = withUnsafePointer(to: source) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    HostAddress.v4(IPAddressV4(rawValue: UInt32(bigEndian: $0.pointee.sin_addr.s_addr)))
                }
            }
        case AF_INET6:
            address = withUnsafePointer(to: source) { pointer in
                pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    HostAddress.v6(SocketAddressV6.address(from: $0.pointee))
                }
            }
        default:
            return nil
        }
        return (Array(buffer[0..<received]), address)
    }

    /// Classe un datagramme reçu, selon le protocole du socket.
    func classify(_ datagram: [UInt8]) -> ICMPEcho.Received? {
        isIPv6 ? ICMPEcho.classifyV6(datagram: datagram) : ICMPEcho.classify(datagram: datagram)
    }
}

/// Horloge monotone en millisecondes, pour mesurer des durées.
func monotonicMilliseconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
}
