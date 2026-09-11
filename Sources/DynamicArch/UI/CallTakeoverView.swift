import SwiftUI

/// An incoming call owns the whole island until it is answered or declined.
struct CallTakeoverView: View {
    let call: CallCenter.Call

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Palette.positive.opacity(0.25))
                    .scaleEffect(pulse ? 1.25 : 1)
                    .opacity(pulse ? 0 : 1)
                if let icon = call.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 54, height: 54)
                } else {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.positive)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Palette.controlFill))
                }
            }
            .frame(width: 64, height: 64)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(call.caller)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                Text(call.subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if call.declineTitle != nil {
                    CallActionButton(symbol: "phone.down.fill", tint: Palette.danger) {
                        CallCenter.shared.decline()
                    }
                }
                if call.acceptTitle != nil {
                    CallActionButton(symbol: "phone.fill", tint: Palette.positive) {
                        CallCenter.shared.accept()
                    }
                }
                if call.acceptTitle == nil, call.declineTitle == nil {
                    CallActionButton(symbol: "xmark", tint: Palette.secondaryText) {
                        CallCenter.shared.clear()
                    }
                }
            }
        }
    }
}

private struct CallActionButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(tint.opacity(hovering ? 1 : 0.85)))
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(Motion.press, value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { Haptics.tap(); action() }
    }
}
