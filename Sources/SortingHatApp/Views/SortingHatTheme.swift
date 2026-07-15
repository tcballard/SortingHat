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

    private var hatColor: Color {
        active ? SortingHatTheme.amberBright : .white.opacity(0.58)
    }

    var body: some View {
        ZStack {
            WizardHatCrown()
                .fill(hatColor)
                .frame(width: 22, height: 18)
                .offset(y: -2)

            Capsule()
                .fill(hatColor)
                .frame(width: 25, height: 4)
                .offset(y: 7)

            Image(systemName: "sparkle")
                .font(.system(size: 6, weight: .black))
                .foregroundStyle(SortingHatTheme.ink.opacity(active ? 0.9 : 0.55))
                .offset(x: -2, y: 1)
        }
        .frame(width: 27, height: 24)
        .accessibilityHidden(true)
    }
}

private struct WizardHatCrown: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.08, 0.94))
        path.addCurve(
            to: point(0.50, 0.02),
            control1: point(0.20, 0.66),
            control2: point(0.31, 0.12)
        )
        path.addCurve(
            to: point(0.92, 0.36),
            control1: point(0.63, 0.14),
            control2: point(0.78, 0.40)
        )
        path.addCurve(
            to: point(0.72, 0.94),
            control1: point(0.83, 0.54),
            control2: point(0.80, 0.76)
        )
        path.closeSubpath()
        return path
    }
}
