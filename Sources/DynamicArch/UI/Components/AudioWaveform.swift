import SwiftUI

/// Playback-reactive bars. Driven by a single TimelineView so the whole set
/// animates from one clock instead of N independent animations, and it stops
/// completely when audio is paused - no idle CPU, no timers left running.
struct AudioWaveform: View {
    var accent: Color = Palette.accent
    var isActive: Bool
    var barCount: Int = 4

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
                bars(in: geometry.size, heights: heights(at: context.date))
            }
        }
    }

    private func heights(at date: Date) -> [Double] {
        guard isActive else { return Array(repeating: 0.28, count: barCount) }
        let time = date.timeIntervalSinceReferenceDate
        return (0..<barCount).map { index in
            // Different phase and a second harmonic per bar: reads as audio,
            // not as a row of synchronised sine waves.
            let phase = time * 3.1 + Double(index) * 0.8
            let base = abs(sin(phase))
            let detail = 0.25 * abs(sin(phase * 1.7 + 0.4))
            return min(1, 0.30 + 0.6 * base + detail)
        }
    }

    private func bars(in size: CGSize, heights: [Double]) -> some View {
        let spacing = size.width / CGFloat(barCount * 2 - 1)
        return HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(width: spacing, height: max(2, size.height * heights[index]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
