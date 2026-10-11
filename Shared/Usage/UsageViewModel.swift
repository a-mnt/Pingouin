import Foundation
import Observation
import PingouinCore
import PingouinNetwork

/// Consommation de données par appareil, relevée auprès de la box.
/// Les relevés ne sont pris que lorsque l'application est ouverte : rien n'est compté le reste du temps.
@MainActor
@Observable
final class UsageViewModel {
    /// Écart entre deux relevés, en secondes, d'après les réglages.
    private(set) var pollSeconds = AppSettings.usagePollSeconds
    private var keptDays = AppSettings.usageKeptDays
    private static let tokenAccount = "freebox:app_token"
    private static let approvalTimeoutSeconds = 150

    private let store = JSONStore<UsageLedger>(fileName: "consommation")
    private var client = FreeboxClient(usesHTTPS: AppSettings.freeboxUsesHTTPS)

    private(set) var connection: UsageConnection = .disconnected
    var period: UsagePeriod = .session
    var isChoosingSource = false
    private(set) var lastReading: Date?
    private(set) var isRefreshing = false
    /// Message sur le dernier relevé, quand il a échoué en tout ou partie alors que la box est connectée.
    private(set) var readingError: String?
    /// Nombre d'appareils et de ports rendus par le dernier relevé réussi.
    private(set) var lastReadingCount = 0
    private(set) var diagnosticMessage: String?

    private var ledger = UsageLedger()
    private var tracker = UsageTracker()
    private var endpoint: FreeboxEndpoint?
    private var sessionToken: String?
    private var pollTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var unsavedReadings = 0

    init() {
        ledger = store.load() ?? UsageLedger()
        // Un accès déjà accordé est repris sans rien redemander.
        if KeychainStore.hasPassword(account: Self.tokenAccount) {
            resume()
        }
    }

    // MARK: Lecture

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    var isBusy: Bool {
        connection == .connecting || connection == .awaitingApproval
    }

    private var displayedTotals: [String: UsageCounters] {
        switch period {
        case .session: tracker.sessionTotals
        case .today: ledger.totals(days: [Self.dayKey(Date())])
        case .week: ledger.totals(days: Self.lastDayKeys(7))
        }
    }

    var rows: [UsageRow] {
        let totals = displayedTotals
        let sum = totals.values.reduce(UInt64(0)) { $0 &+ $1.total }
        return totals
            .sorted { left, right in
                left.value.total != right.value.total ? left.value.total > right.value.total : left.key < right.key
            }
            .flatMap { key, counters -> [UsageRow] in
                let info = ledger.devices[key] ?? UsageDeviceInfo(name: key, link: "")
                let share = sum > 0 ? Double(counters.total) / Double(sum) : 0
                let rate = tracker.rates[key]
                let isPresent = tracker.presentKeys.contains(key)
                // Sous un port partagé, chaque appareil a sa ligne, sans volume : la box ne le mesure pas.
                var members: [UsageRow] = []
                if info.isShared {
                    let addresses = info.memberAddresses ?? []
                    for (index, member) in info.members.enumerated() {
                        members.append(UsageRow(
                            id: "\(key)#\(index)",
                            name: member,
                            detail: index < addresses.count ? addresses[index] : "",
                            isShared: false,
                            link: L("Derrière « \(info.name) »"),
                            received: "—",
                            sent: "—",
                            share: 0,
                            shareText: L("non mesuré"),
                            rate: "—",
                            isPresent: isPresent,
                            isMember: true
                        ))
                    }
                }
                let parent = UsageRow(
                    id: key,
                    name: info.name,
                    detail: info.isShared ? L("\(info.members.count) appareils, mesurés ensemble") : info.address,
                    isShared: info.isShared,
                    link: info.link,
                    received: ByteFormat.volume(counters.received),
                    sent: ByteFormat.volume(counters.sent),
                    share: share,
                    shareText: Self.percent(share, hasTraffic: counters.total > 0),
                    rate: rate.map { ByteFormat.rate($0.total) } ?? "—",
                    isPresent: isPresent
                )
                return [parent] + members
            }
    }

    var totalReceived: String {
        ByteFormat.volume(displayedTotals.values.reduce(UInt64(0)) { $0 &+ $1.received })
    }

    var totalSent: String {
        ByteFormat.volume(displayedTotals.values.reduce(UInt64(0)) { $0 &+ $1.sent })
    }

    /// Appareils et ports présents dans le dernier relevé.
    var measuredCount: Int { tracker.presentKeys.count }

    var currentRate: String {
        guard !tracker.rates.isEmpty else { return "—" }
        return ByteFormat.rate(tracker.rates.values.reduce(UInt64(0)) { $0 &+ $1.total })
    }

    /// Nom de la box connectée, s'il y en a une.
    var boxName: String? {
        if case .connected(let name) = connection { return name }
        return nil
    }

