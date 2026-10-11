#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import CoreText
import Foundation
import Observation
import PingouinCore
import UniformTypeIdentifiers

// Police et couleur du PDF : celles d'AppKit sur le Mac, d'UIKit sur iOS.
#if canImport(AppKit)
private typealias ReportFont = NSFont
private typealias ReportColor = NSColor
#else
private typealias ReportFont = UIFont
private typealias ReportColor = UIColor
#endif

/// Les outils dont un rapport peut reprendre les résultats. L'état de l'application Mac et celui de
/// l'application iOS s'y conforment : le rapport se construit de la même façon sur les deux.
@MainActor
protocol ReportSource {
    var lanDiscovery: LANDiscoveryViewModel { get }
    var portScanner: PortScanViewModel { get }
    var ping: PingViewModel { get }
    var traceroute: TracerouteViewModel { get }
    var dns: DNSViewModel { get }
    var http: HTTPViewModel { get }
    var tls: TLSViewModel { get }
    var monitoring: MonitoringViewModel { get }
}

enum ReportFormat: String, CaseIterable, Identifiable {
    case pdf
    case csv
    case json

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }

    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .csv: .commaSeparatedText
        case .json: .json
        }
    }
}

/// Rapports : assemble les résultats présents dans les autres outils. Rien n'est relancé ni inventé :
/// un outil qui n'a pas de résultat n'a pas de section.
@MainActor
@Observable
final class ReportsViewModel {
    /// Sections que l'utilisateur a décochées.
    var excludedSections: Set<String> = []
    var maskMACAddresses = false
    var maskHostnames = false
    var format: ReportFormat = .pdf
    private(set) var message: String?

    func isIncluded(_ id: String) -> Bool {
        !excludedSections.contains(id)
    }

    func setIncluded(_ included: Bool, id: String) {
        if included {
            excludedSections.remove(id)
        } else {
            excludedSections.insert(id)
        }
    }

    // MARK: Contenu

