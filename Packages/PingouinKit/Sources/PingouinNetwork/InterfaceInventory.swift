import Foundation
import PingouinCore

/// Inventaire des interfaces locales, lu avec `getifaddrs`.
public enum InterfaceInventory {

    /// Interfaces actives disposant d'une adresse IPv4, hors bouclage et liaisons point à point (VPN).
    public static func ipv4Interfaces() -> [LocalInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var result: [LocalInterface] = []
        var cursor = head
        while let current = cursor {
            cursor = current.pointee.ifa_next

            let flags = Int32(bitPattern: current.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }
            guard flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0 else { continue }

            guard let addressPointer = current.pointee.ifa_addr,
                  let maskPointer = current.pointee.ifa_netmask,
                  Int32(addressPointer.pointee.sa_family) == AF_INET else { continue }

            let addressValue = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let maskValue = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }

            let address = IPAddressV4(rawValue: addressValue)
            guard let prefix = IPv4Subnet.prefixLength(forMask: IPAddressV4(rawValue: maskValue)),
                  let subnet = IPv4Subnet(address: address, prefixLength: prefix) else { continue }

            let name = String(cString: current.pointee.ifa_name)
            result.append(LocalInterface(name: name, address: address, subnet: subnet))
        }
        return result.sorted { $0.name < $1.name }
    }

    /// Adresses IPv6 d'une interface, hors adresses de liaison locale (fe80::/10).
    public static func ipv6Addresses(interfaceName: String) -> [IPAddressV6] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var result: Set<IPAddressV6> = []
        var cursor = head
        while let current = cursor {
            cursor = current.pointee.ifa_next
            guard String(cString: current.pointee.ifa_name) == interfaceName,
                  let addressPointer = current.pointee.ifa_addr,
                  Int32(addressPointer.pointee.sa_family) == AF_INET6 else { continue }
            let address = addressPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                SocketAddressV6.address(from: $0.pointee)
            }
            if address.rawValue >> 118 != 0x3FA {
                result.insert(address)
            }
        }
        return result.sorted()
    }
}
