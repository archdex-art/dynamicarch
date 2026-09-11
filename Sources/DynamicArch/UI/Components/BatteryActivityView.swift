import SwiftUI

/// The battery itself: an outline that fills to the real charge level, with a
/// travelling shimmer while charging and a breathing glow when the charge is
/// low. Everything is driven from one `TimelineView` clock, and the clock only
/// runs while there is something to animate - a static battery costs nothing.
struct BatteryCapsule: View {
    var level: Double
    var state: IslandActivity.BatteryState
    var height: CGFloat = 15

    private var width: CGFloat { height * 2.05 }
    private var animates: Bool { state.isCharging || state.isWarning }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            body(phase: phase)
        }
    }

    private func body(phase: TimeInterval) -> some View {
        // Charging sweeps a highlight across the fill; a low battery breathes.
        let sweep = state.isCharging ? (sin(phase * 1.9) + 1) / 2 : 0.5
        let breathe = state.isWarning ? 0.55 + 0.45 * (sin(phase * 2.6) + 1) / 2 : 1

        return HStack(spacing: height * 0.12) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, height * 0.075))

                fill(sweep: sweep)
                    .padding(height * 0.14)

                if state.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.62, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: state.tint.opacity(0.9), radius: 3)
                        .frame(width: width, alignment: .center)
                        .scaleEffect(1 + 0.08 * sin(phase * 3.4))
                } else if state.isWarning {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: height * 0.6, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: width, alignment: .center)
                        .opacity(breathe)
                }
            }
            .frame(width: width, height: height)

            // Terminal nub.
            RoundedRectangle(cornerRadius: height * 0.1, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: height * 0.1, height: height * 0.34)
        }
        .shadow(color: state.tint.opacity(animates ? 0.55 * breathe : 0), radius: height * 0.55)
        .animation(Motion.value, value: level)
    }

    private func fill(sweep: Double) -> some View {
        GeometryReader { geometry in
            let usable = geometry.size.width
            let clamped = min(1, max(0.04, level))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.2, style: .continuous)
                    .fill(
                        LinearGradient(colors: [state.tint.opacity(0.75), state.tint],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: usable * clamped)
                    .opacity(state.isWarning ? 0.9 : 1)

                if state.isCharging {
                    // A soft highlight that travels along the charged portion.
                    RoundedRectangle(cornerRadius: height * 0.2, style: .continuous)
                        .fill(
                            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(6, usable * 0.32))
                        .offset(x: (usable * clamped - usable * 0.32) * sweep)
                        .clipShape(RoundedRectangle(cornerRadius: height * 0.2, style: .continuous))
                        .frame(width: usable * clamped, alignment: .leading)
                        .blendMode(.plusLighter)
                }
            }
            .frame(height: geometry.size.height)
        }
    }
}

/// Trailing half of the battery activity: what happened, and what it means.
struct BatteryActivityDetail: View {
    var level: Double
    var state: IslandActivity.BatteryState
    var detail: String?

    private var title: String {
        switch state {
        case .charging: "Charging"
        case .charged: "Fully Charged"
        case .unplugged: "On Battery"
        case .low: "Low Battery"
        case .critical: "Battery Critical"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(title)
                    .font(Typography.compact)
                    .foregroundStyle(Palette.primaryText)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .lineLimit(1)

            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(state.tint)
                .contentTransition(.numericText())
                .animation(Motion.value, value: level)
        }
    }
}
