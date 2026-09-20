import SwiftUI

/// The island's standard pressable. Hover lifts it, press compresses it, and
/// both use the shared motion vocabulary so every control feels identical.
struct IslandButton<Label: View>: View {
    var size: CGFloat = 30
    var tint: Color = Palette.primaryText
    var filled = false
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var hovering = false

    var body: some View {
        // A real Button, not a tap-gesture stack: a `DragGesture` on the label
        // recognises the mouse-down and then swallows the click, so the action
        // never fires. `ButtonStyle` also gives us the pressed state for free.
        Button {
            Haptics.tap()
            action()
        } label: {
            label
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle(size: size, filled: filled, hovering: hovering))
        .onHover { hovering = $0 }
    }
}

private struct IslandButtonStyle: ButtonStyle {
    let size: CGFloat
    let filled: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(filled ? Palette.controlFillHover : (hovering ? Palette.controlFill : .clear))
            }
            .scaleEffect(configuration.isPressed ? 0.88 : (hovering ? 1.06 : 1))
            .animation(Motion.press, value: configuration.isPressed)
            .animation(Motion.press, value: hovering)
    }
}

/// Tile used by the home grid and quick actions.
struct IslandTile<Content: View>: View {
    var title: String?
    var tint: Color = Palette.controlFill
    var action: (() -> Void)?
    @ViewBuilder let content: Content

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            content
            if let title {
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovering ? Palette.controlFillHover : tint)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.16 : 0.07), lineWidth: 0.7)
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(Motion.press, value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { action.map { Haptics.tap(); $0() } }
    }
}
