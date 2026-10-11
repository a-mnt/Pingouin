import Foundation
import PingouinCore
import PingouinNetwork
import Testing
@testable import Pingouin

// Services factices : ils rendent ce qu'on leur donne, sans toucher au réseau.
// Ils remplacent les vrais services par les protocoles prévus pour cela.

struct FakeScanner: PortScanning {
    var results: [PortScanResult] = []
    var error: PortScanError?

    func scan(host: String, ports: [UInt16], options: PortScanOptions) -> AsyncThrowingStream<PortScanEvent, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for result in results where ports.contains(result.port) {
                continuation.yield(.result(result))
            }
            continuation.yield(.finished(durationSeconds: 0.1))
            continuation.finish()
        }
    }
}

struct FakePinger: Pinging {
    var events: [PingEvent] = []
    var error: PingError?

    func ping(host: String, options: PingOptions) -> AsyncThrowingStream<PingEvent, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Attend qu'une condition devienne vraie, sans dépasser `timeout` secondes.
@MainActor
func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
}

struct FakeTracer: Tracing {
    var events: [TracerouteEvent] = []
    var error: TracerouteError?

    func trace(host: String, options: TracerouteOptions) -> AsyncThrowingStream<TracerouteEvent, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

struct FakeDNSClient: DNSQuerying {
    var outcome: DNSOutcome = .noRecords
    var error: DNSQueryError?

    func systemServers() -> [String] { ["192.0.2.53"] }

    func query(name: String, type: DNSRecordType, server: String?, timeoutMilliseconds: Int) async throws -> DNSQueryResult {
        if let error { throw error }
        return DNSQueryResult(server: server ?? "192.0.2.53", outcome: outcome, milliseconds: 4)
    }
}

struct FakeHTTPProbe: HTTPProbing {
    var statusCode = 200
    var error: HTTPProbeError?

    func send(url: URL, options: HTTPProbeOptions) async throws -> HTTPProbeResult {
        if let error { throw error }
        return HTTPProbeResult(
            finalURL: url.absoluteString,
            statusCode: statusCode,
            headers: [HTTPHeader(name: "Content-Type", value: "text/plain")],
            bodyByteCount: 120,
            redirects: [],
            totalMilliseconds: 42,
            timing: nil,
            protocolName: "http/1.1"
        )
    }
}

struct FakeTLSInspector: TLSInspecting {
    var isTrusted = true
    var error: TLSInspectionError?

    func inspect(host: String, port: UInt16, serverName: String?, timeoutSeconds: Double) async throws -> TLSInspectionResult {
        if let error { throw error }
        let leaf = CertificateSummary(
            subject: host,
            issuer: "Autorité d'essai",
            notBefore: Date().addingTimeInterval(-86_400),
            notAfter: Date().addingTimeInterval(200 * 86_400),
            subjectAlternativeNames: [host],
            sha256Fingerprint: "AA:BB"
        )
        return TLSInspectionResult(
            host: host,
            port: port,
            isTrusted: isTrusted,
            trustFailureReason: isTrusted ? nil : "certificat auto-signé",
            hostnameMismatch: false,
            negotiatedProtocol: "TLS 1.3",
            chain: [leaf]
        )
    }
}

struct FakeLANDiscovery: LANDiscovering {
    var hosts: [DiscoveredHost] = []

    func discover(
        subnet: IPv4Subnet,
        localAddress: IPAddressV4?,
        options: LANDiscoveryOptions
    ) -> AsyncThrowingStream<LANDiscoveryEvent, Error> {
        AsyncThrowingStream { continuation in
            for host in hosts {
                continuation.yield(.host(host))
            }
            continuation.yield(.finished(LANDiscoverySummary(
                scannedAddressCount: 254,
                hostCount: hosts.count,
                pingReplyCount: hosts.filter(\.respondedToPing).count,
                arpTableAvailable: true,
                durationSeconds: 0.1
            )))
            continuation.finish()
        }
    }
}
