import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Phase de la décomposition du temps, avec sa position sur l'axe pour le dessin en cascade.
struct HTTPPhaseRow: Identifiable, Hashable {
    let id: String
    let label: String
    let milliseconds: Double
    /// Début et longueur de la phase, rapportés à la somme des phases (de 0 à 1).
    let offset: Double
    let length: Double
    let isLongest: Bool
}

struct HTTPHeaderRow: Identifiable, Hashable {
    let id: Int
    let name: String
    let value: String
}

struct HTTPRedirectRow: Identifiable, Hashable {
    let id: Int
    let statusCode: String
    let url: String
    let note: String
}

@MainActor
@Observable
final class HTTPViewModel {
    private let probe: any HTTPProbing

    var urlText = ""
    var method = "GET"
    var followRedirects = true
    var maximumRedirectsText = "5"
    var headerSelection: Set<Int> = []

    private(set) var isRunning = false
    private(set) var status: ToolStatusLine.Content = .hint(L("Saisir une URL, puis envoyer la requête."))
    private(set) var statusCodeText = "—"
    private(set) var statusKind: StatusKind = .neutral
    private(set) var totalTimeText = "—"
    private(set) var sizeText = "—"
    private(set) var protocolText = "—"
    private(set) var phases: [HTTPPhaseRow] = []
    private(set) var redirects: [HTTPRedirectRow] = []
    private(set) var headers: [HTTPHeaderRow] = []
    private(set) var history: [HistoryEntry] = []
    private var task: Task<Void, Never>?
    private var generation = 0

    init(probe: any HTTPProbing = URLSessionHTTPProbe()) {
        self.probe = probe
    }

    var hasResult: Bool { statusCodeText != "—" }

    var resultAsText: String {
        var lines = [L("Code\t\(statusCodeText)"), L("Temps total\t\(totalTimeText)"), L("Taille\t\(sizeText)"), L("Protocole\t\(protocolText)"), ""]
        lines += redirects.map { "\($0.statusCode)\t\($0.url)\t\($0.note)" }
        lines.append("")
        lines += headers.map { "\($0.name): \($0.value)" }
        return lines.joined(separator: "\n")
    }

    func header(id: Int) -> HTTPHeaderRow? {
        headers.first { $0.id == id }
    }

    // MARK: Lancement

    /// Lance aussitôt une requête vers une URL fournie par un autre outil.
    func launch(url: String) {
        urlText = url
        start()
    }

