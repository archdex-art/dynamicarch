import SwiftUI

/// The inline volume/brightness readout used by the HUD activities.
struct LevelBar: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geometry.size.width * min(1, max(0, value))))
                    .animation(Motion.value, value: value)
            }
        }
    }
}

struct RingProgress: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.value, value: fraction)
        }
    }
}
