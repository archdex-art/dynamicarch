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
    @State private var pressed = false

    var body: some View {
        label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(filled ? Palette.controlFillHover : (hovering ? Palette.controlFill : .clear))
            }
            .scaleEffect(pressed ? 0.88 : (hovering ? 1.06 : 1))
            .animation(Motion.press, value: pressed)
            .animation(Motion.press, value: hovering)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { value in
                        pressed = false
                        let inBounds = abs(value.translation.width) < size && abs(value.translation.height) < size
                        if inBounds {
                            Haptics.tap()
                            action()
                        }
                    }
            )
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
