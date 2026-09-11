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
        case .glass: "Refracts the desktop underneath, like Tahoe's glass."
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

    private var shape: NotchShape { NotchShape(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
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

    private var glass: some View {
        ZStack {
            VisualEffectBackdrop(material: .hudWindow, blending: .behindWindow)
                .clipShape(shape)

            // Tint: a hint of the accent so album art and activities bleed into
            // the material instead of sitting on top of it.
            shape
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.16), accent.opacity(0.10)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .blendMode(.plusLighter)

            // Specular edge, brightest along the top where light would hit.
            shape
                .stroke(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.55), location: 0),
                        .init(color: .white.opacity(0.12), location: 0.45),
                        .init(color: .white.opacity(0.30), location: 1)
                    ], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9
                )

            // Light catching the bottom curvature, which is what sells the
            // impression of a thick refracting slab.
            shape
                .fill(
                    RadialGradient(colors: [.white.opacity(0.22), .clear],
                                   center: .bottom, startRadius: 0, endRadius: 120)
                )
                .blendMode(.plusLighter)
                .opacity(isOpen ? 1 : 0.4)
        }
        .compositingGroup()
        .shadow(color: accent.opacity(isOpen ? 0.30 : 0.10), radius: 24, y: 10)
        .shadow(color: .black.opacity(isOpen ? 0.35 : 0), radius: 14, y: 8)
    }
}
