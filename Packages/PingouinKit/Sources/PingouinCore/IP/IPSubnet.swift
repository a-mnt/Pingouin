import Foundation

/// Raisons pour lesquelles une saisie CIDR est refusée.
public enum IPParseError: Error, Equatable, Sendable {
    case empty
    case missingPrefix
    case invalidAddress
    case invalidPrefix(maximum: Int)
    case invalidMask
}

/// Réseau IPv4 ou IPv6 issu d'une saisie utilisateur.
public enum IPSubnet: Hashable, Sendable {
    case v4(IPv4Subnet)
    case v6(IPv6Subnet)

    /// Analyse « adresse/préfixe ». En IPv4, le préfixe peut aussi être un masque pointé
    /// (« 192.168.1.0/255.255.255.0 »). La famille est déduite de la présence de « : ».
    public static func parse(_ text: String) -> Result<IPSubnet, IPParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 1 { return .failure(.missingPrefix) }
        guard parts.count == 2 else { return .failure(.invalidAddress) }

        let addressText = parts[0].trimmingCharacters(in: .whitespaces)
        let suffix = parts[1].trimmingCharacters(in: .whitespaces)

        if addressText.contains(":") {
            guard let address = IPAddressV6(addressText) else { return .failure(.invalidAddress) }
            guard let prefix = decimalPrefix(suffix),
                  let subnet = IPv6Subnet(address: address, prefixLength: prefix) else {
                return .failure(.invalidPrefix(maximum: 128))
            }
            return .success(.v6(subnet))
        }

        guard let address = IPAddressV4(addressText) else { return .failure(.invalidAddress) }

        if suffix.contains(".") {
            guard let mask = IPAddressV4(suffix),
                  let prefix = IPv4Subnet.prefixLength(forMask: mask),
                  let subnet = IPv4Subnet(address: address, prefixLength: prefix) else {
                return .failure(.invalidMask)
            }
            return .success(.v4(subnet))
        }

        guard let prefix = decimalPrefix(suffix),
              let subnet = IPv4Subnet(address: address, prefixLength: prefix) else {
            return .failure(.invalidPrefix(maximum: 32))
        }
        return .success(.v4(subnet))
    }

    /// Lit un préfixe composé uniquement de chiffres ASCII (pas de signe, pas d'espace).
    static func decimalPrefix(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 3 else { return nil }
        guard text.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else { return nil }
        return Int(text)
    }
}