    /// Sections disponibles, d'après l'état actuel des outils.
    func availableSections(from app: some ReportSource) -> [ReportSection] {
        var sections: [ReportSection] = []

        let lan = app.lanDiscovery
        if lan.hostCount > 0 {
            sections.append(ReportSection(
                id: "lan",
                title: L("Découverte LAN"),
                parameters: [L("Plage : \(lan.rangeText)")],
                columns: [
                    ReportColumn(L("Adresse")), ReportColumn(L("Nom"), kind: .hostname),
                    ReportColumn(L("Adresse MAC"), kind: .macAddress), ReportColumn(L("Temps")), ReportColumn(L("État"))
                ],
                rows: lan.rows.map { [$0.address, $0.hostname, $0.macAddress, $0.responseText, $0.status] },
                notes: [L("\(lan.hostCount) hôtes trouvés, dont \(lan.pingReplyCount) répondent au ping.")]
            ))
        }

        let ports = app.portScanner
        if ports.testedCount > 0 {
            sections.append(ReportSection(
                id: "ports",
                title: L("Scan de ports"),
                parameters: [L("Hôte : \(ports.scannedHost)"), L("Affichage : \(ports.filter.title.lowercased())")],
                columns: [ReportColumn(L("Port")), ReportColumn(L("Service habituel")), ReportColumn(L("État")), ReportColumn(L("Temps")), ReportColumn(L("Détail"))],
                rows: ports.rows.map { [String($0.port), $0.service, $0.stateText, $0.timeText, $0.detail] },
                notes: [L("\(ports.testedCount) ports testés : \(ports.openCount) ouverts, \(ports.closedCount) fermés, \(ports.undeterminedCount) indéterminés.")]
            ))
        }

        let ping = app.ping
        if ping.hasResults {
            let stats = ping.statistics
            var note = L("\(stats.received) réponses sur \(stats.sent) (perte \((stats.lossPercent / 100).formatted(.percent.precision(.fractionLength(0...1)))))")
            if let minimum = stats.minimum, let average = stats.average, let maximum = stats.maximum {
                note += L(" ; minimum \(NumberInput.milliseconds(minimum)), moyenne \(NumberInput.milliseconds(average)), maximum \(NumberInput.milliseconds(maximum))")
            }
            sections.append(ReportSection(
                id: "ping",
                title: L("Ping"),
                parameters: [L("Hôte : \(ping.host)"), L("Tentatives : \(ping.countText)"), L("Intervalle : \(ping.intervalText) s"), L("Délai : \(ping.timeoutText) ms")],
                columns: [ReportColumn(L("N°")), ReportColumn(L("Heure")), ReportColumn(L("Adresse")), ReportColumn("TTL"), ReportColumn(L("Temps")), ReportColumn(L("État"))],
                rows: ping.rows.sorted { $0.id < $1.id }.map { [String($0.id), $0.time, $0.address, $0.ttl, $0.timeText, $0.status] },
                notes: [note + "."]
            ))
        }

        let traceroute = app.traceroute
        if traceroute.hopCount > 0 {
            sections.append(ReportSection(
                id: "traceroute",
                title: L("Traceroute"),
                parameters: [L("Destination : \(traceroute.host)"), L("Sondes par saut : \(traceroute.probesText)"), L("Délai : \(traceroute.timeoutText) ms")],
                columns: [ReportColumn(L("Saut")), ReportColumn(L("Adresse")), ReportColumn(L("Nom"), kind: .hostname), ReportColumn(L("Sondes (ms)")), ReportColumn(L("Moyenne"))],
                rows: traceroute.rows.map { [String($0.id), $0.address.isEmpty ? "*" : $0.address, $0.name, $0.probes, $0.averageText] },
                notes: [L("\(traceroute.hopCount) sauts, dont \(traceroute.silentHopCount) sans réponse.")]
            ))
        }

        let dns = app.dns
        if !dns.records.isEmpty || dns.responseCode != "—" {
            sections.append(ReportSection(
                id: "dns",
                title: "DNS",
                parameters: [L("Question : \(dns.name) (\(dns.type.name))"), L("Serveur : \(dns.serverUsed)")],
                columns: [ReportColumn(L("Nom")), ReportColumn(L("Type")), ReportColumn("TTL"), ReportColumn(L("Valeur"))],
                rows: dns.records.map { [$0.name, $0.type, $0.ttl, $0.value] },
                notes: [L("Réponse : \(dns.responseSummary.lowercased()) (\(dns.responseCode)), en \(dns.responseTime).")]
            ))
        }

        let http = app.http
        if http.hasResult {
            let phaseNotes: [String] = http.phases.map { phase in
                "\(phase.label) : \(phase.milliseconds.formatted(.number.precision(.fractionLength(0)))) ms"
            }
            sections.append(ReportSection(
                id: "http",
                title: "HTTP",
                parameters: [L("Méthode : \(http.method)"), L("URL : \(http.urlText)")],
                columns: [ReportColumn(L("Code")), ReportColumn("URL"), ReportColumn(L("Remarque"))],
                rows: http.redirects.map { [$0.statusCode, $0.url, $0.note] },
                notes: [L("Code \(http.statusCodeText), en \(http.totalTimeText), \(http.sizeText) reçus.")] + phaseNotes
            ))
        }

        let tls = app.tls
        if tls.hasResult {
            let detailLines: [String] = tls.details.map { "\($0.label) : \($0.value)" }
            sections.append(ReportSection(
                id: "tls",
                title: "TLS",
                parameters: [L("Hôte : \(tls.hostText):\(tls.portText)")] + detailLines,
                columns: [ReportColumn(L("Rôle")), ReportColumn(L("Certificat")), ReportColumn(L("Validité"))],
                rows: tls.chain.map { [$0.role, $0.subject, $0.validity] },
                notes: [tls.verdict?.title, tls.verdict?.detail].compactMap { $0 }
            ))
        }

        let monitoring = app.monitoring
        if !monitoring.monitors.isEmpty {
            sections.append(ReportSection(
                id: "supervision",
                title: L("Supervision"),
                parameters: [L("Période de disponibilité : \(monitoring.period.title.lowercased())")],
                columns: [ReportColumn(L("Nom")), ReportColumn(L("Cible")), ReportColumn(L("Test")), ReportColumn(L("État")), ReportColumn(L("Temps")), ReportColumn(L("Disponibilité"))],
                rows: monitoring.rows.map { [$0.name, $0.target, $0.test, $0.statusText, $0.time, $0.availability] },
                notes: monitoring.events.prefix(10).map { "\($0.date.formatted(date: .numeric, time: .shortened)) · \($0.monitorName) · \($0.text)" }
            ))
        }

        return sections
    }

