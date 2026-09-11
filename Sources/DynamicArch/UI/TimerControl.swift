import SwiftUI

/// Start, pause, and cancel a timer without leaving the island. The running
/// timer also wraps the closed island as a live activity.
struct TimerControl: View {
    private var store: TimerStore { TimerStore.shared }

    var body: some View {
        if let running = store.running {
            VStack(spacing: 4) {
                RingProgress(fraction: running.fraction, tint: Palette.warning, lineWidth: 3)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Image(systemName: running.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.primaryText)
                    }
                    .onTapGesture { running.paused ? store.resume() : store.pause() }
                Text(running.display)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.primaryText)
                    .contentTransition(.numericText())
            }
            .onTapGesture(count: 2) { store.cancel() }
            .help("Tap to pause, double-tap to cancel")
        } else {
            Menu {
                ForEach([1, 5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) min") {
                        store.start(duration: TimeInterval(minutes) * 60, label: "\(minutes) min")
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                    Text("Timer")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}
