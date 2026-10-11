import CryptoKit
import Foundation
import Network
import os
import PingouinCore
import Security

public struct CertificateSummary: Hashable, Sendable {
    /// Résumé du sujet, en général le nom commun.
    public let subject: String
    public let issuer: String
    public let notBefore: Date?
    public let notAfter: Date?
    public let subjectAlternativeNames: [String]
    /// Empreinte SHA-256 du certificat, en hexadécimal séparé par des deux-points.
    public let sha256Fingerprint: String

    public init(
        subject: String,
        issuer: String,
        notBefore: Date?,
        notAfter: Date?,
        subjectAlternativeNames: [String],
        sha256Fingerprint: String
    ) {
        self.subject = subject
        self.issuer = issuer
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.subjectAlternativeNames = subjectAlternativeNames
        self.sha256Fingerprint = sha256Fingerprint
    }
}

public struct TLSInspectionResult: Sendable {
    public let host: String
    public let port: UInt16
    /// Résultat de l'évaluation de confiance du système pour ce nom d'hôte.
    public let isTrusted: Bool
    /// Motif du refus rendu par le système, quand la confiance n'est pas accordée.
    public let trustFailureReason: String?
    /// Vrai si la chaîne est valide mais ne couvre pas le nom demandé ; `nil` si on ne peut pas le dire.
    public let hostnameMismatch: Bool?
    /// Version négociée, par exemple « TLS 1.3 ».
    public let negotiatedProtocol: String?
    /// Certificats présentés, du serveur vers la racine.
    public let chain: [CertificateSummary]

    public init(
        host: String,
        port: UInt16,
        isTrusted: Bool,
        trustFailureReason: String?,
        hostnameMismatch: Bool?,
        negotiatedProtocol: String?,
        chain: [CertificateSummary]
    ) {
        self.host = host
        self.port = port
        self.isTrusted = isTrusted
        self.trustFailureReason = trustFailureReason
        self.hostnameMismatch = hostnameMismatch
        self.negotiatedProtocol = negotiatedProtocol
        self.chain = chain
    }
}

public enum TLSInspectionError: Error, Equatable, Sendable {
    case invalidHost
    case timedOut
    case connectionFailed(String)
    /// La négociation n'a livré aucun certificat.
    case noCertificate
}

/// Contrat de l'inspecteur TLS, pour pouvoir l'injecter et le remplacer dans les tests.
public protocol TLSInspecting: Sendable {
    func inspect(host: String, port: UInt16, serverName: String?, timeoutSeconds: Double) async throws -> TLSInspectionResult
}

/// Inspection d'un serveur TLS : négociation, puis évaluation de la chaîne par le système.
///
/// La négociation est acceptée même si le certificat est invalide, **uniquement** pour pouvoir le
/// lire et l'expliquer : aucune donnée applicative n'est envoyée ni reçue, la connexion est fermée
/// aussitôt, et le verdict affiché est celui de l'évaluation de confiance normale du système.
public struct NetworkTLSInspector: TLSInspecting {
    public init() {}

    private final class TrustBox: @unchecked Sendable {
        private let lock = NSLock()
        private var trust: SecTrust?

        func store(_ value: SecTrust) {
            lock.withLock { trust = value }
        }

        func load() -> SecTrust? {
            lock.withLock { trust }
        }
    }

    private enum Handshake: Sendable {
        case ready
        case timedOut
        case failed(String)
    }

    public func inspect(host: String, port: UInt16, serverName: String?, timeoutSeconds: Double) async throws -> TLSInspectionResult {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HostInput.isPlausible(target), let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw TLSInspectionError.invalidHost
        }
        let presentedName = serverName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifiedName = (presentedName?.isEmpty == false ? presentedName : nil) ?? target