    /// Appareils présents dans le dernier relevé, avec l'endroit où la box les voit.
    /// Sert à la topologie pour tracer les relations constatées.
    var observedAttachments: [ObservedAttachment] {
        var result: [ObservedAttachment] = []
        for key in tracker.presentKeys.sorted() {
            guard let info = ledger.devices[key] else { continue }
            if info.isShared {
                let addresses = info.memberAddresses ?? []
                for (index, member) in info.members.enumerated() where index < addresses.count {
                    result.append(ObservedAttachment(name: member, address: addresses[index], via: info.name))
                }
            } else {
                // Un appareil Wi-Fi est vu sur sa bande ; un appareil seul sur un port est vu sur ce port.
                let via = key.hasPrefix("port:") ? L("Port Ethernet \(key.dropFirst(5))") : info.link
                result.append(ObservedAttachment(name: info.name, address: info.address, via: via))
            }
        }
        return result.filter { !$0.address.isEmpty }
    }

    var rowsAsText: String {
        let header = L("Appareil\tDétail\tLiaison\tReçu\tEnvoyé\tPart\tDébit")
        let lines = rows.map { "\($0.name)\t\($0.detail)\t\($0.link)\t\($0.received)\t\($0.sent)\t\($0.shareText)\t\($0.rate)" }
        return ([header] + lines).joined(separator: "\n")
    }

    // MARK: Connexion

    /// Demande l'accès à la Freebox : la box affiche la demande, à valider sur place.
    func connectFreebox() {
        guard !isBusy else { return }
        isChoosingSource = false
        connection = .connecting
        connectTask = Task {
            do {
                let endpoint = try await client.discover()
                let authorization = try await client.requestAuthorization(
                    endpoint: endpoint,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                    deviceName: Platform.deviceName
                )
                connection = .awaitingApproval
                var granted = false
                for _ in 0..<Self.approvalTimeoutSeconds {
                    try await Task.sleep(for: .seconds(1))
                    let state = try await client.authorizationState(endpoint: endpoint, trackID: authorization.trackID)
                    if state == .pending { continue }
                    if state == .granted {
                        granted = true
                    } else if state == .denied {
                        connection = .failed(message: L("L'accès a été refusé sur la Freebox."))
                    } else {
                        connection = .failed(message: L("Personne n'a validé la demande sur la Freebox à temps."))
                    }
                    break
                }
                guard granted else {
                    if connection == .awaitingApproval {
                        connection = .failed(message: L("Personne n'a validé la demande sur la Freebox à temps."))
                    }
                    return
                }
                guard KeychainStore.setPassword(authorization.appToken, account: Self.tokenAccount, label: L("Pingouin — accès à la Freebox")) else {
                    connection = .failed(message: L("L'accès est accordé, mais le Trousseau a refusé d'enregistrer le jeton."))
                    return
                }
                try await open(endpoint: endpoint, appToken: authorization.appToken)
            } catch is CancellationError {
                connection = .disconnected
            } catch {
                connection = .failed(message: Self.message(for: error))
                AppLog.shared.error("Consommation", "Connexion à la box en échec : " + Self.message(for: error))
            }
        }
    }

    /// Abandonne une demande d'accès en cours.
    func cancelConnecting() {
        connectTask?.cancel()
    }

    /// Oublie l'accès : le jeton est retiré du Trousseau. L'historique déjà relevé est conservé.
    func forgetAccess() {
        connectTask?.cancel()
        pollTask?.cancel()
        pollTask = nil
        KeychainStore.deletePassword(account: Self.tokenAccount)
        endpoint = nil
        sessionToken = nil
        tracker = UsageTracker()
        lastReading = nil
        readingError = nil
        connection = .disconnected
    }

    /// Reprend un accès déjà accordé, au lancement.
    private func resume() {
        guard let appToken = KeychainStore.password(account: Self.tokenAccount) else { return }
        connection = .connecting
        connectTask = Task {
            do {
                let endpoint = try await client.discover()
                try await open(endpoint: endpoint, appToken: appToken)
            } catch is CancellationError {
                connection = .disconnected
            } catch {
                connection = .failed(message: Self.message(for: error))
                AppLog.shared.error("Consommation", "Connexion à la box en échec : " + Self.message(for: error))
            }
        }
    }

    /// Nouvel essai après un échec, avec l'accès déjà enregistré s'il existe.
    func retry() {
        guard !isBusy else { return }
        if KeychainStore.hasPassword(account: Self.tokenAccount) {
            resume()
        } else {
            connectFreebox()
        }
    }

    private func open(endpoint: FreeboxEndpoint, appToken: String) async throws {
        sessionToken = try await client.openSession(endpoint: endpoint, appToken: appToken)
        self.endpoint = endpoint
        connection = .connected(boxName: endpoint.deviceName)
        AppLog.shared.info("Consommation", "Session ouverte avec \(endpoint.deviceName).")
        startPolling()
    }

