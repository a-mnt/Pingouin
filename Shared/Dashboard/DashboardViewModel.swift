import Foundation
import Observation
import PingouinCore
import PingouinNetwork
#if os(macOS)
import SystemConfiguration
#endif

/// Ce que l'appareil sait de son propre raccordement, lu sans rien envoyer sur le réseau.
struct LocalNetworkInfo: Equatable {
    /// Nom de l'interface pour le système (« Wi-Fi », « Ethernet »…), s'il est connu.
    let displayName: String?
    let interfaceName: String
    /// Adresse IPv4 et préfixe, par exemple « 192.168.1.57 /24 ». Vide si l'interface n'a pas d'IPv4.
    let address: String
    /// Plage du réseau raccordé, par exemple « 192.168.1.0/24 ».
    let subnet: String
    let hostCount: Int
    /// Vide quand le système n'en donne pas (iOS sans Wi-Fi, par exemple).
    let gateway: String
    let dnsServers: [String]
    let ipv6Addresses: [String]
}

/// Maillon du test de connexion, du plus proche au plus lointain.
enum ConnectionStep: Int, CaseIterable, Identifiable {
    case gateway
    case internet
    case dns
    case web

    var id: Int { rawValue }
}

enum ConnectionStepState: Equatable {
    case untested
    case running
    case ok(milliseconds: Double?)
    case failed(detail: String)
}

/// Avancement des trois étapes de prise en main.
struct DashboardSteps {
    let discoveryDone: Bool
    let monitoringDone: Bool
    let boxDone: Bool

    var doneCount: Int { [discoveryDone, monitoringDone, boxDone].filter { $0 }.count }
    var isComplete: Bool { doneCount == 3 }
    var hasStarted: Bool { doneCount > 0 }
}

/// Tableau de bord : le raccordement de l'appareil et le test de connexion. Les autres blocs lisent
/// directement l'état des modules concernés.
@MainActor
@Observable
final class DashboardViewModel {
    private let runner = CheckRunner()

    private(set) var network: LocalNetworkInfo?
    /// Faux tant que la première lecture n'est pas revenue.
    private(set) var networkWasRead = false
    private(set) var states: [ConnectionStep: ConnectionStepState] = [:]
    private(set) var testedAt: Date?
    private(set) var isTesting = false
    /// Cibles utilisées par le dernier test, pour les afficher telles qu'elles ont été interrogées.
    private(set) var pingTarget = AppSettings.connectionPingTarget
    private(set) var webName = AppSettings.connectionWebName
    var quickTarget = ""

    private var testTask: Task<Void, Never>?

    func state(of step: ConnectionStep) -> ConnectionStepState {
        states[step] ?? .untested
    }

    /// Premier maillon en échec du dernier test, s'il y en a un.
    var firstFailure: ConnectionStep? {
        ConnectionStep.allCases.first { step in
            if case .failed = state(of: step) { return true }
            return false
        }
    }

    // MARK: Raccordement

    /// Relit l'interface, la passerelle et les serveurs DNS. Aucun paquet ne part : tout vient du Mac.
    func refreshNetwork() {
        pingTarget = AppSettings.connectionPingTarget
        webName = AppSettings.connectionWebName
        Task {
            let info = await Task.detached(priority: .userInitiated) { Self.readNetwork() }.value
            network = info
            networkWasRead = true
        }
    }

    private nonisolated static func readNetwork() -> LocalNetworkInfo? {
        let route = DefaultRouteReader.read()
        let interfaces = InterfaceInventory.ipv4Interfaces()
        #if os(macOS)
        guard let found = route else { return nil }
        let interface = interfaces.first { $0.name == found.interfaceName }
        let interfaceName = found.interfaceName
        #else
        // Sur iOS, la passerelle peut manquer alors que le Wi-Fi (en0) est bien raccordé.
        let interface = route.flatMap { route in interfaces.first { $0.name == route.interfaceName } }
            ?? interfaces.first { $0.name == "en0" }
            ?? interfaces.first
        guard route != nil || interface != nil else { return nil }
        let interfaceName = interface?.name ?? route?.interfaceName ?? ""
        #endif
        return LocalNetworkInfo(
            displayName: displayName(of: interfaceName),
            interfaceName: interfaceName,
            address: interface.map { "\($0.address) /\($0.subnet.prefixLength)" } ?? "",
            subnet: interface?.subnet.description ?? "",
            hostCount: interface.map { Int(min($0.subnet.usableHostCount, UInt64(Int32.max))) } ?? 0,
            gateway: route?.gateway ?? "",
            dnsServers: UDPDNSClient().systemServers(),
            ipv6Addresses: InterfaceInventory.ipv6Addresses(interfaceName: interfaceName).map(\.description)
        )
    }

    private nonisolated static func displayName(of interfaceName: String) -> String? {
        #if os(macOS)
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return nil }
        for interface in interfaces where SCNetworkInterfaceGetBSDName(interface) as String? == interfaceName {
            return SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
        }
        return nil
        #else
        // Sur iPhone et iPad, « en0 » est le Wi-Fi ; les autres interfaces gardent leur nom technique.
        return interfaceName == "en0" ? "Wi-Fi" : nil
        #endif
    }

    static var noGatewayText: String {
        #if os(macOS)
        L("Aucune passerelle : ce Mac n'est raccordé à aucun réseau.")
        #else
        L("Aucune passerelle : cet appareil n'est raccordé à aucun réseau Wi-Fi.")
        #endif
    }

    // MARK: Test de connexion

    /// Lance les quatre contrôles, l'un après l'autre. Tous sont faits, même après un échec :
    /// une box peut ignorer le ping alors qu'Internet fonctionne.
    func runTest() {
        guard !isTesting else { return }
        pingTarget = AppSettings.connectionPingTarget
        webName = AppSettings.connectionWebName
        let gateway = network.flatMap { $0.gateway.isEmpty ? nil : $0.gateway }
        let pingTarget = self.pingTarget
        let webName = self.webName
        isTesting = true
        states = [:]

        testTask = Task {
            for step in ConnectionStep.allCases {
                if Task.isCancelled { break }
                states[step] = .running
                let result: CheckResult
                switch step {
                case .gateway:
                    if let gateway {
                        result = await runner.ping(host: gateway)
                    } else {
                        result = CheckResult(level: .failure, milliseconds: nil, detail: Self.noGatewayText)
                    }
                case .internet:
                    result = await runner.ping(host: pingTarget)
                case .dns:
                    result = await runner.dns(name: webName)
                case .web:
                    result = await runner.http(urlText: "https://\(webName)/")
                }
                if Task.isCancelled {
                    states[step] = .untested
                    break
                }
                states[step] = result.succeeded ? .ok(milliseconds: result.milliseconds) : .failed(detail: result.detail)
            }
            testedAt = Date()
            isTesting = false
            let failed = firstFailure.map { String(describing: $0) }
            AppLog.shared.info("Tableau de bord", "Test de connexion terminé" + (failed.map { " : premier échec au maillon \($0)." } ?? " : tout répond."))
        }
    }

    func cancelTest() {
        testTask?.cancel()
    }
}
