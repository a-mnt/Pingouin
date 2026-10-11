import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Ligne du tableau des enregistrements.
struct DNSRecordRow: Identifiable, Hashable {
    let id: Int
    let name: String
    let type: String
    let ttl: String
    let value: String
}

/// Ligne de la comparaison entre serveurs.
struct DNSComparisonRow: Identifiable, Hashable {
    let id: String
    let server: String
    let status: String
    let statusKind: StatusKind
    let time: String
    let answer: String
}

/// Serveur à interroger.
enum DNSServerChoice: Hashable, Identifiable {
    case system
    case preset(String)
    case custom

    var id: String {
        switch self {
        case .system: "system"
        case .preset(let address): address
        case .custom: "custom"
        }
    }

    static let presets: [DNSServerChoice] = [.system, .preset("1.1.1.1"), .preset("9.9.9.9"), .preset("8.8.8.8"), .custom]
}

@MainActor
@Observable
final class DNSViewModel {
    private let client: any DNSQuerying
    private static let timeoutMilliseconds = 2_000

    var name = ""
    var type: DNSRecordType = .a
    var serverChoice: DNSServerChoice = .system
    var customServer = ""
    var selection: Set<Int> = []

    private(set) var isRunning = false
    private(set) var status: ToolStatusLine.Content = .hint(L("Saisir un nom de domaine ou une adresse IP, puis interroger."))
    private(set) var records: [DNSRecordRow] = []
    private(set) var comparison: [DNSComparisonRow] = []
    private(set) var isComparing = false
    private(set) var history: [HistoryEntry] = []
    private(set) var responseSummary = "—"
    private(set) var responseCode = "—"
    private(set) var responseTime = "—"
    private(set) var serverUsed = "—"
    private var task: Task<Void, Never>?
    private var generation = 0

    init(client: any DNSQuerying = UDPDNSClient()) {
        self.client = client
    }

    /// Premier serveur DNS du système, pour l'afficher dans le menu.
    var systemServerLabel: String {
        client.systemServers().first.map { L("Résolveur du système (\($0))") } ?? L("Résolveur du système")
    }

    func label(for choice: DNSServerChoice) -> String {
        switch choice {
        case .system: systemServerLabel
        case .preset(let address): address
        case .custom: L("Autre…")
        }
    }

    func row(id: Int) -> DNSRecordRow? {
        records.first { $0.id == id }
    }

