import Foundation
import PingouinCore
import Testing
@testable import PingouinNetwork

/// Lectures du système faites par la cible C (table de routage, résolveur). Rien ne part sur le réseau.
/// Ces lectures servent surtout à iOS, mais le code est le même sur macOS : on le vérifie ici.
@Suite("Lectures du système")
struct SystemReadTests {

    @Test("La passerelle lue dans le noyau est celle que donne la commande route")
    func kernelRouteMatchesRouteCommand() {
        let fromCommand = DefaultRouteReader.read()
        let fromKernel = DefaultRouteReader.readFromKernel()
        // Sans réseau, les deux lectures ne trouvent rien ; avec un réseau, elles donnent la même passerelle IPv4.
        if let fromCommand, IPAddressV4(fromCommand.gateway) != nil {
            #expect(fromKernel?.gateway == fromCommand.gateway)
            #expect(fromKernel?.interfaceName == fromCommand.interfaceName)
        } else if let fromKernel {
            #expect(HostAddress(fromKernel.gateway) != nil)
        }
    }

    @Test("Les serveurs DNS du résolveur sont des adresses")
    func resolverServersAreAddresses() {
        for server in UDPDNSClient.resolverServers() {
            #expect(HostAddress(server) != nil, "« \(server) » n'est pas une adresse")
        }
    }
}