    /// Rapport tel qu'il sera exporté : sections cochées, masquage appliqué.
    func report(from app: some ReportSource, date: Date = Date()) -> Report {
        let sections = availableSections(from: app).filter { isIncluded($0.id) }
        let report = Report(title: L("Rapport de diagnostic réseau"), generatedAt: date, sections: sections)
        return ReportRenderer.applying(
            ReportPrivacy(maskMACAddresses: maskMACAddresses, maskHostnames: maskHostnames),
            to: report
        )
    }

    func previewText(from app: some ReportSource) -> String {
        let report = self.report(from: app)
        guard !report.sections.isEmpty else { return "" }
        return ReportRenderer.text(report, dateText: Self.dateText(report.generatedAt))
    }

    // MARK: Export

    /// Rapport au format choisi, avec son nom de fichier. `nil`, avec un message, s'il n'y a rien à
    /// exporter ou si la génération échoue.
    private func exportData(from app: some ReportSource) -> (data: Data, fileName: String)? {
        let report = self.report(from: app)
        guard !report.sections.isEmpty else {
            message = L("Aucune section à exporter.")
            return nil
        }

        let data: Data
        do {
            switch format {
            case .pdf:
                let text = ReportRenderer.text(report, dateText: Self.dateText(report.generatedAt))
                guard let pdf = Self.pdfData(text: text, title: "\(report.title) · \(Self.dateText(report.generatedAt))") else {
                    message = L("Le PDF n'a pas pu être créé.")
                    AppLog.shared.error("Rapports", "Création du PDF en échec.")
                    return nil
                }
                data = pdf
            case .csv:
                // La marque d'ordre d'octets fait reconnaître l'UTF-8 par les tableurs.
                data = Data("\u{FEFF}".utf8) + Data(ReportRenderer.csv(report).utf8)
            case .json:
                data = try ReportRenderer.json(report)
            }
        } catch {
            message = L("Le rapport n'a pas pu être généré : \(error.localizedDescription)")
            return nil
        }
        return (data, "rapport-pingouin-\(Self.fileDate(report.generatedAt)).\(format.rawValue)")
    }

    #if os(macOS)
    /// Demande l'emplacement, puis écrit le rapport au format choisi.
    func export(from app: some ReportSource) {
        guard let export = exportData(from: app) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = export.fileName
        panel.message = L("Choisir où enregistrer le rapport")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export.data.write(to: url, options: .atomic)
            message = L("Rapport enregistré dans \(url.lastPathComponent).")
        } catch {
            message = L("L'enregistrement a échoué : \(error.localizedDescription)")
        }
    }
    #else
    /// Écrit le rapport dans le dossier temporaire de l'application et renvoie le fichier, à remettre
    /// à la feuille de partage d'iOS (Fichiers, AirDrop, Mail…).
    func exportFile(from app: some ReportSource) -> URL? {
        guard let export = exportData(from: app) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
        do {
            try export.data.write(to: url, options: .atomic)
            message = nil
            return url
        } catch {
            message = L("L'enregistrement a échoué : \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    private static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    /// PDF paginé au format A4 paysage : le texte de l'aperçu, coupé entre deux lignes, avec le titre
    /// et le numéro de page en pied de page. `nil` si le document n'a pas pu être créé.
    private static func pdfData(text: String, title: String) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595)
        let margin: CGFloat = 36
        let footerHeight: CGFloat = 20
        // Zone de texte : toute la page moins les marges, et la place du pied de page en bas.
        let textRect = CGRect(
            x: margin,
            y: margin + footerHeight,
            width: pageRect.width - margin * 2,
            height: pageRect.height - margin * 2 - footerHeight
        )
        let body = NSAttributedString(string: text, attributes: [
            .font: ReportFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: ReportColor.black
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(body)

        // Premier passage : quelle portion du texte tient sur chaque page.
        var ranges: [CFRange] = []
        var location = 0
        while location < body.length {
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: location, length: 0), CGPath(rect: textRect, transform: nil), nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            ranges.append(visible)
            location += visible.length
        }
        guard !ranges.isEmpty else { return nil }

        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: ReportFont.systemFont(ofSize: 8),
            .foregroundColor: ReportColor.darkGray
        ]
        // Second passage : dessin de chaque page.
        for (index, range) in ranges.enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(pageRect)
            let frame = CTFramesetterCreateFrame(framesetter, range, CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, context)

            let footer = NSAttributedString(
                string: L("\(title) — page \(index + 1) sur \(ranges.count)"),
                attributes: footerAttributes
            )
            context.textPosition = CGPoint(x: margin, y: margin)
            CTLineDraw(CTLineCreateWithAttributedString(footer), context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
