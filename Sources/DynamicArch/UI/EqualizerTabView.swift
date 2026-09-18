import SwiftUI

/// The equaliser section.
///
/// Layout follows the same proportional system as the rest of the island: the
/// band field takes the major share of the panel and the controls the minor
/// one, split on the golden ratio, so this section sits at the same rhythm as
/// Home and Timer rather than introducing its own.
struct EqualizerTabView: View {
    @State private var store = EqualizerStore.shared
    /// Band the pointer is over, or the one being dragged: drives the value
    /// readout and the highlight.
    @State private var focused: Int?

    private var state: EqualizerState { store.state }

    var body: some View {
        VStack(spacing: Metrics.small) {
            header
            presets
            BandField(store: store, focused: $focused)
                .frame(maxHeight: .infinity)
            footer
        }
        .onAppear { store.sync() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metrics.small) {
            PowerButton(isOn: state.isEnabled) { store.setEnabled(!state.isEnabled) }

            VStack(alignment: .leading, spacing: 1) {
                Text(store.activePreset?.name ?? (state.isFlat ? "Flat" : "Custom"))
                    .font(Typography.title)
                    .foregroundStyle(Palette.primaryText)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    StatusDot(isLive: store.isLive)
                    Text(statusLine)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .animation(Motion.content, value: store.statusDescription)

            Spacer(minLength: Metrics.small)

            if case .needsAccessibility = store.availability {
                Button {
                    Haptics.tap()
                    NotificationMirror.requestTrust()
                } label: {
                    Text("Grant Access")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.primaryText)
                        .padding(.horizontal, Metrics.small + 1)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.controlFillHover))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 34)
    }

    /// One line, and honest about scope: this drives Apple Music's own
    /// equaliser, so it says when something else is playing instead of
    /// implying the curve is affecting it.
    private var statusLine: String {
        if store.isLive, store.otherPlayerIsActive,
           let app = MediaStore.shared.track?.appName {
            return "Live in Apple Music · \(app) unaffected"
        }
        return store.statusDescription
    }

    // MARK: - Presets

    private var presets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Metrics.tight + 1) {
                ForEach(EqualizerPreset.all) { preset in
                    PresetChip(preset: preset,
                               isSelected: state.presetID == preset.id) {
                        withAnimation(Motion.value) { store.select(preset) }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        // Fades the row into the panel edges so a chip scrolled half out of
        // view looks intentional rather than clipped.
        .mask(
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black, location: 0.055),
                                   .init(color: .black, location: 0.945),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading,
                           endPoint: .trailing)
        )
        .frame(height: 30)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Metrics.medium) {
            PreampSlider(value: state.preamp) { store.setPreamp($0) }

            Button {
                withAnimation(Motion.value) { store.reset() }
                Haptics.tap()
            } label: {
                Label("Flat", systemImage: "arrow.counterclockwise")
                    .font(Typography.caption)
                    .foregroundStyle(state.isFlat ? Palette.tertiaryText : Palette.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(state.isFlat)
        }
        .frame(height: 26)
    }
}

// MARK: - Power

/// The on/off control. Deliberately the largest thing in the header: it is the
/// difference between the curve being audible and being decoration.
private struct PowerButton: View {
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            ZStack {
                Circle()
                    .fill(isOn ? Palette.accent.opacity(0.22) : Palette.controlFill)
                Circle()
                    .strokeBorder(isOn ? Palette.accent.opacity(0.55) : .white.opacity(0.08),
                                  lineWidth: 1)
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOn ? Palette.accent : Palette.secondaryText)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(Motion.press, value: hovering)
            .animation(Motion.value, value: isOn)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct StatusDot: View {
    let isLive: Bool

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(isLive ? Palette.positive : Palette.tertiaryText)
            .frame(width: 5, height: 5)
            .overlay {
                // A soft halo, only while the curve is actually in effect.
                Circle()
                    .stroke(Palette.positive.opacity(0.5), lineWidth: 1)
                    .scaleEffect(pulsing ? 2.4 : 1)
                    .opacity(pulsing ? 0 : 0.8)
            }
            .onAppear { restartPulse() }
            .onChange(of: isLive) { _, _ in restartPulse() }
    }

    private func restartPulse() {
        pulsing = false
        guard isLive, !MotionPreference.reducesMotion else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulsing = true
        }
    }
}

// MARK: - Preset chip

