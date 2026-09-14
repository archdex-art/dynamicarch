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
        case .dark, .nothing: .black
        case .light: Color(white: 0.97)
        case .glass: Color.white.opacity(0.08)
        }
    }

    static var hairline: Color {
        switch theme {
        case .dark: .white.opacity(0.08)
        case .light: .black.opacity(0.10)
        case .glass: .white.opacity(0.28)
        case .nothing: .white.opacity(0.16)
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
        case .nothing: .white.opacity(0.07)
        }
    }

    static var controlFillHover: Color {
        switch theme {
        case .dark: .white.opacity(0.18)
        case .light: .black.opacity(0.12)
        case .glass: .white.opacity(0.26)
        case .nothing: .white.opacity(0.14)
        }
    }

    /// Confirmation sheets need to stay legible over whatever is behind them,
    /// so they are opaque even on the glass theme.
    static var confirmationBackground: Color {
        switch theme {
        case .dark: Color(white: 0.10)
        case .light: Color(white: 0.98)
        case .glass: Color(white: 0.12).opacity(0.96)
        case .nothing: Color(white: 0.06)
        }
    }

    /// Nothing's single red accent replaces the system tint on that theme.
    static var accent: Color {
        theme == .nothing ? nothingRed : Color(nsColor: .controlAccentColor)
    }

    static let nothingRed = Color(red: 0.84, green: 0.10, blue: 0.13)
    static let positive = Color(red: 0.20, green: 0.82, blue: 0.44)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.18)
    static let danger = Color(red: 1.00, green: 0.30, blue: 0.28)
}

enum Typography {
    /// Nothing OS sets everything in a dot-matrix face; monospaced is the
    /// closest thing we can rely on being installed, and it carries the same
    /// mechanical rhythm.
    private static var design: Font.Design {
        Palette.theme == .nothing ? .monospaced : .rounded
    }

    static var compact: Font { .system(size: 11, weight: .semibold, design: design) }
    static var caption: Font { .system(size: 10, weight: .medium, design: design) }
    static var title: Font { .system(size: 13, weight: .semibold, design: design) }
    static var headline: Font { .system(size: 15, weight: .bold, design: design) }
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
}
