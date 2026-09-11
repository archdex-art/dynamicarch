import AppKit
import SwiftUI

enum IslandTheme: String, CaseIterable, Identifiable, Codable {
    /// The default: a black island that is invisible against the bezel.
    case dark
    /// A light island for bright desktops.
    case light
    /// Translucent glass that refracts whatever is behind the island, in the
    /// spirit of the macOS Tahoe material.
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .glass: "Glass"
        }
    }

    var symbol: String {
        switch self {
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        case .glass: "drop.halffull"
        }
    }

    var subtitle: String {
        switch self {
        case .dark: "Matches the bezel - the island disappears when idle."
        case .light: "Bright chrome with dark text."
        case .glass: "The Dock's material: the desktop showing through, nothing added."
        }
    }

    /// Glass and light chrome want light content behind them; dark chrome wants
    /// the dark appearance so system controls match.
    var appearance: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark, .glass: .darkAqua
        }
    }

    var isLight: Bool { self == .light }
}

/// A `NSVisualEffectView` with behind-window blending: this is what makes the
/// glass theme refract the desktop and windows underneath the island rather
/// than just looking grey.
struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.isEmphasized = emphasized
    }
}

/// The island's body, themed.
///
/// Glass is built in layers, because a single translucent fill reads as fog:
/// a behind-window blur that bends the desktop, a faint tint, a bright inner
/// top edge where light would catch, and a rim that is brightest where the
/// curvature is steepest.
struct IslandSurface: View {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    var accent: Color
    var isOpen: Bool
    /// True when the island is at rest with nothing to show. It then has to be
    /// literally invisible - a light or glass rim around an empty notch looks
    /// like a rendering bug, because that is what it is.
    var isIdle: Bool = false

    private var shape: NotchShape { NotchShape(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
        if isIdle {
            // Matches the bezel exactly, on every theme.
            shape.fill(Color.black)
        } else {
            themed
        }
    }

    @ViewBuilder
    private var themed: some View {
        switch Palette.theme {
        case .dark:
            shape
                .fill(Color.black)
                .overlay { shape.stroke(Palette.hairline, lineWidth: 0.7).opacity(isOpen ? 1 : 0) }
                .shadow(color: accent.opacity(isOpen ? 0.28 : 0), radius: 26, y: 8)
                .shadow(color: .black.opacity(isOpen ? 0.55 : 0), radius: 18, y: 10)

        case .light:
            shape
                .fill(Color(white: 0.97))
                .overlay {
                    shape.stroke(Color.black.opacity(0.10), lineWidth: 0.8).opacity(isOpen ? 1 : 0)
                }
                .shadow(color: accent.opacity(isOpen ? 0.22 : 0), radius: 22, y: 8)
                .shadow(color: .black.opacity(isOpen ? 0.30 : 0), radius: 16, y: 8)

        case .glass:
            glass
        }
    }

    /// Modelled directly on the Dock: one behind-window blur of the desktop, a
    /// faint light hairline where the pane catches the sky, and nothing else.
    /// The Dock has no bloom, no gradient wash and no coloured tint, which is
    /// exactly why it reads as glass instead of as a glowing panel.
    private var glass: some View {
        ZStack {
            VisualEffectBackdrop(material: .hudWindow,
                                 blending: .behindWindow,
                                 emphasized: false)
                .clipShape(shape)

            // The Dock's hairline: a single hair of light, an order of
            // magnitude fainter than a specular rim, and uniform rather than
            // brightest at the top.
            shape
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .compositingGroup()
        // Contact shadow only - the Dock casts one, it does not glow.
        .shadow(color: .black.opacity(isOpen ? 0.32 : 0.12), radius: 10, y: 4)
    }
}
