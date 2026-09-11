import SwiftUI

/// The hover state: a taste of what opening would give you.
struct PeekIslandView: View {
    let model: IslandModel
    let morph: Namespace.ID

    var body: some View {
        let resting = model.metrics?.restingSize.width ?? 190

        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if let track = model.media.track {
                    ArtworkView(image: track.artwork, accent: track.accent, cornerRadius: 7)
                        .frame(width: 26, height: 26)
                        .matchedGeometryEffect(id: "artwork", in: morph)
                } else {
                    Image(systemName: "capsule.portrait")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: resting)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let track = model.media.track, Preferences.shared.mediaVisualizer {
                    AudioWaveform(accent: track.accent, isActive: track.isPlaying)
                        .frame(width: 24, height: 16)
                } else if let track = model.media.track {
                    Image(systemName: track.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(track.accent)
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(Typography.compact)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.tertiaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
