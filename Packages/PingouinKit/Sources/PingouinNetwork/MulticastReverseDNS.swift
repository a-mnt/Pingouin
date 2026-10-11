import dnssd
import Foundation
import PingouinCore

/// Recherche inverse par mDNS (Bonjour) : la question est posée directement sur le réseau local,
/// sans passer par le serveur DNS. Les Mac, iPhone, imprimantes, Apple TV et la plupart des
/// appareils Linux y répondent avec leur nom en « .local », même quand le routeur ne tient
/// aucune zone inverse.
enum MulticastReverseDNS {

    /// Porte le résultat entre la fonction de rappel C et l'appelant. Tout se passe sur le même fil
    /// d'exécution : la fonction de rappel n'est invoquée que depuis `DNSServiceProcessResult`.
    private final class ResultBox {
        var name: String?
    }

    /// Nom annoncé par l'appareil, ou `nil` s'il ne répond pas avant le délai. Appel **bloquant**.
    static func hostname(for address: IPAddressV4, timeoutMilliseconds: Int = 700) -> String? {
        let question = DNSWireName.reverseLookupName(for: address)
        let box = ResultBox()
        let context = Unmanaged.passUnretained(box).toOpaque()

        let reply: DNSServiceQueryRecordReply = { _, _, _, errorCode, _, _, _, dataLength, data, _, context in
            guard errorCode == DNSServiceErrorType(kDNSServiceErr_NoError), let data, let context else { return }
            let box = Unmanaged<ResultBox>.fromOpaque(context).takeUnretainedValue()
            let bytes = UnsafeRawBufferPointer(start: data, count: Int(dataLength))
            if let name = DNSWireName.decode(Array(bytes)) {
                box.name = name
            }
        }

        var service: DNSServiceRef?
        let status = DNSServiceQueryRecord(
            &service,
            DNSServiceFlags(kDNSServiceFlagsForceMulticast),
            0,
            question,
            UInt16(kDNSServiceType_PTR),
            UInt16(kDNSServiceClass_IN),
            reply,
            context
        )
        guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let service else { return nil }
        defer { DNSServiceRefDeallocate(service) }

        let descriptor = DNSServiceRefSockFD(service)
        guard descriptor >= 0 else { return nil }

        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeoutMilliseconds, 0)) * 1_000_000
        while box.name == nil {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            let remaining = Int32(min((deadline - now) / 1_000_000 + 1, 10_000))
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&pollDescriptor, 1, remaining) > 0 else { break }
            guard DNSServiceProcessResult(service) == DNSServiceErrorType(kDNSServiceErr_NoError) else { break }
        }
        return box.name
    }
}