private struct PresetChip: View {
    let preset: EqualizerPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 4) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(preset.name)
                    .font(Typography.caption)
            }
            .foregroundStyle(isSelected ? Palette.primaryText : Palette.secondaryText)
            .padding(.horizontal, Metrics.small + 1)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Palette.accent.opacity(0.26)
                                     : (hovering ? Palette.controlFillHover : Palette.controlFill))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent.opacity(0.6) : .white.opacity(0.06),
                                  lineWidth: isSelected ? 1 : 0.7)
            }
            .scaleEffect(hovering && !isSelected ? 1.03 : 1)
            .animation(Motion.press, value: hovering)
            .animation(Motion.value, value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Band field

/// The bands, the response curve behind them, and the decibel grid.
private struct BandField: View {
    let store: EqualizerStore
    @Binding var focused: Int?

    /// Gain the drag started from, so a drag is an offset rather than an
    /// absolute jump to wherever the pointer landed.
    @State private var dragOrigin: [Int: Double] = [:]

    private var gains: [Double] { store.state.gains }
    private var isEnabled: Bool { store.state.isEnabled }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let travel = max(height - 22, 40)

            ZStack {
                DecibelGrid()

                ResponseCurve(values: AnimatableVector(gains), filled: true)
                    .fill(
                        LinearGradient(colors: [Palette.accent.opacity(isEnabled ? 0.30 : 0.10),
                                                Palette.accent.opacity(0)],
                                       startPoint: .top,
                                       endPoint: .bottom)
                    )
                ResponseCurve(values: AnimatableVector(gains), filled: false)
                    .stroke(
                        LinearGradient(colors: [Palette.accent.opacity(isEnabled ? 0.95 : 0.35),
                                                Palette.accent.opacity(isEnabled ? 0.55 : 0.2)],
                                       startPoint: .leading,
                                       endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    // The glow is what makes the curve read as audio rather
                    // than as a chart. Only when the curve is live.
                    .shadow(color: Palette.accent.opacity(isEnabled ? 0.45 : 0), radius: 7)
                    .padding(.vertical, 11)

                HStack(spacing: 0) {
                    ForEach(0..<EqualizerState.bandCount, id: \.self) { index in
                        BandSlider(index: index,
                                   gain: gains[index],
                                   travel: travel,
                                   isEnabled: isEnabled,
                                   isFocused: focused == index)
                            .frame(maxWidth: .infinity)
                            .onHover { inside in
                                withAnimation(Motion.press) {
                                    focused = inside ? index : (focused == index ? nil : focused)
                                }
                            }
                            .gesture(drag(index: index, travel: travel))
                    }
                }
            }
            .animation(store.isAdjusting ? nil : Motion.value, value: AnimatableVector(gains).values)
        }
    }

    /// Vertical drag, scaled so the full slider travel spans the full +/-12 dB
    /// range. The gain is recomputed from the gesture's total translation each
    /// time, which keeps it exact however many events are delivered.
    private func drag(index: Int, travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOrigin[index] == nil {
                    dragOrigin[index] = store.state.gains[index]
                    store.isAdjusting = true
                    focused = index
                    Haptics.tick()
                }
                let span = EqualizerState.gainRange.upperBound - EqualizerState.gainRange.lowerBound
                let delta = -value.translation.height / travel * span
                store.setGain((dragOrigin[index] ?? 0) + delta, forBand: index)
            }
            .onEnded { _ in
                dragOrigin[index] = nil
                store.isAdjusting = false
                Haptics.tap()
            }
    }
}

/// Faint reference lines at 0 and +/-6 dB. The zero line is brighter: it is
/// the one the eye uses to judge the curve.
private struct DecibelGrid: View {
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = EqualizerState.gainRange.upperBound - EqualizerState.gainRange.lowerBound

            ZStack {
                ForEach([6.0, 0.0, -6.0], id: \.self) { decibels in
                    let y = height / 2 - CGFloat(decibels / span) * (height - 22)
                    Rectangle()
                        .fill(.white.opacity(decibels == 0 ? 0.10 : 0.05))
                        .frame(height: decibels == 0 ? 1 : 0.5)
                        .position(x: geometry.size.width / 2, y: y)
                }
            }
        }
    }
}

/// One band: track, fill from the zero line, knob, and its label.
private struct BandSlider: View {
    let index: Int
    let gain: Double
    let travel: CGFloat
    let isEnabled: Bool
    let isFocused: Bool

    private var fraction: Double {
        let span = EqualizerState.gainRange.upperBound - EqualizerState.gainRange.lowerBound
        return gain / span
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.07))
                    .frame(width: 3)

                // Fill grows from the centre in the direction of the gain, so
                // a cut reads as clearly as a boost.
                Capsule()
                    .fill(isEnabled ? Palette.accent.opacity(0.8) : Palette.tertiaryText.opacity(0.5))
                    .frame(width: 3, height: abs(CGFloat(fraction)) * travel)
                    .offset(y: -CGFloat(fraction) * travel / 2)

                Knob(isFocused: isFocused, isEnabled: isEnabled)
                    .offset(y: -CGFloat(fraction) * travel)

                if isFocused {
                    Text(Self.format(gain))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.primaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .offset(y: -CGFloat(fraction) * travel - 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: travel)
            .frame(maxHeight: .infinity)
            // The whole column is the target, not just the 12 pt knob.
            .contentShape(Rectangle())

            Text(EqualizerState.label(forBand: index))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isFocused ? Palette.secondaryText : Palette.tertiaryText)
        }
    }

    static func format(_ gain: Double) -> String {
        let rounded = (gain * 2).rounded() / 2
        if rounded == 0 { return "0" }
        let body = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        return rounded > 0 ? "+\(body)" : body
    }
}

