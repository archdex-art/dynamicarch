import SwiftUI

enum Palette {
    /// The island body. Pure black so it is indistinguishable from the bezel on
    /// notched displays; the subtle top sheen keeps it from looking like a hole
    /// when it is expanded over bright content.
    static let body = Color.black
    static let hairline = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)
    static let controlFill = Color.white.opacity(0.10)
    static let controlFillHover = Color.white.opacity(0.18)
    static let accent = Color(nsColor: .controlAccentColor)
    static let positive = Color(red: 0.20, green: 0.82, blue: 0.44)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.18)
    static let danger = Color(red: 1.00, green: 0.30, blue: 0.28)
}

enum Typography {
    static let compact = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 10, weight: .medium, design: .rounded)
    static let title = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 15, weight: .bold, design: .rounded)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
}
