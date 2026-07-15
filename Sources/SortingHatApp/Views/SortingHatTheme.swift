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
