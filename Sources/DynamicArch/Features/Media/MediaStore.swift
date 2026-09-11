import AppKit
import SwiftUI

/// Everything the island knows about what is playing, from any app: Music,
/// Spotify, Safari, Chrome, IINA, QuickTime - anything that registers with the
/// system Now Playing service.
@MainActor
@Observable
final class MediaStore {
    static let shared = MediaStore()

    struct Track: Equatable {
        var title: String = ""
        var artist: String?
        var album: String?
        var artwork: NSImage?
        var accent: Color = Palette.accent
        var duration: TimeInterval = 0
        /// Elapsed time as reported, and the wall clock moment it was true.
        var elapsedAtSample: TimeInterval = 0
        var sampledAt: Date = .now
        var rate: Double = 0
        var isPlaying = false
        var bundleIdentifier: String?
        var appName: String?
        var shuffle: Int = 0
        var repeatMode: Int = 0

        static func == (lhs: Track, rhs: Track) -> Bool {
            lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
                && lhs.isPlaying == rhs.isPlaying && lhs.duration == rhs.duration
                && lhs.elapsedAtSample == rhs.elapsedAtSample && lhs.bundleIdentifier == rhs.bundleIdentifier
                && lhs.artwork === rhs.artwork
        }
    }

    private(set) var track: Track?
    private(set) var bridgeAvailable = true
    /// Live audio level 0...1 used by the visualiser, driven by playback state.
    private(set) var lastTrackIdentity: String?

    private var bridge: MediaBridge?
    private var fallback: ScriptedMediaController?
    private var fallbackTimer: Timer?

    private init() {}

    var isPlaying: Bool { track?.isPlaying ?? false }
    var hasMedia: Bool { track != nil }

    /// Interpolated playback position. MediaRemote only gives us a sample plus
    /// a timestamp, so the smooth progress bar is computed here.
    var elapsed: TimeInterval {
        guard let track else { return 0 }
        guard track.isPlaying, track.rate > 0 else { return track.elapsedAtSample }
        let drift = Date.now.timeIntervalSince(track.sampledAt) * track.rate
        return min(track.duration > 0 ? track.duration : .greatestFiniteMagnitude,
                   track.elapsedAtSample + drift)
    }

    var progress: Double {
        guard let track, track.duration > 0 else { return 0 }
        return min(1, max(0, elapsed / track.duration))
    }

    // MARK: - Lifecycle

    func start() {
        guard bridge == nil else { return }
        let bridge = MediaBridge { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
        self.bridge = bridge
        bridge.start()
    }

    func stop() {
        bridge?.stop()
        bridge = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    // MARK: - Incoming state

    private func handle(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "now":
            bridgeAvailable = true
            apply(payload: message)
        case "gone":
            if track != nil { withAnimation(Motion.content) { track = nil } }
            lastTrackIdentity = nil
        case "error":
            bridgeAvailable = false
            startFallbackPolling()
        default:
            break
        }
    }

    private func apply(payload: [String: Any]) {
        /// Players routinely report empty strings rather than omitting a field;
        /// an empty artist must not win over a usable fallback.
        func text(_ key: String) -> String? {
            guard let value = payload[key] as? String else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        var next = track ?? Track()
        next.title = text("title") ?? next.title
        next.artist = text("artist") ?? next.artist
        next.album = text("album") ?? next.album
        next.duration = payload["duration"] as? Double ?? next.duration
        next.rate = payload["rate"] as? Double ?? next.rate
        next.isPlaying = payload["playing"] as? Bool ?? next.isPlaying
        next.bundleIdentifier = text("bundleIdentifier") ?? next.bundleIdentifier
        next.appName = text("appName") ?? next.appName
        next.shuffle = payload["shuffle"] as? Int ?? next.shuffle
        next.repeatMode = payload["repeat"] as? Int ?? next.repeatMode

        if let elapsed = payload["elapsed"] as? Double {
            next.elapsedAtSample = elapsed
            if let stamp = payload["timestamp"] as? Double {
                // MediaRemote timestamps are when the sample was taken; using
                // them verbatim keeps the progress bar locked to the player.
                next.sampledAt = Date(timeIntervalSince1970: stamp)
            } else {
                next.sampledAt = .now
            }
        }

        if payload["artworkCleared"] as? Bool == true {
            next.artwork = nil
            next.accent = Palette.accent
        }
        if let base64 = payload["artwork"] as? String,
           let data = Data(base64Encoded: base64),
           let image = NSImage(data: data) {
            next.artwork = image
            next.accent = ColorExtractor.accent(for: image)
        }

        let identity = [next.title, next.artist ?? "", next.album ?? ""].joined(separator: "|")
        let isNewTrack = identity != lastTrackIdentity && !next.title.isEmpty
        lastTrackIdentity = identity

        withAnimation(Motion.content) { track = next }

        if isNewTrack, next.isPlaying, Preferences.shared.mediaEnabled {
            ActivityCenter.shared.present(
                IslandActivity(kind: .media,
                               content: .media(artwork: next.artwork,
                                               title: next.title,
                                               artist: next.artist,
                                               tint: next.accent),
                               duration: 2.6)
            )
        }
    }

    // MARK: - Scripting fallback

    private func startFallbackPolling() {
        guard fallbackTimer == nil else { return }
        fallback = ScriptedMediaController()
        pollFallback()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFallback() }
        }
    }

