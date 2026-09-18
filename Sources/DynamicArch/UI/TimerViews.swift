import SwiftUI

// MARK: - Shared timeline

/// Drives every timer visual from one clock. The view reads the timer's state
/// and the current date; nothing here counts, so nothing here can drift. When
/// the timer is not running the timeline is paused outright, which means a
/// paused or finished timer costs nothing to display.
private struct TimerTimeline<Content: View>: View {
    let state: TimerState
    @ViewBuilder let content: (TimeInterval, Double) -> Content

    var body: some View {
        if state.phase == .running {
            TimelineView(.animation(minimumInterval: MotionPreference.timelineInterval)) { context in
                content(state.remaining(at: context.date), state.progress(at: context.date))
            }
        } else {
            // Static phases render once from the same derivation.
            content(state.remaining(), state.progress())
        }
    }
}

/// Monospaced digits so the countdown never jitters as glyph widths change.
private struct TimerReadout: View {
    let state: TimerState
    var size: CGFloat = 13
    var weight: Font.Weight = .semibold
    var color: Color = Palette.primaryText

    var body: some View {
        TimerTimeline(state: state) { _, _ in
            Text(state.display(at: .now))
                .font(.system(size: size, weight: weight, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .completionBlink(state.phase == .completed)
    }
}

/// A finished timer announces itself and then gets out of the way: the
/// readout pulses on a steady beat for a few seconds, which is long enough to
/// be noticed and short enough not to become furniture. The island clears
/// itself afterwards (see `TimerStore.complete`), so the blink and the
/// lifetime are deliberately the same length.
private struct CompletionBlink: ViewModifier {
    let active: Bool

    /// Four beats of half a second, autoreversed - just over four seconds.
    static let beat: Double = 0.5
    static let beats = 9
    static var duration: Double { beat * Double(beats) }

    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dimmed ? 0.28 : 1)
            .onAppear { start() }
            .onChange(of: active) { _, _ in start() }
    }

    private func start() {
        guard active, !MotionPreference.reducesMotion else {
            dimmed = false
            return
        }
        dimmed = false
        withAnimation(.easeInOut(duration: Self.beat).repeatCount(Self.beats, autoreverses: true)) {
            dimmed = true
        }
    }
}

private extension View {
    func completionBlink(_ active: Bool) -> some View {
        modifier(CompletionBlink(active: active))
    }
}

// MARK: - Ring

/// Circular progress with a soft leading cap. The trim is the timer's
/// progress, so it is exact at every frame rather than eased toward a target.
struct TimerRing: View {
    let state: TimerState
    var lineWidth: CGFloat = 3
    var tint: Color = Palette.warning
    /// Off when a readout sits inside the ring: two paused indicators in the
    /// same 90 pt circle just collide.
    var showsPausedGlyph = true

    var body: some View {
        TimerTimeline(state: state) { _, progress in
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.0001, progress))
                    .stroke(
                        AngularGradient(colors: [tint.opacity(0.75), tint],
                                        center: .center,
                                        startAngle: .degrees(-90),
                                        endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if state.phase == .paused, showsPausedGlyph {
                    Image(systemName: "pause.fill")
                        .font(.system(size: lineWidth * 2.2, weight: .black))
                        .foregroundStyle(tint)
                }
            }
            .opacity(state.phase == .paused ? 0.75 : 1)
        }
        .completionBlink(state.phase == .completed)
    }
}

// MARK: - Minimal progress bar

/// The fully collapsed state: a single bar with a travelling head.
///
/// The fill is the timer's progress and the head sits exactly at its leading
/// edge, so the bar cannot disagree with the clock. The only decorative motion
/// is a slow sheen behind the head, and that is dropped entirely under reduced
/// motion.
struct TimerMinimalBar: View {
    let state: TimerState
    var tint: Color = Palette.warning
    var height: CGFloat = 3

    var body: some View {
        TimerTimeline(state: state) { _, progress in
            GeometryReader { geometry in
                let width = geometry.size.width
                let filled = width * progress
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.16))

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(colors: [tint.opacity(0.55), tint],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(height, filled))

                    if state.phase == .running, !MotionPreference.reducesMotion {
                        // Head: a soft point of light at the frontier, which is
                        // what separates this from a loading bar.
                        Circle()
                            .fill(.white)
                            .frame(width: height * 1.9, height: height * 1.9)
                            .shadow(color: tint.opacity(0.9), radius: height)
                            .offset(x: max(0, filled - height * 0.95))
                    }
                }
                .frame(height: height)
                .opacity(state.phase == .paused ? 0.6 : 1)
            }
            .frame(height: height)
        }
    }
}

/// What the island shows in fully collapsed mode.
struct TimerMinimalView: View {
    let state: TimerState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            TimerMinimalBar(state: state, height: 4)
                .padding(.horizontal, Metrics.medium)
                .padding(.bottom, 2)
        }
    }
}

// MARK: - Collapsed pill

/// Collapsed: a ring and the remaining time, hugging the cutout. No
/// destructive control lives here - a stray click next to the menu bar must
/// never be able to throw away a running session.
struct TimerCompactView: View {
    let state: TimerState
    var showsLabel = false
    /// The collapsed island already carries a ring in its leading slot, so the
    /// trailing slot is the readout alone - two rings either side of the
    /// cutout just looked like a mistake.
    var showsRing = true

