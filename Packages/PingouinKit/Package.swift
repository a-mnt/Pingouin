// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PingouinKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PingouinCore", targets: ["PingouinCore"]),
        .library(name: "PingouinNetwork", targets: ["PingouinNetwork"])
    ],
    targets: [
        // Types de domaine et calculs purs : aucun accès au réseau ni au système.
        .target(name: "PingouinCore"),
        // Services qui parlent au système (sockets, interfaces, processus).
        .target(name: "PingouinNetwork", dependencies: ["PingouinCore", "CPingouinSystem"]),
        // Deux lectures du système que Swift n'atteint pas directement : serveurs DNS (libresolv)
        // et table de routage (sysctl). Aucun accès au réseau.
        .target(name: "CPingouinSystem", linkerSettings: [.linkedLibrary("resolv")]),
        .testTarget(name: "PingouinCoreTests", dependencies: ["PingouinCore"]),
        // Essais des services réseau sur la boucle locale : aucun accès au réseau extérieur.
        .testTarget(name: "PingouinNetworkTests", dependencies: ["PingouinNetwork", "PingouinCore"])
    ]
)
