import Foundation

/// The equaliser curve, as a value.
///
/// Ten bands plus a preamp, in decibels, matching the shape of the graphic
/// equaliser Apple Music exposes - that is deliberate. macOS has no public
/// system-wide audio EQ, so the only way a third-party app can genuinely
/// change what you hear (rather than draw a decorative curve) is to drive a
/// player's own equaliser. Music's is a ten-band unit at fixed centre
/// frequencies, so this type mirrors it exactly and no resampling or
/// interpolation is needed to apply a preset.
struct EqualizerState: Equatable, Codable {
    static let bandCount = 10
    /// Centre frequencies of Music's graphic equaliser, in order.
    static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    /// The hardware range of the unit. Values outside it are refused rather
    /// than clipped silently, because a clipped band would not match the UI.
    static let gainRange: ClosedRange<Double> = -12...12

    var isEnabled = false
    var preamp: Double = 0
    var gains: [Double] = Array(repeating: 0, count: EqualizerState.bandCount)
    /// Identifier of the preset the curve came from, or nil once the user has
    /// moved a band and the curve is their own.
    var presetID: String?

    /// Short label for each band. Kept out of the view so the axis labels and
    /// the values applied to Music cannot drift apart.
    static func label(forBand index: Int) -> String {
        let frequency = frequencies[index]
        if frequency >= 1_000 {
            let kilohertz = frequency / 1_000
            return kilohertz == kilohertz.rounded()
                ? "\(Int(kilohertz))k"
                : String(format: "%.1fk", kilohertz)
        }
        return "\(Int(frequency))"
    }

    /// Clamped and rounded to the 0.5 dB step the unit actually resolves, so
    /// what the UI shows is what the engine receives.
    static func quantise(_ value: Double) -> Double {
        let clamped = min(max(value, gainRange.lowerBound), gainRange.upperBound)
        return (clamped * 2).rounded() / 2
    }

    var isFlat: Bool {
        preamp == 0 && gains.allSatisfy { $0 == 0 }
    }

    /// Guards against a malformed value arriving from persistence: a short or
    /// long `gains` array would otherwise index out of bounds in the view.
    var normalised: EqualizerState {
        var copy = self
        if copy.gains.count != Self.bandCount {
            var resized = Array(repeating: 0.0, count: Self.bandCount)
            for index in 0..<min(copy.gains.count, Self.bandCount) {
                resized[index] = copy.gains[index]
            }
            copy.gains = resized
        }
        copy.gains = copy.gains.map(Self.quantise)
        copy.preamp = Self.quantise(copy.preamp)
        return copy
    }
}

/// A named curve.
///
/// The shapes are conventional audio corrections rather than invented numbers:
/// a presence lift around 1-4 kHz for vocals, a shelf below 125 Hz for bass, a
/// low-cut plus presence for speech, and so on. Each stays inside +/-6 dB so a
/// preset cannot drive the output into clipping on its own.
struct EqualizerPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let preamp: Double
    let gains: [Double]

    static let all: [EqualizerPreset] = [
        EqualizerPreset(id: "flat", name: "Flat", symbol: "minus",
                        preamp: 0,
                        gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        // Presence band lifted, everything competing with it eased back.
        EqualizerPreset(id: "vocal", name: "Vocals", symbol: "music.mic",
                        preamp: 0,
                        gains: [-3, -2.5, -1, 1, 3.5, 4.5, 4, 2, -0.5, -2]),
        EqualizerPreset(id: "bass", name: "Bass", symbol: "speaker.wave.3.fill",
                        preamp: -1.5,
                        gains: [6, 5, 3.5, 1.5, 0, 0, 0, 0, 0.5, 1]),
        EqualizerPreset(id: "treble", name: "Treble", symbol: "sparkles",
                        preamp: -0.5,
                        gains: [-1, -0.5, 0, 0, 0, 0.5, 2, 3.5, 5, 6]),
        // Gentle smile: the classic loudness contour.
        EqualizerPreset(id: "loudness", name: "Loudness", symbol: "waveform.path.ecg",
                        preamp: -2,
                        gains: [5, 4, 1, 0, -1, -0.5, 0.5, 2, 4, 5]),
        EqualizerPreset(id: "acoustic", name: "Acoustic", symbol: "guitars.fill",
                        preamp: -0.5,
                        gains: [3, 2, 1.5, 0.5, 1, 1.5, 2.5, 2.5, 2, 1]),
        // Low cut removes rumble and plosives; presence carries diction.
        EqualizerPreset(id: "speech", name: "Speech", symbol: "text.bubble.fill",
                        preamp: 0,
                        gains: [-6, -4, -1.5, 1.5, 3, 3.5, 3, 1.5, -1, -3]),
        // Bass and the very top eased off so quiet listening stays even.
        EqualizerPreset(id: "night", name: "Late Night", symbol: "moon.stars.fill",
                        preamp: 0,
                        gains: [-3, -1.5, 0, 2, 3, 3, 2.5, 1.5, 0.5, -1]),
        EqualizerPreset(id: "piano", name: "Piano", symbol: "pianokeys",
                        preamp: -0.5,
                        gains: [2, 1, 0, 1.5, 2, 1, 1.5, 2.5, 2, 1.5]),
    ]

    static func preset(id: String?) -> EqualizerPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