private struct Knob: View {
    let isFocused: Bool
    let isEnabled: Bool

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 11, height: 11)
            .overlay {
                Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .overlay {
                Circle()
                    .fill(isEnabled ? Palette.accent : Palette.tertiaryText)
                    .frame(width: 4, height: 4)
            }
            .scaleEffect(isFocused ? 1.25 : 1)
            .animation(Motion.press, value: isFocused)
    }
}

// MARK: - Preamp

/// Horizontal, and clearly subordinate to the bands: it is a level trim, not
/// part of the curve.
private struct PreampSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    @State private var dragOrigin: Double?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Metrics.small) {
            Text("Preamp")
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)

            GeometryReader { geometry in
                // One mapping for every part of the control. The knob used to
                // be placed by an offset from the leading edge while the fill
                // was placed from the centre, so the two only agreed at 0 dB
                // and drifted apart as the value moved.
                let width = geometry.size.width
                let span = EqualizerState.gainRange.upperBound - EqualizerState.gainRange.lowerBound
                let zero = width / 2
                let x = zero + CGFloat(value / span) * width
                let midY = geometry.size.height / 2

                ZStack {
                    Capsule()
                        .fill(.white.opacity(0.07))
                        .frame(width: width, height: 3)
                        .position(x: zero, y: midY)
                    // Fill runs from the centre, like the bands: a preamp of
                    // 0 dB drawn as a half-full bar reads as "half volume",
                    // which it is not.
                    Capsule()
                        .fill(Palette.accent.opacity(0.75))
                        .frame(width: abs(x - zero), height: 3)
                        .position(x: (x + zero) / 2, y: midY)
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .scaleEffect(hovering ? 1.2 : 1)
                        .animation(Motion.press, value: hovering)
                        .position(x: x, y: midY)
                }
                .frame(width: width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { drag in
                            if dragOrigin == nil { dragOrigin = value }
                            let delta = drag.translation.width / width * span
                            onChange((dragOrigin ?? 0) + delta)
                        }
                        .onEnded { _ in dragOrigin = nil; Haptics.tap() }
                )
                .onHover { hovering = $0 }
            }
            .frame(height: 14)

            // Wide enough for the longest reading ("-11.5 dB") and fixed, so
            // the slider beside it does not resize as the number changes.
            Text("\(BandSlider.format(value)) dB")
                .font(Typography.mono)
                .monospacedDigit()
                .foregroundStyle(Palette.tertiaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 62, alignment: .trailing)
        }
    }
}

// MARK: - Curve

/// A smooth curve through the band gains.
///
/// Catmull-Rom rather than straight segments, because a graphic equaliser's
/// audible response between two band centres is a curve, not a corner - and
/// the control points animate as one `AnimatableVector`, so switching presets
/// sweeps the whole shape instead of redrawing it.
private struct ResponseCurve: Shape {
    var values: AnimatableVector
    let filled: Bool

    var animatableData: AnimatableVector {
        get { values }
        set { values = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let gains = values.values
        guard gains.count >= 2 else { return Path() }

        let span = EqualizerState.gainRange.upperBound - EqualizerState.gainRange.lowerBound
        let step = rect.width / CGFloat(gains.count)
        // Band knobs sit at the centre of their column, so the curve's control
        // points must too, or curve and knobs disagree by half a column.
        var points = gains.enumerated().map { index, gain in
            CGPoint(x: rect.minX + step * (CGFloat(index) + 0.5),
                    y: rect.midY - CGFloat(gain / span) * rect.height)
        }
        // Flat shoulders so the fill reaches both edges.
        points.insert(CGPoint(x: rect.minX, y: points[0].y), at: 0)
        points.append(CGPoint(x: rect.maxX, y: points[points.count - 1].y))

        var path = Path()
        path.move(to: points[0])
        let last = points.count - 1
        for index in 0..<last {
            let p1 = points[index]
            let p2 = points[index + 1]
            // The shoulder segments are drawn flat. A spline through them
            // borrows its tangent from the second band, which bows the curve
            // above its own starting level before it has left the edge - a
            // visible overshoot that claims gain the band does not have.
            if index == 0 || index == last - 1 {
                path.addLine(to: p2)
                continue
            }
            let p0 = points[max(index - 1, 0)]
            let p3 = points[min(index + 2, last)]
            // Catmull-Rom to Bezier: tangents are a sixth of the neighbouring
            // span, which is the uniform form of the spline.
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        if filled {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
        return path
    }
}
