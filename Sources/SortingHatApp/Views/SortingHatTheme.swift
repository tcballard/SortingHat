import SwiftUI

enum SortingHatTheme {
    static let amber = Color(red: 0.94, green: 0.66, blue: 0.20)
    static let amberBright = Color(red: 1.00, green: 0.78, blue: 0.32)
    static let ink = Color(red: 0.035, green: 0.055, blue: 0.085)
    static let midnight = Color(red: 0.065, green: 0.09, blue: 0.13)
    static let parchment = Color(red: 0.97, green: 0.95, blue: 0.90)

    static func canvas(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? ink : parchment
    }

    static func statusSurface(for colorScheme: ColorScheme, increasedContrast: Bool) -> LinearGradient {
        let leading = colorScheme == .dark ? ink : Color(red: 0.13, green: 0.14, blue: 0.16)
        let trailing = colorScheme == .dark ? midnight : Color(red: 0.20, green: 0.18, blue: 0.14)
        return LinearGradient(
            colors: increasedContrast ? [leading, leading] : [leading, trailing],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct WizardHatSymbol: View {
    var active = true
    var size: CGFloat = 30

    private var hatColor: Color {
        active ? SortingHatTheme.amberBright : .white.opacity(0.58)
    }

    var body: some View {
        WizardHatSilhouette()
            .fill(hatColor)
            .frame(width: size * 29 / 30, height: size * 25 / 30)
            .frame(width: size, height: size * 26 / 30)
        .accessibilityHidden(true)
    }
}

private struct WizardHatSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()

        // Crooked crown and folded tip.
        path.move(to: point(0.30, 0.68))
        path.addLine(to: point(0.39, 0.28))
        path.addLine(to: point(0.51, 0.22))
        path.addLine(to: point(0.55, 0.05))
        path.addLine(to: point(0.68, 0.00))
        path.addLine(to: point(0.77, 0.18))
        path.addLine(to: point(0.88, 0.10))
        path.addLine(to: point(0.80, 0.29))
        path.addLine(to: point(0.72, 0.25))
        path.addCurve(
            to: point(0.77, 0.68),
            control1: point(0.73, 0.41),
            control2: point(0.79, 0.58)
        )
        path.addCurve(to: point(0.30, 0.68), control1: point(0.62, 0.73), control2: point(0.43, 0.73))
        path.closeSubpath()

        // Uneven hat band.
        path.move(to: point(0.27, 0.64))
        path.addCurve(to: point(0.78, 0.67), control1: point(0.43, 0.71), control2: point(0.64, 0.73))
        path.addLine(to: point(0.75, 0.78))
        path.addCurve(to: point(0.26, 0.75), control1: point(0.57, 0.83), control2: point(0.39, 0.80))
        path.closeSubpath()

        // Wide, swept brim with a nicked trailing edge.
        path.move(to: point(0.03, 0.89))
        path.addCurve(
            to: point(0.29, 0.73),
            control1: point(0.12, 0.83),
            control2: point(0.21, 0.76)
        )
        path.addCurve(to: point(0.93, 0.78), control1: point(0.50, 0.79), control2: point(0.73, 0.70))
        path.addLine(to: point(0.84, 0.89))
        path.addLine(to: point(0.78, 0.87))
        path.addLine(to: point(0.81, 0.95))
        path.addLine(to: point(0.73, 0.90))
        path.addCurve(
            to: point(0.03, 0.89),
            control1: point(0.48, 1.01),
            control2: point(0.25, 0.84)
        )
        path.closeSubpath()
        return path
    }
}