    func start() {
        guard let url = HTTPTarget.url(from: urlText) else {
            status = .failure(L("URL non valide. Attendu : une adresse en http:// ou https://, par exemple https://example.com/."))
            return
        }
        guard let maximum = NumberInput.integer(maximumRedirectsText), (0...20).contains(maximum) else {
            status = .failure(L("Le nombre maximal de redirections doit être compris entre 0 et 20."))
            return
        }

        task?.cancel()
        generation += 1
        let current = generation
        clearResult()
        isRunning = true
        status = .progress(L("Requête en cours"), fraction: nil)
        let options = HTTPProbeOptions(method: method, followRedirects: followRedirects, maximumRedirects: maximum)

        task = Task {
            defer {
                if current == generation { isRunning = false }
            }
            do {
                let result = try await probe.send(url: url, options: options)
                guard current == generation, !Task.isCancelled else { return }
                show(result, requested: url.absoluteString)
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
        status = .hint(L("Requête annulée."))
    }

    private func clearResult() {
        statusCodeText = "—"
        statusKind = .neutral
        totalTimeText = "—"
        sizeText = "—"
        protocolText = "—"
        phases = []
        redirects = []
        headers = []
        headerSelection = []
    }

    // MARK: Présentation

    private func show(_ result: HTTPProbeResult, requested: String) {
        statusCodeText = "\(result.statusCode) \(Self.reason(for: result.statusCode))"
        switch result.statusCode {
        case 200..<300: statusKind = .ok
        case 300..<400: statusKind = .warning
        default: statusKind = .failure
        }
        totalTimeText = result.totalMilliseconds.formatted(.number.precision(.fractionLength(0))) + " ms"
        sizeText = Int64(result.bodyByteCount).formatted(.byteCount(style: .file))
        protocolText = result.protocolName ?? "—"

        if let timing = result.timing {
            phases = Self.phaseRows(timing)
        }

        var rows: [HTTPRedirectRow] = result.redirects.enumerated().map { index, hop in
            HTTPRedirectRow(
                id: index,
                statusCode: String(hop.statusCode),
                url: hop.url,
                note: hop.followed ? L("Redirige vers \(hop.location)") : L("Redirection vers \(hop.location), non suivie")
            )
        }
        rows.append(HTTPRedirectRow(id: rows.count, statusCode: String(result.statusCode), url: result.finalURL, note: L("Réponse finale")))
        redirects = rows

        headers = result.headers.enumerated().map { index, header in
            HTTPHeaderRow(id: index, name: header.name, value: header.value)
        }

        let followed = result.redirects.filter(\.followed).count
        var summary = L("Réponse \(result.statusCode) en \(totalTimeText)")
        if followed > 0 {
            summary += L(count: followed, one: ", après \(followed) redirection", other: ", après \(followed) redirections")
        }
        status = statusKind == .failure ? .warning(summary + ".") : .done(summary + ".")
        history.insert(HistoryEntry(text: "\(method) \(requested) · \(result.statusCode)", target: requested), at: 0)
    }

    private static func phaseRows(_ timing: HTTPTimingBreakdown) -> [HTTPPhaseRow] {
        let entries: [(String, Double?)] = [
            (L("Résolution DNS"), timing.dnsLookup),
            (L("Connexion TCP"), timing.tcpConnect),
            (L("Négociation TLS"), timing.tlsHandshake),
            (L("Premier octet"), timing.firstByte),
            (L("Transfert"), timing.transfer)
        ]
        let measured = entries.compactMap { entry in entry.1.map { (entry.0, $0) } }
        let total = measured.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        let longest = measured.map(\.1).max() ?? 0

        var rows: [HTTPPhaseRow] = []
        var cursor = 0.0
        for (label, value) in measured {
            rows.append(HTTPPhaseRow(
                id: label,
                label: label,
                milliseconds: value,
                offset: cursor / total,
                length: value / total,
                isLongest: value == longest
            ))
            cursor += value
        }
        return rows
    }

    private static func reason(for statusCode: Int) -> String {
        switch statusCode {
        case 200: "OK"
        case 201: L("Créé")
        case 204: L("Sans contenu")
        case 301: L("Redirection permanente")
        case 302: L("Redirection temporaire")
        case 304: L("Non modifié")
        case 307: L("Redirection temporaire")
        case 308: L("Redirection permanente")
        case 400: L("Requête incorrecte")
        case 401: L("Authentification requise")
        case 403: L("Accès refusé")
        case 404: L("Introuvable")
        case 405: L("Méthode non autorisée")
        case 429: L("Trop de requêtes")
        case 500: L("Erreur du serveur")
        case 502: L("Passerelle incorrecte")
        case 503: L("Service indisponible")
        case 504: L("Délai de passerelle dépassé")
        default: ""
        }
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? HTTPProbeError else {
            return L("La requête a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .unsupportedMethod:
            return L("Cette méthode HTTP n'est pas prise en charge.")
        case .timedOut:
            return L("Délai dépassé : le serveur n'a pas répondu à temps.")
        case .hostNotFound:
            return L("Ce nom d'hôte est introuvable : la résolution DNS a échoué.")
        case .cannotConnect:
            return L("Connexion impossible : le serveur refuse la connexion ou le réseau est coupé.")
        case .secureConnectionFailed(let reason):
            return L("La connexion sécurisée a échoué : \(reason) L'outil TLS permet d'examiner le certificat.")
        case .notHTTPResponse:
            return L("Le serveur n'a pas répondu en HTTP.")
        case .other(let reason):
            return L("La requête a échoué : \(reason)")
        }
    }
}
