import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Certificat de la chaîne, prêt à afficher.
struct TLSCertificateRow: Identifiable, Hashable {
    let id: Int
    /// Rôle dans la chaîne : serveur, intermédiaire ou racine.
    let role: String
    let subject: String
    let validity: String
    let validityKind: StatusKind
}

/// Verdict affiché en tête de résultat.
struct TLSVerdict: Equatable {
    let kind: StatusKind
    let title: String
    let detail: String
}

@MainActor
@Observable
final class TLSViewModel {
    private let inspector: any TLSInspecting
    private static let timeoutSeconds = 10.0

    var hostText = ""
    var portText = "443"
    var serverName = ""

    private(set) var isRunning = false
    private(set) var status: ToolStatusLine.Content = .hint(L("Saisir un hôte, puis analyser."))
    private(set) var verdict: TLSVerdict?
    private(set) var trustText = "—"
    private(set) var trustKind: StatusKind = .neutral
    private(set) var hostnameText = "—"
    private(set) var expiryText = "—"
    private(set) var expiryKind: StatusKind = .neutral
    private(set) var protocolText = "—"
    private(set) var details: [SummaryRow] = []
    private(set) var chain: [TLSCertificateRow] = []
    private(set) var history: [HistoryEntry] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    init(inspector: any TLSInspecting = NetworkTLSInspector()) {
        self.inspector = inspector
    }

    var hasResult: Bool { !chain.isEmpty }

    var resultAsText: String {
        var lines: [String] = []
        if let verdict {
            lines.append(verdict.title)
            lines.append(verdict.detail)
            lines.append("")
        }
        lines += details.map { "\($0.label) : \($0.value)" }
        lines.append("")
        lines += chain.map { "\($0.role) : \($0.subject) (\($0.validity))" }
        return lines.joined(separator: "\n")
    }

    // MARK: Lancement

    /// Lance aussitôt une analyse sur une cible « hôte » ou « hôte:port » fournie par un autre outil.
    func launch(target: String) {
        if let parts = HostPort.split(target, defaultPort: 443) {
            hostText = parts.host
            portText = String(parts.port)
        } else {
            hostText = target
        }
        serverName = ""
        start()
    }

    func start() {
        // La saisie « hôte:port » dans le champ hôte l'emporte sur le champ port.
        guard let parts = HostPort.split(hostText, defaultPort: 0) else {
            status = .failure(L("Saisir un nom d'hôte ou une adresse IP."))
            return
        }
        var port = parts.port
        if port == 0 {
            guard let typed = NumberInput.integer(portText), (1...65_535).contains(typed) else {
                status = .failure(L("Le port doit être compris entre 1 et 65535."))
                return
            }
            port = UInt16(typed)
        }
        let host = parts.host
        let name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)

        task?.cancel()
        generation += 1
        let current = generation
        clearResult()
        isRunning = true
        status = .progress(L("Négociation avec \(host):\(port)"), fraction: nil)

