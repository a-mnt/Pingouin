import Foundation
import PingouinCore

/// Recherche inverse de nom par le résolveur du système.
enum ReverseDNS {

    /// Nom associé à l'adresse, ou `nil` s'il n'y en a pas. Appel **bloquant**, qui peut durer
    /// plusieurs secondes quand le serveur DNS ne répond pas.
    static func hostname(for address: IPAddressV4) -> String? {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_addr = in_addr(s_addr: address.rawValue.bigEndian)

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = buffer.withUnsafeMutableBufferPointer { host in
            withUnsafePointer(to: socketAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    getnameinfo(
                        generic,
                        socklen_t(MemoryLayout<sockaddr_in>.size),
                        host.baseAddress,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NAMEREQD
                    )
                }
            }
        }
        guard status == 0 else { return nil }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let name = String(decoding: bytes, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    /// Nom associé à une adresse IPv4 ou IPv6. Appel **bloquant**, comme le précédent.
    static func hostname(for address: HostAddress) -> String? {
        switch address {
        case .v4(let address):
            return hostname(for: address)
        case .v6(let address):
            let socketAddress = SocketAddressV6.make(address, scopeID: 0)
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = buffer.withUnsafeMutableBufferPointer { host in
                withUnsafePointer(to: socketAddress) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        getnameinfo(
                            generic,
                            socklen_t(MemoryLayout<sockaddr_in6>.size),
                            host.baseAddress,
                            socklen_t(host.count),
                            nil,
                            0,
                            NI_NAMEREQD
                        )
                    }
                }
            }
            guard status == 0 else { return nil }
            let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let name = String(decoding: bytes, as: UTF8.self)
            return name.isEmpty ? nil : name
        }
    }

    /// Résout plusieurs adresses, par lots de `concurrency` recherches simultanées,
    /// sur une file Dispatch pour ne pas bloquer le pool de tâches coopératif.
    static func hostnames(
        for addresses: [IPAddressV4],
        concurrency: Int = 8,
        onResolved: @Sendable (IPAddressV4, String) -> Void
    ) async {
        let queue = DispatchQueue(label: "fr.a-mnt.pingouin.reverse-dns", qos: .utility, attributes: .concurrent)
        var index = 0
        while index < addresses.count {
            if Task.isCancelled { return }
            let batch = Array(addresses[index..<min(index + concurrency, addresses.count)])
            index += batch.count

            await withTaskGroup(of: (IPAddressV4, String?).self) { group in
                for address in batch {
                    group.addTask {
                        await withCheckedContinuation { continuation in
                            queue.async {
                                // Serveur DNS d'abord ; à défaut, question posée directement
                                // sur le réseau local (mDNS).
                                let name = ReverseDNS.hostname(for: address)
                                    ?? MulticastReverseDNS.hostname(for: address)
                                continuation.resume(returning: (address, name))
                            }
                        }
                    }
                }
                for await (address, name) in group {
                    if let name {
                        onResolved(address, name)
                    }
                }
            }
        }
    }
}
