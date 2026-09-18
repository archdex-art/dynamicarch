import AppKit

/// AppleScript fallback for the day Apple closes the platform-binary route.
/// Covers the two players that expose a scripting dictionary; everything else
/// simply reports nothing rather than lying to the UI.
final class ScriptedMediaController {
    struct Snapshot {
        var title: String
        var artist: String?
        var album: String?
        var duration: TimeInterval
        var elapsed: TimeInterval
        var isPlaying: Bool
        var appName: String
        var bundleIdentifier: String
        var artwork: NSImage?
    }

    private static let music = "com.apple.Music"
    private static let spotify = "com.spotify.client"

    func snapshot() -> Snapshot? {
        if let snapshot = query(bundleIdentifier: Self.spotify, application: "Spotify") { return snapshot }
        if let snapshot = query(bundleIdentifier: Self.music, application: "Music") { return snapshot }
        return nil
    }

    func send(_ command: String, _ extra: [String: Any]) {
        let target = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.spotify }
            ? "Spotify" : "Music"
        let script: String
        switch command {
        case "toggle": script = "tell application \"\(target)\" to playpause"
        case "next": script = "tell application \"\(target)\" to next track"
        case "previous": script = "tell application \"\(target)\" to previous track"
        case "seek":
            // Formatted explicitly: interpolating a raw Double would put
            // "inf" or "nan" straight into the script if a player ever
            // reported a nonsense duration.
            let raw = (extra["position"] as? Double) ?? 0
            let position = raw.isFinite ? min(max(raw, 0), 86_400) : 0
            script = String(format: "tell application \"%@\" to set player position to %.3f",
                            target, position)
        default: return
        }
        run(script)
    }

    private func query(bundleIdentifier: String, application: String) -> Snapshot? {
        guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier })
        else { return nil }
        let script = """
        tell application "\(application)"
            if player state is stopped then return ""
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set playing to (player state is playing)
            return trackName & "\t" & trackArtist & "\t" & trackAlbum & "\t" & trackDuration & "\t" & trackPosition & "\t" & playing
        end tell
        """
        guard let output = run(script), !output.isEmpty else { return nil }
        let fields = output.components(separatedBy: "\t")
        guard fields.count >= 6 else { return nil }
        // Spotify reports duration in milliseconds, Music in seconds.
        let rawDuration = Double(fields[3]) ?? 0
        let duration = bundleIdentifier == Self.spotify ? rawDuration / 1000 : rawDuration
        return Snapshot(title: fields[0],
                        artist: fields[1].isEmpty ? nil : fields[1],
                        album: fields[2].isEmpty ? nil : fields[2],
                        duration: duration,
                        elapsed: Double(fields[4]) ?? 0,
                        isPlaying: fields[5] == "true",
                        appName: application,
                        bundleIdentifier: bundleIdentifier,
                        artwork: nil)
    }

    @discardableResult
    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}
