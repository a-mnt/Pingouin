import SwiftUI

/// Logo de l'application, dessiné en formes vectorielles : net à toutes les tailles.
/// Les proportions sont celles de l'icône de l'application (grille de 30 unités).
struct PingouinLogo: View {
    var size: CGFloat = 30

    private static let ink = Color(red: 0x17 / 255, green: 0x21 / 255, blue: 0x2B / 255)
    private static let beak = Color(red: 0xE0 / 255, green: 0x73 / 255, blue: 0x1A / 255)

    var body: some View {
        Canvas { context, canvasSize in
            let unit = min(canvasSize.width, canvasSize.height) / 30

            func ellipse(_ x: CGFloat, _ y: CGFloat, _ radiusX: CGFloat, _ radiusY: CGFloat) -> Path {
                Path(ellipseIn: CGRect(
                    x: (x - radiusX) * unit,
                    y: (y - radiusY) * unit,
                    width: radiusX * 2 * unit,
                    height: radiusY * 2 * unit
                ))
            }

            // Pattes, corps, ventre, yeux, bec : du fond vers le premier plan.
            context.fill(ellipse(11.2, 28.3, 3.4, 1.5), with: .color(Self.beak))
            context.fill(ellipse(18.8, 28.3, 3.4, 1.5), with: .color(Self.beak))
            context.fill(ellipse(15, 15.6, 10, 13), with: .color(Self.ink))
            context.fill(ellipse(15, 18.6, 6, 9), with: .color(.white))
            context.fill(ellipse(11.5, 9.1, 1.3, 1.3), with: .color(.white))
            context.fill(ellipse(18.5, 9.1, 1.3, 1.3), with: .color(.white))

            var beakPath = Path()
            beakPath.move(to: CGPoint(x: 12.5 * unit, y: 11.6 * unit))
            beakPath.addLine(to: CGPoint(x: 17.5 * unit, y: 11.6 * unit))
            beakPath.addLine(to: CGPoint(x: 15 * unit, y: 15.1 * unit))
            beakPath.closeSubpath()
            context.fill(beakPath, with: .color(Self.beak))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