    var recordsAsText: String {
        let header = L("Nom\tType\tTTL\tValeur")
        let lines = records.map { "\($0.name)\t\($0.type)\t\($0.ttl)\t\($0.value)" }
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: Lancement

    /// Lance aussitôt une recherche inverse (PTR) sur une adresse choisie dans un autre outil.
    func launchReverse(address: String) {
        name = address
        type = .ptr
        start()
    }

    func start() {
        let question = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            status = .failure(L("Saisir un nom de domaine ou une adresse IP."))
            return
        }
        let server: String?
        switch serverChoice {
        case .system:
            server = nil
        case .preset(let address):
            server = address
        case .custom:
            let text = customServer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard HostInput.isPlausible(text) else {
                status = .failure(L("Saisir l'adresse du serveur DNS à interroger."))
                return
            }
            server = text
        }

        task?.cancel()
        generation += 1
        let current = generation
        let requestedType = type
        records = []
        selection = []
        comparison = []
        isRunning = true
        status = .progress(L("Interrogation en cours"), fraction: nil)

        task = Task {
            defer {
                if current == generation { isRunning = false }
            }
            do {
                let result = try await client.query(
                    name: question,
                    type: requestedType,
                    server: server,
                    timeoutMilliseconds: Self.timeoutMilliseconds
                )
                guard current == generation, !Task.isCancelled else { return }
                show(result, question: question, type: requestedType)
            } catch {
                guard current == generation else { return }
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

    /// Pose la même question au résolveur du système et à deux résolveurs publics, en parallèle.
    func compareServers() {
        let question = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isComparing else { return }
        let requestedType = type
        let servers: [String?] = [nil, "1.1.1.1", "9.9.9.9"]
        let client = self.client
        let systemLabel = client.systemServers().first ?? L("Système")
        isComparing = true
        comparison = []

        Task {
            let rows = await withTaskGroup(of: (Int, DNSComparisonRow).self) { group in
                for (index, server) in servers.enumerated() {
                    group.addTask {
                        let label = server ?? systemLabel
                        do {
                            let result = try await client.query(
                                name: question,
                                type: requestedType,
                                server: server,
                                timeoutMilliseconds: 2_000
                            )
                            return (index, Self.comparisonRow(result))
                        } catch {
                            return (index, DNSComparisonRow(
                                id: label, server: label, status: L("Requête impossible"),
                                statusKind: .failure, time: "—", answer: ""
                            ))
                        }
                    }
                }
                var collected: [(Int, DNSComparisonRow)] = []
                for await item in group {
                    collected.append(item)
                }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }
            comparison = rows
            isComparing = false
        }
    }

    // MARK: Présentation

    private func show(_ result: DNSQueryResult, question: String, type: DNSRecordType) {
        serverUsed = result.server
        responseTime = result.milliseconds.map { NumberInput.milliseconds($0) } ?? "—"
        let description = Self.describe(result.outcome)
        responseCode = description.code
        responseSummary = description.summary

        var shown: [DNSRecord] = []
        switch result.outcome {
        case .answers(let list):
            shown = list
            status = .done(L("\(list.count) enregistrements reçus de \(result.server)."))
        case .truncated(let list):
            shown = list
            status = .warning(L("Réponse tronquée : elle ne tenait pas dans un datagramme UDP, la liste est incomplète."))
        case .noRecords:
            status = .done(L("Le nom existe, mais n'a aucun enregistrement \(type.name)."))
        case .nonexistentDomain:
            status = .warning(L("Ce nom de domaine n'existe pas."))
        case .serverFailure(let code):
            status = .failure(L("Le serveur \(result.server) a répondu par une erreur (code \(code))."))
        case .timedOut:
            status = .failure(L("Délai dépassé : \(result.server) n'a pas répondu en \(Self.timeoutMilliseconds.formatted()) ms."))
        case .networkError(let reason):
            status = .failure(L("Le serveur \(result.server) est injoignable : \(reason)"))
        case .malformedResponse:
            status = .failure(L("La réponse de \(result.server) est illisible."))
        }

        records = shown.enumerated().map { index, record in
            DNSRecordRow(
                id: index,
                name: record.name,
                type: record.typeName,
                ttl: "\(record.ttl.formatted()) s",
                value: record.value
            )
        }
        history.insert(HistoryEntry(text: "\(question) \(type.name) · \(description.summary.lowercased())", target: question), at: 0)
    }

    private nonisolated static func describe(_ outcome: DNSOutcome) -> (summary: String, code: String, kind: StatusKind) {
        switch outcome {
        case .answers(let list):
            return (L("\(list.count) enregistrements"), "NOERROR", .ok)
        case .truncated(let list):
            return (L("\(list.count) enregistrements (tronqué)"), "NOERROR", .warning)
        case .noRecords:
            return (L("Aucun enregistrement"), "NOERROR", .neutral)
        case .nonexistentDomain:
            return (L("Domaine inexistant"), "NXDOMAIN", .warning)
        case .serverFailure(let code):
            return (L("Échec du serveur"), code == 2 ? "SERVFAIL" : code == 5 ? "REFUSED" : L("Code \(code)"), .failure)
        case .timedOut:
            return (L("Délai dépassé"), "—", .warning)
        case .networkError:
            return (L("Serveur injoignable"), "—", .failure)
        case .malformedResponse:
            return (L("Réponse illisible"), "—", .failure)
        }
    }

    private nonisolated static func comparisonRow(_ result: DNSQueryResult) -> DNSComparisonRow {
        let description = describe(result.outcome)
        var answer = ""
        switch result.outcome {
        case .answers(let list), .truncated(let list):
            answer = list.map(\.value).joined(separator: ", ")
        default:
            break
        }
        return DNSComparisonRow(
            id: result.server,
            server: result.server,
            status: description.summary,
            statusKind: description.kind,
            time: result.milliseconds.map { $0.formatted(.number.precision(.fractionLength(1))) + " ms" } ?? "—",
            answer: answer
        )
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? DNSQueryError else {
            return L("La requête a échoué : \(error.localizedDescription)")
        }
        switch error {
        case .invalidName:
            return L("Ce nom ne peut pas être interrogé : il est vide, trop long, ou contient des caractères accentués (saisir alors sa forme « xn-- »).")
        case .invalidServer:
            return L("L'adresse du serveur DNS n'est pas valide.")
        case .noSystemServer:
            return L("Aucun serveur DNS n'a été trouvé dans la configuration du système. Choisir un serveur dans la liste.")
        }
    }
}
