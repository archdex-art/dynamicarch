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
                .fill(Color.black.opacity(0.70 + 0.30 * (1 - Preferences.shared.glassTransparency)))
                .overlay { shape.stroke(Palette.hairline, lineWidth: 0.7).opacity(isOpen ? 1 : 0) }
                .shadow(color: accent.opacity(isOpen ? 0.28 : 0), radius: 26, y: 8)
                .shadow(color: .black.opacity(isOpen ? 0.55 : 0), radius: 18, y: 10)

        case .light:
            shape
                .fill(Color(white: 0.97).opacity(0.74 + 0.26 * (1 - Preferences.shared.glassTransparency)))
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
        // Transparency trades legibility for see-through: 0 is chrome, 1 is as
        // clear as a blurred backdrop can be.
        let transparency = min(1, max(0, Preferences.shared.glassTransparency))
        // A floor on the veil: at full transparency the material matches
        // whatever is behind it and the island's own content becomes
        // unreadable, which is a broken state rather than a preference.
        let veil = 0.12 + 0.38 * (1 - transparency)

        return ZStack {
            // The real refraction: a behind-window blur samples the desktop and
            // windows underneath, so the island genuinely carries what is
            // behind it rather than faking a frosted colour.
            VisualEffectBackdrop(material: .underWindowBackground,
                                 blending: .behindWindow,
                                 emphasized: false)
                .clipShape(shape)

            // Lensing: a second, slightly scaled copy of the same backdrop,
            // visible only in a band along the edges. Magnifying the blur near
            // the rim is what an actual thick pane does to whatever is behind
            // it, and it replaces the old bloom entirely.
            VisualEffectBackdrop(material: .fullScreenUI,
                                 blending: .behindWindow,
                                 emphasized: false)
                .scaleEffect(x: 1.08, y: 1.14, anchor: .center)
                .clipShape(shape)
                .mask {
                    shape
                        .stroke(Color.black, lineWidth: 14)
                        .blur(radius: 5)
                }
                .opacity(0.9)

            // Just enough darkening to keep white text readable, flat rather
            // than a gradient so there is no hotspot anywhere.
            shape.fill(Color.black.opacity(veil))

            // Thickness, drawn as shadow rather than light: a soft inner
            // darkening at the very edge reads as a bevelled pane, where a
            // bright stroke read as an outline and a radial highlight read as
            // glow.
            shape
                .stroke(Color.black.opacity(0.22), lineWidth: 6)
                .blur(radius: 4)
                .clipShape(shape)
        }
        .compositingGroup()
        // No accent bloom: only a contact shadow, so the island sits on the
        // desktop instead of glowing over it.
        .shadow(color: .black.opacity(isOpen ? 0.28 : 0), radius: 12, y: 6)
    }
}
