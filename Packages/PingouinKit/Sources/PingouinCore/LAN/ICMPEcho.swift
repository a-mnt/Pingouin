import Foundation

/// Construction et lecture des messages ICMP Echo (RFC 792), sans aucun accès réseau.
public enum ICMPEcho {
    public static let echoRequestType: UInt8 = 8
    public static let echoReplyType: UInt8 = 0

    /// Charge utile par défaut, renvoyée telle quelle par l'hôte distant : elle sert à reconnaître nos réponses.
    public static let defaultPayload: [UInt8] = Array("PINGOUIN".utf8)

    public struct Message: Equatable, Sendable {
        public let type: UInt8
        public let code: UInt8
        public let identifier: UInt16
        public let sequence: UInt16
        public let payload: [UInt8]

        public var isEchoReply: Bool { type == ICMPEcho.echoReplyType && code == 0 }
    }

    /// Somme de contrôle Internet (RFC 1071) : complément à un de la somme des mots de 16 bits.
    public static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }

    /// Message Echo Request complet, somme de contrôle incluse.
    public static func request(identifier: UInt16, sequence: UInt16, payload: [UInt8] = defaultPayload) -> [UInt8] {
        var packet: [UInt8] = [
            echoRequestType, 0,
            0, 0,
            UInt8(truncatingIfNeeded: identifier >> 8), UInt8(truncatingIfNeeded: identifier),
            UInt8(truncatingIfNeeded: sequence >> 8), UInt8(truncatingIfNeeded: sequence)
        ]
        packet.append(contentsOf: payload)
        let sum = checksum(packet)
        packet[2] = UInt8(truncatingIfNeeded: sum >> 8)
        packet[3] = UInt8(truncatingIfNeeded: sum)
        return packet
    }

    /// Message ICMP reçu, classé selon ce qu'il apprend à un ping ou à un traceroute.
    public enum Received: Equatable, Sendable {
        /// Réponse de l'hôte visé. `ttl` vient de l'en-tête IP quand il est présent.
        case echoReply(identifier: UInt16, sequence: UInt16, payload: [UInt8], ttl: UInt8?)
        /// Un routeur a jeté notre requête parce que sa durée de vie était épuisée (type 11).
        case timeExceeded(originalIdentifier: UInt16, originalSequence: UInt16)
        /// Un équipement signale que la destination est injoignable (type 3).
        case destinationUnreachable(code: UInt8, originalIdentifier: UInt16, originalSequence: UInt16)
        case other(type: UInt8)
    }

    /// Classe un datagramme reçu. Pour les messages d'erreur, retrouve l'identifiant et le numéro de
    /// séquence de notre requête, recopiée par l'émetteur à la suite de son message.
    /// Renvoie `nil` si le datagramme est tronqué ou incohérent.
    public static func classify(datagram: [UInt8]) -> Received? {
        var offset = 0
        var ttl: UInt8?
        if let first = datagram.first, first >> 4 == 4 {
            let headerLength = Int(first & 0x0F) * 4
            guard headerLength >= 20, datagram.count >= headerLength, datagram[9] == 1 else { return nil }
            ttl = datagram[8]
            offset = headerLength
        }
        guard datagram.count >= offset + 8 else { return nil }
        let type = datagram[offset]
        let code = datagram[offset + 1]

        func word(_ index: Int) -> UInt16 {
            UInt16(datagram[index]) << 8 | UInt16(datagram[index + 1])
        }

        switch type {
        case echoReplyType:
            return .echoReply(
                identifier: word(offset + 4),
                sequence: word(offset + 6),
                payload: Array(datagram[(offset + 8)...]),
                ttl: ttl
            )
        case 3, 11:
            // À la suite des 8 octets du message : l'en-tête IP de notre requête, puis ses 8 premiers octets.
            let inner = offset + 8
            guard datagram.count > inner, datagram[inner] >> 4 == 4 else { return nil }
            let innerHeaderLength = Int(datagram[inner] & 0x0F) * 4
            let original = inner + innerHeaderLength
            guard innerHeaderLength >= 20, datagram.count >= original + 8,
                  datagram[original] == echoRequestType else { return nil }
            let identifier = word(original + 4)
            let sequence = word(original + 6)
            if type == 11 {
                return .timeExceeded(originalIdentifier: identifier, originalSequence: sequence)
            }
            return .destinationUnreachable(code: code, originalIdentifier: identifier, originalSequence: sequence)
        default:
            return .other(type: type)
        }
    }

    // MARK: ICMPv6 (RFC 4443)

    public static let echoRequestTypeV6: UInt8 = 128
    public static let echoReplyTypeV6: UInt8 = 129

    /// Message Echo Request ICMPv6. La somme de contrôle est laissée à zéro : elle porte aussi sur les
    /// adresses du paquet, et c'est le système qui la calcule à l'envoi.
    public static func requestV6(identifier: UInt16, sequence: UInt16, payload: [UInt8] = defaultPayload) -> [UInt8] {
        [
            echoRequestTypeV6, 0,
            0, 0,
            UInt8(truncatingIfNeeded: identifier >> 8), UInt8(truncatingIfNeeded: identifier),
            UInt8(truncatingIfNeeded: sequence >> 8), UInt8(truncatingIfNeeded: sequence)
        ] + payload
    }

    /// Classe un message ICMPv6 reçu. Il arrive sans en-tête IP, donc sans durée de vie connue.
    /// Pour les messages d'erreur, la requête d'origine suit son en-tête IPv6 de 40 octets ;
    /// si cet en-tête est suivi d'extensions, le message n'est pas reconnu et `nil` est rendu.
    public static func classifyV6(datagram: [UInt8]) -> Received? {
        guard datagram.count >= 8 else { return nil }
        let type = datagram[0]
        let code = datagram[1]

        func word(_ index: Int) -> UInt16 {
            UInt16(datagram[index]) << 8 | UInt16(datagram[index + 1])
        }

        switch type {
        case echoReplyTypeV6:
            return .echoReply(identifier: word(4), sequence: word(6), payload: Array(datagram[8...]), ttl: nil)
        case 1, 3:
            // Type 1 : destination injoignable. Type 3 : nombre de sauts épuisé.
            let inner = 8
            let original = inner + 40
            guard datagram.count >= original + 8,
                  datagram[inner] >> 4 == 6,
                  datagram[inner + 6] == 58,
                  datagram[original] == echoRequestTypeV6 else { return nil }
            let identifier = word(original + 4)
            let sequence = word(original + 6)
            if type == 3 {
                return .timeExceeded(originalIdentifier: identifier, originalSequence: sequence)
            }
            return .destinationUnreachable(code: code, originalIdentifier: identifier, originalSequence: sequence)
        default:
            return .other(type: type)
        }
    }

    /// Lit un message ICMP reçu. macOS livre le datagramme avec son en-tête IPv4 : il est retiré s'il est présent.
    /// Renvoie `nil` si le datagramme est trop court ou si l'en-tête IP n'annonce pas de l'ICMP.
    public static func parse(datagram: [UInt8]) -> Message? {
        var offset = 0
        if let first = datagram.first, first >> 4 == 4 {
            let headerLength = Int(first & 0x0F) * 4
            guard headerLength >= 20, datagram.count >= headerLength, datagram[9] == 1 else { return nil }
            offset = headerLength
        }
        guard datagram.count >= offset + 8 else { return nil }
        return Message(
            type: datagram[offset],
            code: datagram[offset + 1],
            identifier: UInt16(datagram[offset + 4]) << 8 | UInt16(datagram[offset + 5]),
            sequence: UInt16(datagram[offset + 6]) << 8 | UInt16(datagram[offset + 7]),
            payload: Array(datagram[(offset + 8)...])
        )
    }
}
