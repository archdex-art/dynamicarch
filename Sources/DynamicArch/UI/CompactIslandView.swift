import SwiftUI

/// What the island shows at rest: nothing at all when idle, or a pair of
/// compact slots hugging the camera housing when something is happening.
struct CompactIslandView: View {
    let model: IslandModel
    let morph: Namespace.ID

    var body: some View {
        let resting = model.metrics?.restingSize.width ?? 190

        switch model.compactPresentation {
        case .none:
            Color.clear

        case .activity(let activity):
            HStack(spacing: 0) {
                CompactSlot(alignment: .leading) { leading(for: activity) }
                Spacer(minLength: resting)
                CompactSlot(alignment: .trailing) { trailing(for: activity) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)

        case .media(let track):
            HStack(spacing: 0) {
                CompactSlot(alignment: .leading) {
                    ArtworkView(image: track.artwork, accent: track.accent, cornerRadius: 6)
                        .frame(width: 20, height: 20)
                        .matchedGeometryEffect(id: "artwork", in: morph)
                }
                Spacer(minLength: resting)
                CompactSlot(alignment: .trailing) {
                    if Preferences.shared.mediaVisualizer {
                        AudioWaveform(accent: track.accent, isActive: track.isPlaying)
                            .frame(width: 22, height: 14)
                    } else {
                        Image(systemName: track.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(track.accent)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func leading(for activity: IslandActivity) -> some View {
        switch activity.content {
        case .level(let symbol, _, let tint, _):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        case .badge(let symbol, let image, _, _, let tint):
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 5))
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20, height: 20)
        case .media(let artwork, _, _, let tint):
            ArtworkView(image: artwork, accent: tint, cornerRadius: 6)
                .frame(width: 20, height: 20)
                .matchedGeometryEffect(id: "artwork", in: morph)
        case .progress(let symbol, _, _, let tint):
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func trailing(for activity: IslandActivity) -> some View {
        switch activity.content {
        case .level(_, let value, let tint, _):
            LevelBar(value: value, tint: tint)
                .frame(width: 62, height: 5)
        case .badge(_, _, let title, let subtitle, _):
            VStack(alignment: .trailing, spacing: 0) {
                Text(title)
                    .font(Typography.compact)
                    .foregroundStyle(Palette.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .lineLimit(1)
        case .media(_, let title, let artist, let tint):
            HStack(spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(title).font(Typography.compact).foregroundStyle(Palette.primaryText)
                    if let artist {
                        Text(artist).font(Typography.caption).foregroundStyle(Palette.secondaryText)
                    }
                }
                .lineLimit(1)
                AudioWaveform(accent: tint, isActive: true).frame(width: 18, height: 12)
            }
        case .progress(_, let fraction, let label, let tint):
            HStack(spacing: 6) {
                Text(label).font(Typography.mono).foregroundStyle(Palette.primaryText)
                RingProgress(fraction: fraction, tint: tint, lineWidth: 2.5)
                    .frame(width: 14, height: 14)
            }
        }
    }
}

/// Keeps compact content vertically centred on the notch and clipped to its slot.
private struct CompactSlot<Content: View>: View {
    let alignment: HorizontalAlignment
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            if alignment == .trailing { Spacer(minLength: 0) }
            content
            if alignment == .leading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity)
        .transition(Motion.compactSwap)
    }
}
