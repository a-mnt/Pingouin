import Foundation
import Observation
import PingouinCore

/// Ligne « libellé : valeur » du résultat.
struct SummaryRow: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }
}

/// Ligne du tableau de découpage.
struct SubnetRow: Identifiable, Hashable {
    let network: String
    let range: String
    let detail: String
    var id: String { network }
}

enum MembershipOutcome: Equatable {
    case notAsked
    case invalidAddress
    case familyMismatch
    case inside
    case outside
}

enum SplitOutcome: Equatable {
    case notAsked
    case invalid(message: String)
    case result(summary: String, rows: [SubnetRow], truncated: Bool)
}

/// Présentation du calculateur IP. Aucun calcul ici : tout est délégué à PingouinCore,
/// cette classe ne fait que traduire les résultats en textes affichables.
@MainActor
@Observable
final class IPCalculatorViewModel {
    /// Nombre maximal de sous-réseaux listés à l'écran.
    static let subnetDisplayLimit = 64

    var input = "192.168.10.0/24"
    var probe = ""
    var splitPrefix = ""

    private var parsed: Result<IPSubnet, IPParseError> {
        IPSubnet.parse(input)
    }

    private var subnet: IPSubnet? {
        if case .success(let subnet) = parsed { return subnet }
        return nil
    }

    // MARK: Erreur de saisie

    var errorMessage: String? {
        guard case .failure(let error) = parsed else { return nil }
        switch error {
        case .empty:
            return L("Saisir une adresse et un préfixe, par exemple 192.168.10.0/24 ou 2001:db8::/48.")
        case .missingPrefix:
            return L("Il manque le préfixe : ajouter « / » suivi de sa longueur, par exemple /24.")
        case .invalidAddress:
            return L("Adresse non reconnue. Attendu : une adresse IPv4 (quatre octets de 0 à 255, sans zéro en tête) ou IPv6.")
        case .invalidPrefix(let maximum):
            return L("Préfixe non valide : un nombre entier de 0 à \(maximum) est attendu.")
        case .invalidMask:
            return L("Masque non valide : les bits à 1 doivent être contigus, par exemple 255.255.252.0.")
        }
    }

    // MARK: Résultat

    var summary: [SummaryRow] {
        switch subnet {
        case .some(.v4(let net)):
            return summary(for: net)
        case .some(.v6(let net)):
            return summary(for: net)
        case .none:
            return []
        }
    }

    private func summary(for net: IPv4Subnet) -> [SummaryRow] {
        let broadcast: String
        if let address = net.broadcast {
            broadcast = address.description
        } else if net.prefixLength == 31 {
            broadcast = L("Sans objet (lien point à point, RFC 3021)")
        } else {
            broadcast = L("Sans objet (hôte unique)")
        }
        return [
            SummaryRow(label: L("Réseau"), value: net.description),
            SummaryRow(label: L("Masque"), value: net.mask.description),
            SummaryRow(label: L("Masque en binaire"), value: net.mask.binaryDescription),
            SummaryRow(label: L("Masque inverse"), value: net.wildcardMask.description),
            SummaryRow(label: L("Première adresse utilisable"), value: net.firstUsable.description),
            SummaryRow(label: L("Dernière adresse utilisable"), value: net.lastUsable.description),
            SummaryRow(label: L("Broadcast"), value: broadcast),
            SummaryRow(label: L("Nombre d'adresses"), value: net.addressCount.formatted()),
            SummaryRow(label: L("Hôtes utilisables"), value: net.usableHostCount.formatted()),
            SummaryRow(label: L("Type de plage"), value: Self.label(for: net.kind))
        ]
    }

    private func summary(for net: IPv6Subnet) -> [SummaryRow] {
        var rows = [
            SummaryRow(label: L("Réseau"), value: net.description),
            SummaryRow(label: L("Réseau (forme développée)"), value: net.network.expandedDescription),
            SummaryRow(label: L("Première adresse"), value: net.network.description),
            SummaryRow(label: L("Dernière adresse"), value: net.lastAddress.description),
            SummaryRow(label: L("Nombre d'adresses"), value: net.addressCountDescription),
            SummaryRow(label: L("Type de plage"), value: Self.label(for: net.kind))
        ]
        if net.prefixLength == 127 {
            rows.append(SummaryRow(label: L("Remarque"), value: L("Lien point à point (RFC 6164)")))
        } else if net.prefixLength == 128 {
            rows.append(SummaryRow(label: L("Remarque"), value: L("Hôte unique")))
        }
        return rows
    }

    private static let highlightLabels: Set<String> = [
        L("Réseau"), L("Broadcast"), L("Première adresse utilisable"), L("Dernière adresse utilisable"),
        L("Première adresse"), L("Dernière adresse")
    ]

    /// Valeurs mises en avant sous forme de tuiles.
    var highlights: [SummaryRow] {
        summary.filter { Self.highlightLabels.contains($0.label) }
    }