        let queue = DispatchQueue(label: "fr.a-mnt.pingouin.tls")
        let box = TrustBox()
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, trust, complete in
            box.store(sec_trust_copy_ref(trust).takeRetainedValue())
            complete(true)
        }, queue)
        if verifiedName != target {
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, verifiedName)
        }

        let connection = NWConnection(host: NWEndpoint.Host(target), port: endpointPort, using: NWParameters(tls: tlsOptions))
        let alreadyResumed = OSAllocatedUnfairLock(initialState: false)
        let timeout = Int(min(max(timeoutSeconds, 1), 60) * 1_000)

        let handshake: Handshake = await withCheckedContinuation { continuation in
            let finish: @Sendable (Handshake) -> Void = { outcome in
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
                    finish(.ready)
                case .waiting(let error), .failed(let error):
                    finish(.failed(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(timeout)) {
                finish(.timedOut)
            }
        }

        var negotiated: String?
        if case .ready = handshake,
           let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
            negotiated = Self.name(of: sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata.securityProtocolMetadata))
        }
        connection.stateUpdateHandler = nil
        connection.cancel()

        // Même si la négociation a échoué ensuite, un certificat reçu reste analysable.
        guard let trust = box.load() else {
            switch handshake {
            case .timedOut:
                throw TLSInspectionError.timedOut
            case .failed(let reason):
                throw TLSInspectionError.connectionFailed(reason)
            case .ready:
                throw TLSInspectionError.noCertificate
            }
        }

        let verdict = Self.evaluate(trust, host: verifiedName)
        let certificates = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        guard !certificates.isEmpty else { throw TLSInspectionError.noCertificate }

        return TLSInspectionResult(
            host: target,
            port: port,
            isTrusted: verdict.isTrusted,
            trustFailureReason: verdict.reason,
            hostnameMismatch: verdict.hostnameMismatch,
            negotiatedProtocol: negotiated,
            chain: certificates.map { Self.summarize($0) }
        )
    }

    // MARK: Confiance

    private static func evaluate(_ trust: SecTrust, host: String) -> (isTrusted: Bool, reason: String?, hostnameMismatch: Bool?) {
        // Évaluation normale : chaîne, dates, et correspondance avec le nom d'hôte.
        _ = SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            return (true, nil, false)
        }
        let reason = error.map { CFErrorCopyDescription($0) as String }

        // Seconde évaluation sans le nom : si elle réussit, c'est le nom seul qui pose problème.
        _ = SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        let chainIsValid = SecTrustEvaluateWithError(trust, nil)
        return (false, reason, chainIsValid ? true : nil)
    }

    private static func name(of version: tls_protocol_version_t) -> String {
        switch version {
        case .TLSv10: return "TLS 1.0"
        case .TLSv11: return "TLS 1.1"
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .DTLSv10: return "DTLS 1.0"
        case .DTLSv12: return "DTLS 1.2"
        @unknown default: return L("Version inconnue")
        }
    }

    // MARK: Certificat

    private static func summarize(_ certificate: SecCertificate) -> CertificateSummary {
        let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? "—"
        let data = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: data)
            .map { byte -> String in
                let digits = String(byte, radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }
            .joined(separator: ":")

        #if os(macOS)
        let keys = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter, kSecOIDX509V1IssuerName, kSecOIDSubjectAltName] as CFArray
        let values = (SecCertificateCopyValues(certificate, keys, nil) as? [String: Any]) ?? [:]

        func property(_ oid: CFString) -> Any? {
            (values[oid as String] as? [String: Any])?[kSecPropertyKeyValue as String]
        }
        func date(_ oid: CFString) -> Date? {
            (property(oid) as? NSNumber).map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) }
        }
        func entries(_ oid: CFString) -> [(label: String, value: String)] {
            guard let items = property(oid) as? [[String: Any]] else { return [] }
            return items.compactMap { item in
                guard let value = item[kSecPropertyKeyValue as String] as? String else { return nil }
                return (label: (item[kSecPropertyKeyLabel as String] as? String) ?? "", value: value)
            }
        }

        // L'émetteur est une liste d'attributs identifiés par leur OID : nom commun puis organisation.
        let issuerParts = entries(kSecOIDX509V1IssuerName)
        let commonName = issuerParts.first { $0.label == "2.5.4.3" }?.value
        let organization = issuerParts.first { $0.label == "2.5.4.10" }?.value
        let issuer = [commonName, organization].compactMap { $0 }.joined(separator: ", ")

        let alternativeNames = entries(kSecOIDSubjectAltName)
            .filter { $0.label.contains("DNS") || $0.label.contains("IP") }
            .map(\.value)

        return CertificateSummary(
            subject: subject,
            issuer: issuer.isEmpty ? "—" : issuer,
            notBefore: date(kSecOIDX509V1ValidityNotBefore),
            notAfter: date(kSecOIDX509V1ValidityNotAfter),
            subjectAlternativeNames: alternativeNames,
            sha256Fingerprint: fingerprint
        )
        #else
        // iOS n'offre pas la lecture des champs d'un certificat (`SecCertificateCopyValues`) :
        // dates, émetteur et noms couverts sont lus directement dans l'encodage du certificat.
        let fields = X509Reader.parse(der: [UInt8](data))
        let issuer = [fields?.issuerCommonName, fields?.issuerOrganization].compactMap { $0 }.joined(separator: ", ")
        return CertificateSummary(
            subject: subject,
            issuer: issuer.isEmpty ? "—" : issuer,
            notBefore: fields?.notBefore,
            notAfter: fields?.notAfter,
            subjectAlternativeNames: fields?.subjectAlternativeNames ?? [],
            sha256Fingerprint: fingerprint
        )
        #endif
    }
}