        task = Task {
            defer {
                if current == generation { isRunning = false }
            }
            do {
                let result = try await inspector.inspect(
                    host: host,
                    port: port,
                    serverName: name.isEmpty ? nil : name,
                    timeoutSeconds: Self.timeoutSeconds
                )
                guard current == generation, !Task.isCancelled else { return }
                show(result)
            } catch {
                guard current == generation, !Task.isCancelled else { return }
                status = .failure(Self.message(for: error))
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        generation += 1
        isRunning = false
        status = .hint(L("Analyse annulée."))
    }

    private func clearResult() {
        verdict = nil
        trustText = "—"
        trustKind = .neutral
        hostnameText = "—"
        expiryText = "—"
        expiryKind = .neutral
        protocolText = "—"
        details = []
        chain = []
    }

    // MARK: Présentation

    private func show(_ result: TLSInspectionResult) {
        guard let leaf = result.chain.first else { return }
        let now = Date.now
        let expiry = CertificateExpiry.evaluate(notBefore: leaf.notBefore, notAfter: leaf.notAfter, now: now)
        let expiryLabel = Self.label(for: expiry)
        expiryText = expiryLabel.text
        expiryKind = expiryLabel.kind

        trustText = result.isTrusted ? L("Approuvé") : L("Refusé")
        trustKind = result.isTrusted ? .ok : .failure
        switch result.hostnameMismatch {
        case .some(false): hostnameText = L("Correspond")
        case .some(true): hostnameText = L("Ne correspond pas")
        case .none: hostnameText = L("Non vérifiable")
        }
        protocolText = result.negotiatedProtocol ?? "—"

        verdict = Self.verdict(result: result, expiry: expiry, leaf: leaf)

        details = [
            SummaryRow(label: L("Sujet"), value: leaf.subject),
            SummaryRow(label: L("Émetteur"), value: leaf.issuer),
            SummaryRow(label: L("Valide du"), value: Self.format(leaf.notBefore)),
            SummaryRow(label: L("Valide jusqu'au"), value: Self.format(leaf.notAfter)),
            SummaryRow(
                label: L("Noms couverts (SAN)"),
                value: leaf.subjectAlternativeNames.isEmpty ? "—" : leaf.subjectAlternativeNames.joined(separator: ", ")
            ),
            SummaryRow(label: L("Empreinte SHA-256"), value: leaf.sha256Fingerprint)
        ]

        chain = result.chain.enumerated().map { index, certificate in
            let role: String
            if index == 0 {
                role = L("Serveur")
            } else if index == result.chain.count - 1 {
                role = L("Racine ou dernier certificat présenté")
            } else {
                role = L("Intermédiaire")
            }
            let label = Self.label(for: CertificateExpiry.evaluate(
                notBefore: certificate.notBefore,
                notAfter: certificate.notAfter,
                now: now
            ))
            return TLSCertificateRow(
                id: index,
                role: role,
                subject: certificate.subject,
                validity: certificate.notAfter.map { L("Expire le ") + Self.format($0) } ?? L("Date d'expiration illisible"),
                validityKind: label.kind
            )
        }

        if let verdict {
            switch verdict.kind {
            case .ok: status = .done(verdict.title)
            case .warning: status = .warning(verdict.title)
            default: status = .failure(verdict.title)
            }
            history.insert(HistoryEntry(text: "\(result.host):\(result.port) · \(verdict.title)", target: "\(result.host):\(result.port)"), at: 0)
        }
    }

    private static func verdict(result: TLSInspectionResult, expiry: CertificateExpiry, leaf: CertificateSummary) -> TLSVerdict {
        if !result.isTrusted {
            let title: String
            if case .expired = expiry {
                title = L("Certificat expiré")
            } else if case .notYetValid = expiry {
                title = L("Certificat pas encore valide")
            } else if result.hostnameMismatch == true {
                title = L("Le certificat ne couvre pas ce nom d'hôte")
            } else {
                title = L("Chaîne de confiance invalide")
            }
            return TLSVerdict(
                kind: .failure,
                title: title,
                detail: result.trustFailureReason ?? L("\(Platform.systemName) n'accorde pas sa confiance à ce certificat.")
            )
        }
        if case .expiringSoon(let days) = expiry {
            return TLSVerdict(
                kind: .warning,
                title: L("Chaîne de confiance valide, mais le certificat expire dans \(days) jours"),
                detail: L("Le nom correspond et la chaîne remonte à une racine approuvée par \(Platform.systemName). Renouvellement à prévoir avant le \(format(leaf.notAfter)).")
            )
        }
        return TLSVerdict(
            kind: .ok,
            title: L("Chaîne de confiance valide"),
            detail: L("Le nom correspond et la chaîne remonte à une racine approuvée par \(Platform.systemName).")
        )
    }

    private static func label(for expiry: CertificateExpiry) -> (text: String, kind: StatusKind) {
        switch expiry {
        case .valid(let days):
            return (L("\(days) jours"), StatusKind.ok)
        case .expiringSoon(let days):
            return (L("\(days) jours"), StatusKind.warning)
        case .expired(let days):
            return (L("Expiré depuis \(days) jours"), StatusKind.failure)
        case .notYetValid:
            return (L("Pas encore valide"), StatusKind.failure)
        case .unknown:
            return (L("Inconnue"), StatusKind.neutral)
        }
    }

    private static func format(_ date: Date?) -> String {
        date?.formatted(date: .long, time: .omitted) ?? "—"
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? TLSInspectionError else {
            return L("L'analyse a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .invalidHost:
            return L("Le nom d'hôte ou le port n'est pas valide.")
        case .timedOut:
            return L("Délai dépassé : le serveur n'a pas terminé la négociation TLS à temps.")
        case .connectionFailed(let reason):
            return L("Connexion impossible : \(reason)")
        case .noCertificate:
            return L("Le serveur n'a présenté aucun certificat : ce port ne parle peut-être pas TLS.")
        }
    }
}
