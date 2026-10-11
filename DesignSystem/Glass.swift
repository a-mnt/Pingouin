#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Fond de fenêtre : deux halos aux couleurs du pingouin (orange du bec, bleu de la banquise).
/// C'est lui qui donne de la matière aux panneaux de verre posés par-dessus.
struct PingouinBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 0.26 : 0.36
        ZStack {
            Self.base
            RadialGradient(
                colors: [Color.orange.opacity(strength), .clear],
                center: UnitPoint(x: 0.9, y: -0.05),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [Color.blue.opacity(strength * 0.85), .clear],
                center: UnitPoint(x: -0.02, y: 1.04),
                startRadius: 0,
                endRadius: 720
            )
        }
        .ignoresSafeArea()
    }

    /// Couleur de fond du système, sous les halos.
    private static var base: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

extension View {
    /// Panneau Liquid Glass aux angles arrondis. Tout l'usage du matériau de verre passe par ici,
    /// pour n'avoir qu'un endroit à ajuster.
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Panneau Liquid Glass teinté : la teinte colore le verre lui-même, sans masquer le fond.
    func glassCard(cornerRadius: CGFloat = 20, tint: Color) -> some View {
        glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Tuile Liquid Glass vivante : verre teinté qui réagit au pointeur, posé sur un halo de couleur.
    /// Le halo est derrière le verre : c'est lui que le verre déforme et laisse transparaître.
    func glassTile(cornerRadius: CGFloat = 28, tint: Color, halo: Color, haloStrength: Double = 1) -> some View {
        glassEffect(.regular.tint(tint).interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                GeometryReader { proxy in
                    ZStack {
                        Circle()
                            .fill(halo.opacity(0.55 * haloStrength))
                            .frame(width: 150, height: 150)
                            .position(x: proxy.size.width - 52, y: 46)
                        Circle()
                            .fill(halo.opacity(0.28 * haloStrength))
                            .frame(width: 120, height: 120)
                            .position(x: 40, y: proxy.size.height - 20)
                    }
                    .blur(radius: 34)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    /// Contenu de carte : marges internes puis panneau de verre.
    func glassCardPadded(cornerRadius: CGFloat = 20) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: cornerRadius)
    }
}

/// Tuile de synthèse : un libellé et une valeur mise en avant.
struct StatTile: View {
    let label: String
    let value: String
    var tint: Color?
    var monospaced = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .fontDesign(monospaced ? .monospaced : .default)
                .foregroundStyle(tint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

/// Champ surmonté de son libellé.
struct LabeledField<Content: View>: View {
    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Nature d'un état. La forme du repère change avec la nature : la couleur n'est jamais seule à porter le sens.
enum StatusKind: Hashable {
    case ok
    case warning
    case failure
    case neutral
}

/// Repère de forme accompagné de son libellé.
struct StatusLabel: View {
    let kind: StatusKind
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            marker
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .fontWeight(kind == .ok || kind == .neutral ? .regular : .semibold)
        }
    }

    @ViewBuilder
    private var marker: some View {
        switch kind {
        case .ok:
            Circle().fill(Color.green)
        case .warning:
            Rectangle().fill(Color.orange)
        case .failure:
            Circle().strokeBorder(Color.red, lineWidth: 2)
        case .neutral:
            Circle().strokeBorder(Color.secondary, lineWidth: 2)
        }
    }
}

/// Accès au presse-papiers.
/// Ouverture d'une adresse dans le navigateur par défaut de macOS.
enum Browser {
    /// `port` vide : port habituel du protocole. Renvoie faux si l'adresse n'a pas pu être ouverte.
    @MainActor
    @discardableResult
    static func open(scheme: String, host: String, port: Int? = nil) -> Bool {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/"
        guard let url = components.url else { return false }
        #if canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        return true
        #endif
    }
}

enum Pasteboard {
    @MainActor
    static func copy(_ text: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