    private func pollFallback() {
        guard let fallback else { return }
        Task.detached(priority: .utility) {
            let snapshot = fallback.snapshot()
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard let snapshot else {
                    if self.track != nil { withAnimation(Motion.content) { self.track = nil } }
                    return
                }
                var next = self.track ?? Track()
                next.title = snapshot.title
                next.artist = snapshot.artist
                next.album = snapshot.album
                next.duration = snapshot.duration
                next.elapsedAtSample = snapshot.elapsed
                next.sampledAt = .now
                next.isPlaying = snapshot.isPlaying
                next.rate = snapshot.isPlaying ? 1 : 0
                next.appName = snapshot.appName
                next.bundleIdentifier = snapshot.bundleIdentifier
                if let artwork = snapshot.artwork {
                    next.artwork = artwork
                    next.accent = ColorExtractor.accent(for: artwork)
                }
                withAnimation(Motion.content) { self.track = next }
            }
        }
    }

    // MARK: - Commands

    private func command(_ name: String, _ extra: [String: Any] = [:]) {
        if bridgeAvailable, let bridge, bridge.isRunning {
            bridge.send(["cmd": name].merging(extra) { _, new in new })
            return
        }
        fallback?.send(name, extra)
    }

    func togglePlayPause() {
        // Optimistic local flip so the button reacts on the same frame.
        if var current = track {
            current.isPlaying.toggle()
            current.elapsedAtSample = elapsed
            current.sampledAt = .now
            current.rate = current.isPlaying ? 1 : 0
            withAnimation(Motion.content) { track = current }
        }
        command("toggle")
    }

    func nextTrack() { command("next") }
    func previousTrack() { command("previous") }
    func skipForward() { command("forward15") }
    func skipBackward() { command("back15") }
    func toggleShuffle() { command("shuffle", ["mode": (track?.shuffle ?? 0) == 1 ? 2 : 1]) }
    func cycleRepeat() { command("repeat", ["mode": ((track?.repeatMode ?? 1) % 3) + 1]) }

    func seek(toFraction fraction: Double) {
        guard let track, track.duration > 0 else { return }
        let position = max(0, min(track.duration, track.duration * fraction))
        var updated = track
        updated.elapsedAtSample = position
        updated.sampledAt = .now
        self.track = updated
        command("seek", ["position": position])
    }

    func activatePlayer() {
        guard let bundleIdentifier = track?.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        else { return }
        app.activate(options: [.activateAllWindows])
    }
}
