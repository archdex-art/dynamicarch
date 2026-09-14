import SwiftUI

/// Semantic colours for the island, resolved against the active theme.
///
/// The theme is mirrored into a plain static so every call site - including the
/// non-UI code that builds activities - can read it without actor hops. The
/// mirror is written only by `Preferences`, which is the single source of truth.
enum Palette {
    nonisolated(unsafe) static var theme: IslandTheme = .dark

    /// The island body. Black on the dark theme so it is indistinguishable from
    /// the bezel when idle.
    static var body: Color {
        switch theme {
        case .dark: .black
        case .light: Color(white: 0.97)
        case .glass: Color.white.opacity(0.08)
        }
    }

    static var hairline: Color {
        switch theme {
        case .dark: .white.opacity(0.08)
        case .light: .black.opacity(0.10)
        case .glass: .white.opacity(0.28)
        }
    }

    static var primaryText: Color {
        theme.isLight ? Color(white: 0.08) : .white
    }

    static var secondaryText: Color {
        theme.isLight ? Color(white: 0.32) : .white.opacity(0.62)
    }

    static var tertiaryText: Color {
        theme.isLight ? Color(white: 0.50) : .white.opacity(0.38)
    }

    static var controlFill: Color {
        switch theme {
        case .dark: .white.opacity(0.10)
        case .light: .black.opacity(0.06)
        case .glass: .white.opacity(0.16)
        }
    }

    static var controlFillHover: Color {
        switch theme {
        case .dark: .white.opacity(0.18)
        case .light: .black.opacity(0.12)
        case .glass: .white.opacity(0.26)
        }
    }

    /// Confirmation sheets need to stay legible over whatever is behind them,
    /// so they are opaque even on the glass theme.
    static var confirmationBackground: Color {
        switch theme {
        case .dark: Color(white: 0.10)
        case .light: Color(white: 0.98)
        case .glass: Color(white: 0.12).opacity(0.96)
        }
    }

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