    /// Le reste du résultat, présenté en tableau.
    var details: [SummaryRow] {
        summary.filter { !Self.highlightLabels.contains($0.label) }
    }

    /// Résumé en texte brut, destiné au presse-papiers.
    var summaryText: String {
        summary.map { "\($0.label) : \($0.value)" }.joined(separator: "\n")
    }

    // MARK: Appartenance

    var membership: MembershipOutcome {
        let text = probe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let subnet else { return .notAsked }
        switch subnet {
        case .v4(let net):
            if let address = IPAddressV4(text) {
                return net.contains(address) ? .inside : .outside
            }
            return IPAddressV6(text) != nil ? .familyMismatch : .invalidAddress
        case .v6(let net):
            if let address = IPAddressV6(text) {
                return net.contains(address) ? .inside : .outside
            }
            return IPAddressV4(text) != nil ? .familyMismatch : .invalidAddress
        }
    }

    // MARK: Découpage

    var split: SplitOutcome {
        let text = splitPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let subnet else { return .notAsked }
        guard text.count <= 3, text.allSatisfy({ $0.isASCII && $0.isWholeNumber }), let newPrefix = Int(text) else {
            return .invalid(message: L("Le préfixe de découpage doit être un nombre entier."))
        }
        switch subnet {
        case .v4(let net):
            return split(net, into: newPrefix)
        case .v6(let net):
            return split(net, into: newPrefix)
        }
    }

    private func split(_ net: IPv4Subnet, into newPrefix: Int) -> SplitOutcome {
        guard let count = net.subnetCount(prefixLength: newPrefix) else {
            if net.prefixLength == 32 {
                return .invalid(message: L("Un /32 ne peut pas être découpé."))
            }
            return .invalid(message: L("Choisir un préfixe compris entre /\(net.prefixLength + 1) et /32."))
        }
        let parts = net.subnets(prefixLength: newPrefix, limit: Self.subnetDisplayLimit)
        let rows = parts.map { part in
            SubnetRow(
                network: part.description,
                range: part.firstUsable == part.lastUsable
                    ? part.firstUsable.description
                    : "\(part.firstUsable) – \(part.lastUsable)",
                detail: part.broadcast.map { $0.description } ?? L("Aucun")
            )
        }
        let size = parts.first?.addressCount.formatted() ?? "0"
        let summary = L("\(count.formatted()) sous-réseaux /\(newPrefix) de \(size) adresses chacun")
        return .result(summary: summary, rows: rows, truncated: count > UInt64(rows.count))
    }

    private func split(_ net: IPv6Subnet, into newPrefix: Int) -> SplitOutcome {
        guard net.canSplit(prefixLength: newPrefix) else {
            if net.prefixLength == 128 {
                return .invalid(message: L("Un /128 ne peut pas être découpé."))
            }
            return .invalid(message: L("Choisir un préfixe compris entre /\(net.prefixLength + 1) et /128."))
        }
        let parts = net.subnets(prefixLength: newPrefix, limit: Self.subnetDisplayLimit)
        let rows = parts.map { part in
            SubnetRow(
                network: part.description,
                range: part.network == part.lastAddress
                    ? part.network.description
                    : "\(part.network) – \(part.lastAddress)",
                detail: ""
            )
        }
        let count = net.subnetCount(prefixLength: newPrefix)
        let countText = count.map { String($0) } ?? "2^128"
        let size = parts.first?.addressCountDescription ?? "0"
        let summary = L("\(countText) sous-réseaux /\(newPrefix) de \(size) adresses chacun")
        let truncated = count.map { $0 > UInt128(rows.count) } ?? true
        return .result(summary: summary, rows: rows, truncated: truncated)
    }

    // MARK: Libellés

    private static func label(for kind: IPv4RangeKind) -> String {
        switch kind {
        case .privateUse: L("Plage privée (RFC 1918)")
        case .loopback: L("Bouclage")
        case .linkLocal: L("Lien-local")
        case .sharedAddressSpace: L("Espace partagé opérateur (RFC 6598)")
        case .documentation: L("Réservée à la documentation (RFC 5737)")
        case .multicast: L("Multidiffusion")
        case .reserved: L("Réservée")
        case .publicRange: L("Adresses publiques")
        }
    }

    private static func label(for kind: IPv6RangeKind) -> String {
        switch kind {
        case .unspecified: L("Adresse non spécifiée")
        case .loopback: L("Bouclage")
        case .ipv4Mapped: L("IPv4 mappée")
        case .linkLocal: L("Lien-local")
        case .uniqueLocal: L("Locale unique (RFC 4193)")
        case .multicast: L("Multidiffusion")
        case .documentation: L("Réservée à la documentation (RFC 3849)")
        case .globalUnicast: L("Unicast globale")
        case .reserved: L("Réservée")
        }
    }
}
