import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Ce qui change d'un système à l'autre dans les textes et les valeurs envoyées à l'extérieur.
enum Platform {
    /// Nom du système, pour les messages qui le citent (« … approuvée par macOS »).
    static var systemName: String {
        #if os(macOS)
        "macOS"
        #else
        "iOS"
        #endif
    }

    /// Nom donné à l'appareil par son propriétaire, pour se présenter à un équipement du réseau.
    @MainActor
    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        UIDevice.current.name
        #endif
    }
}
