import SwiftUI

/// Home is the media surface when something is playing, and a launcher grid
/// when it is not - the island should never show an empty box.
struct HomeTabView: View {
    let model: IslandModel
    let morph: Namespace.ID

    var body: some View {
        HStack(spacing: 14) {
            if let track = model.media.track {
                NowPlayingPanel(track: track, model: model, morph: morph)
            } else {
                QuickLaunchGrid(model: model)
            }

            if Preferences.shared.shelfEnabled {
                ShelfMiniColumn(model: model)
                    .frame(width: 116)
            }
        }
    }
}

struct NowPlayingPanel: View {
    let track: MediaStore.Track
    let model: IslandModel
    let morph: Namespace.ID

    private var media: MediaStore { model.media }

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: track.artwork, accent: track.accent, cornerRadius: 12)
                .frame(width: 96, height: 96)
                .matchedGeometryEffect(id: "artwork", in: morph)
                .onTapGesture { media.activatePlayer() }
                .help(track.appName ?? "Now Playing")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(text: track.title, font: Typography.title)
                    MarqueeText(text: track.artist ?? track.appName ?? "Now Playing",
                                font: Typography.caption,
                                color: Palette.secondaryText,
                                height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SeekBar(track: track, media: media)

                HStack(spacing: 4) {
                    IslandButton(size: 26, tint: track.shuffle == 2 ? track.accent : Palette.tertiaryText) {
                        media.toggleShuffle()
                    } label: { Image(systemName: "shuffle") }

                    Spacer(minLength: 0)

                    IslandButton(size: 30) { media.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                    }
                    IslandButton(size: 38, tint: Palette.primaryText, filled: true) {
                        media.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace.downUp))
                    }
                    IslandButton(size: 30) { media.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                    }

                    Spacer(minLength: 0)

                    IslandButton(size: 26, tint: track.repeatMode > 1 ? track.accent : Palette.tertiaryText) {
                        media.cycleRepeat()
                    } label: {
                        Image(systemName: track.repeatMode == 3 ? "repeat.1" : "repeat")
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Progress bar with scrub. Redraws off a 20 Hz timeline while playing instead
/// of a per-frame observable write, so scrolling the island stays free.
struct SeekBar: View {
    let track: MediaStore.Track
    let media: MediaStore

    @State private var scrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            TimelineView(.periodic(from: .now, by: track.isPlaying ? 0.05 : 1.0)) { _ in
                let fraction = scrubbing ? scrubFraction : media.progress
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(LinearGradient(colors: [track.accent.opacity(0.8), track.accent],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(2, geometry.size.width * fraction))
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                            .offset(x: max(0, geometry.size.width * fraction - 4))
                            .opacity(hovering || scrubbing ? 1 : 0)
                    }
                    .frame(height: hovering || scrubbing ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                scrubbing = true
                                scrubFraction = min(1, max(0, value.location.x / geometry.size.width))
                            }
                            .onEnded { value in
                                let fraction = min(1, max(0, value.location.x / geometry.size.width))
                                media.seek(toFraction: fraction)
                                scrubbing = false
                                Haptics.tap()
                            }
                    )
                }
                .frame(height: 10)
                .animation(Motion.press, value: hovering)
                .onHover { hovering = $0 }
            }

            HStack {
                Text(Self.format(scrubbing ? scrubFraction * track.duration : media.elapsed))
                Spacer()
                Text(Self.format(track.duration))
            }
            .font(Typography.mono)
            .foregroundStyle(Palette.tertiaryText)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Shown instead of the player when nothing is playing.
struct QuickLaunchGrid: View {
    let model: IslandModel

    var body: some View {
        HStack(spacing: 10) {
            IslandTile(title: "Shelf", action: { withAnimation(Motion.content) { model.tab = .shelf } }) {
                ZStack {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                    if !ShelfStore.shared.isEmpty {
                        Text("\(ShelfStore.shared.items.count)")
                            .font(Typography.caption)
                            .padding(4)
                            .background(Circle().fill(Palette.accent))
                            .offset(x: 16, y: -12)
                    }
                }
            }

            IslandTile(title: "Clipboard", action: { withAnimation(Motion.content) { model.tab = .clipboard } }) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
            }

            IslandTile(title: nil, action: { withAnimation(Motion.content) { model.tab = .calendar } }) {
                WeatherGlance()
            }

            IslandTile(title: nil) {
                TimerControl()
            }

            IslandTile(title: "Shortcuts", action: { ShortcutsStore.shared.presentMenu() }) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.warning)
            }
        }
    }
}