    // MARK: Relevés

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.takeReading()
                try? await Task.sleep(for: .seconds(self?.pollSeconds ?? 30))
            }
        }
    }

    /// Copie dans le presse-papiers les réponses brutes de la box, pour comprendre un relevé vide.
    func copyDiagnostic() {
        guard let endpoint, let sessionToken else {
            diagnosticMessage = L("Aucune session ouverte avec la box.")
            return
        }
        diagnosticMessage = L("Diagnostic en cours…")
        Task {
            var text = await client.diagnostic(endpoint: endpoint, sessionToken: sessionToken)
            text += "\n\nDernier relevé : \(lastReading?.formatted(date: .omitted, time: .standard) ?? "aucun")"
            text += " · \(lastReadingCount) élément(s) · erreur : \(readingError ?? "aucune")"
            Pasteboard.copy(text)
            diagnosticMessage = L("Diagnostic copié dans le presse-papiers.")
        }
    }

    /// Relit la fréquence des relevés et la durée de conservation dans les réglages.
    func applySettings() {
        keptDays = AppSettings.usageKeptDays
        if AppSettings.freeboxUsesHTTPS != client.usesHTTPS {
            // Le mode d'échange change : les appels suivants passent par le nouveau client.
            client = FreeboxClient(usesHTTPS: AppSettings.freeboxUsesHTTPS)
            AppLog.shared.info("Consommation", "Échanges avec la box en \(client.usesHTTPS ? "HTTPS" : "HTTP non chiffré").")
            if case .failed = connection {
                retry()
            }
        }
        let seconds = AppSettings.usagePollSeconds
        guard seconds != pollSeconds else { return }
        pollSeconds = seconds
        if isConnected {
            startPolling()
        }
    }

    /// Efface les volumes conservés. La connexion à la box et le suivi en cours ne sont pas touchés.
    func clearHistory() {
        ledger = UsageLedger()
        tracker = UsageTracker()
        store.save(ledger)
        unsavedReadings = 0
    }

    func refreshNow() {
        guard isConnected, !isRefreshing else { return }
        Task {
            await takeReading()
        }
    }

    private func takeReading() async {
        guard !isRefreshing, let endpoint, let sessionToken else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result: FreeboxReadings
            do {
                result = try await client.readings(endpoint: endpoint, sessionToken: sessionToken)
            } catch FreeboxError.authenticationRequired {
                // La session a expiré : on en rouvre une avec le jeton enregistré, une seule fois.
                guard let appToken = KeychainStore.password(account: Self.tokenAccount) else {
                    throw FreeboxError.invalidToken
                }
                let renewed = try await client.openSession(endpoint: endpoint, appToken: appToken)
                self.sessionToken = renewed
                result = try await client.readings(endpoint: endpoint, sessionToken: renewed)
            }
            guard self.endpoint != nil else { return }
            let readings = result.readings
            let now = Date()
            let deltas = tracker.ingest(readings, at: now)
            ledger.describe(readings)
            ledger.record(deltas, day: Self.dayKey(now))
            lastReading = now
            lastReadingCount = readings.count
            readingError = result.failures.isEmpty ? nil : result.failures.map { failure in
                (failure.part == .wifi ? L("Wi-Fi : ") : L("Ethernet : ")) + Self.message(for: failure.error)
            }.joined(separator: " ")
            unsavedReadings += 1
            // Une écriture toutes les deux minutes suffit : au pire, deux minutes de relevés sont perdues.
            if unsavedReadings >= 4 {
                ledger.trim(keepingDays: keptDays)
                store.save(ledger)
                unsavedReadings = 0
            }
        } catch is CancellationError {
            return
        } catch FreeboxError.invalidToken {
            pollTask?.cancel()
            connection = .failed(message: L("La Freebox n'accepte plus l'accès de Pingouin (il a pu être révoqué dans Freebox OS). Oublier l'accès, puis reconnecter la box."))
            AppLog.shared.error("Consommation", "La Freebox refuse le jeton enregistré.")
        } catch {
            readingError = L("Dernier relevé impossible : ") + Self.message(for: error)
            AppLog.shared.warning("Consommation", readingError ?? "")
        }
    }

    // MARK: Outils

    private static func percent(_ share: Double, hasTraffic: Bool) -> String {
        // Le pourcentage est mis en forme par le système : son écriture change selon la langue.
        let whole = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        guard hasTraffic else { return 0.0.formatted(whole) }
        let value = Int((share * 100).rounded())
        return value < 1 ? L("moins de \(0.01.formatted(whole))") : (Double(value) / 100).formatted(whole)
    }

    private static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func lastDayKeys(_ count: Int) -> [String] {
        let today = Date()
        return (0..<count).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: today).map { dayKey($0) }
        }
    }
}