    var body: some View {
        HStack(spacing: Metrics.tight) {
            if showsRing {
                TimerRing(state: state, lineWidth: 2.5, tint: tint)
                    .frame(width: 14, height: 14)
            }
            TimerReadout(state: state, size: 12, color: tint)
            if showsLabel {
                Text(state.label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private var tint: Color {
        switch state.phase {
        case .completed: Palette.positive
        case .paused: Palette.secondaryText
        default: Palette.warning
        }
    }
}

/// Peek: the collapsed pill plus the two safe controls, which is where
/// pause/resume and reset become reachable without opening the panel.
struct TimerPeekControls: View {
    let state: TimerState
    private var store: TimerStore { TimerStore.shared }

    var body: some View {
        HStack(spacing: 5) {
            IslandButton(size: 22, tint: Palette.primaryText) {
                store.togglePause()
            } label: {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
            }
            IslandButton(size: 22, tint: Palette.secondaryText) {
                store.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
        }
    }

    private var symbol: String {
        switch state.phase {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .completed: "arrow.counterclockwise"
        case .idle: "play.fill"
        }
    }
}

// MARK: - Expanded panel

/// Expanded: the full control surface. Reset lives here, where there is room
/// for it to be labelled and hard to hit by accident.
struct TimerTabView: View {
    let model: IslandModel
    private var store: TimerStore { TimerStore.shared }

    var body: some View {
        Group {
            if store.state.isVisible {
                running(state: store.state)
            } else {
                picker
            }
        }
        .animation(Motion.content, value: store.state)
    }

    /// Running layout: the ring and its controls form one block, centred on
    /// both axes. The block is `panelWidth / phi` wide, so the margins either
    /// side of it are equal and in proportion to the panel.
    private func running(state: TimerState) -> some View {
        HStack(alignment: .center, spacing: Metrics.large) {
            ZStack {
                TimerRing(state: state, lineWidth: 6, tint: tint(for: state), showsPausedGlyph: false)
                    .frame(width: Metrics.ring, height: Metrics.ring)
                VStack(spacing: 1) {
                    TimerReadout(state: state, size: 20, weight: .bold, color: Palette.primaryText)
                    Text(statusText(for: state))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            // One short elastic beat marks the finish; it does not loop.
            .scaleEffect(store.justCompleted && !MotionPreference.reducesMotion ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: store.justCompleted)

            VStack(alignment: .leading, spacing: Metrics.medium) {
                HStack(spacing: Metrics.small) {
                    Text(state.label)
                        .font(Typography.title)
                        .foregroundStyle(Palette.primaryText)
                    Text(Self.durationText(state.configuredDuration))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tertiaryText)
                    Spacer(minLength: 0)
                }

                HStack(spacing: Metrics.small) {
                    Button {
                        state.phase == .completed ? store.restart() : store.togglePause()
                    } label: {
                        Label(primaryTitle(for: state), systemImage: primarySymbol(for: state))
                            .font(Typography.compact)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: tint(for: state).opacity(0.9), foreground: .black))

                    Button {
                        store.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(Typography.compact)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill, foreground: Palette.primaryText))
                    .disabled(state.configuredDuration <= 0)

                    Button {
                        store.extend(by: 300)
                    } label: {
                        Text("+5 min").font(Typography.compact)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill, foreground: Palette.primaryText))

                    Spacer(minLength: 0)
                }

                // Same control shape as the row above: a plain-style Button's
                // label does not reliably take a click in a non-key panel, and
                // two treatments read as two different kinds of thing.
                HStack(spacing: Metrics.small) {
                    Button {
                        model.setTimerMinimal(true)
                        model.close()
                    } label: {
                        Label("Minimise", systemImage: "minus.rectangle")
                            .font(Typography.caption)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill,
                                                    foreground: Palette.secondaryText))

                    Button {
                        store.clear()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .font(Typography.caption)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill,
                                                    foreground: Palette.secondaryText))

                    Spacer(minLength: 0)
                }
            }
            .frame(width: Metrics.textColumn, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var picker: some View {
        VStack(spacing: Metrics.medium) {
            Text("Start a timer")
                .font(Typography.title)
                .foregroundStyle(Palette.primaryText)

            HStack(spacing: Metrics.small) {
                ForEach(TimerStore.presets, id: \.self) { duration in
                    Button {
                        store.start(duration: duration)
                        withAnimation(Motion.content) { model.tab = .timer }
                    } label: {
                        Text(Self.durationText(duration))
                            .font(Typography.compact)
                            .frame(minWidth: Metrics.xlarge)
                    }
                    .buttonStyle(CapsuleButtonStyle(tint: Palette.controlFill, foreground: Palette.primaryText))
                }
            }

            Text("Collapse the island for a compact countdown, or minimise it to a progress bar under the notch.")
                .font(Typography.caption)
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.panelWidth / Metrics.phi)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func tint(for state: TimerState) -> Color {
        switch state.phase {
        case .completed: Palette.positive
        case .paused: Palette.secondaryText
        default: Palette.warning
        }
    }

    private func statusText(for state: TimerState) -> String {
        switch state.phase {
        case .running: "remaining"
        case .paused: "paused"
        case .completed: "finished"
        case .idle: "ready"
        }
    }

    private func primaryTitle(for state: TimerState) -> String {
        switch state.phase {
        case .running: "Pause"
        case .paused: "Resume"
        case .completed: "Start again"
        case .idle: "Start"
        }
    }

    private func primarySymbol(for state: TimerState) -> String {
        switch state.phase {
        case .running: "pause.fill"
        case .completed: "arrow.clockwise"
        default: "play.fill"
        }
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
        }
        return minutes > 0 ? "\(minutes)m" : "\(Int(duration))s"
    }
}

/// Home-grid entry point.
struct TimerTile: View {
    let model: IslandModel
    private var store: TimerStore { TimerStore.shared }

    var body: some View {
        if store.state.isVisible {
            VStack(spacing: 5) {
                TimerRing(state: store.state, lineWidth: 3)
                    .frame(width: 26, height: 26)
                TimerReadout(state: store.state, size: 11)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("Timer")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}
