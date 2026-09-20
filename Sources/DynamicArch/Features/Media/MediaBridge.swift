import Foundation
import Security

/// Supervises the MediaRemote bridge process and exposes it as a duplex
/// newline-delimited JSON channel.
///
/// The bridge runs under /usr/bin/perl because MediaRemote refuses to talk to
/// anything that is not an Apple platform binary since macOS 15.4. The process
/// is kept alive for the lifetime of the app and restarted with backoff if it
/// ever dies, so media control is always one write away.
final class MediaBridge {
    typealias Handler = ([String: Any]) -> Void

    private let handler: Handler
    private let queue = DispatchQueue(label: "app.dynamicarch.media.bridge")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    /// Set after an oversized frame is dropped, so the remainder of that line
    /// is discarded instead of being parsed as if it were a new message.
    private var resyncing = false
    /// Largest single message accepted. Artwork dominates the payload, and a
    /// few hundred kilobytes is already generous for album art.
    private static let maximumFrame = 6 * 1024 * 1024
    private var restartDelay: TimeInterval = 0.5
    private var stopped = false

    private(set) var isRunning = false
    /// Set when the bridge reports that MediaRemote is unreachable, which is the
    /// signal to fall back to scripting bridges.
    private(set) var isUnavailable = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Resolves the bundled helper, and refuses anything else.
    ///
    /// This pair is *executed*: the script is handed to /usr/bin/perl and the
    /// dylib is dlopened inside it. An earlier version fell back to
    /// `Helper/archmedia.pl` relative to the process's working directory,
    /// which means launching the app from a directory an attacker can write
    /// (a shared folder, a downloads directory, `open -a` from a script) would
    /// have run their code with the user's full privileges. Only paths inside
    /// our own bundle are accepted now, and each one is checked for the
    /// classic substitution tricks before it is used.
    static var helperPaths: (script: URL, bridge: URL)? {
        let contents = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .standardizedFileURL
        let script = contents.appendingPathComponent("Resources/archmedia.pl")
        let bridge = contents.appendingPathComponent("Frameworks/ArchMediaBridge.dylib")
        guard isSafeToExecute(script, within: contents), isSafeToExecute(bridge, within: contents) else {
            return nil
        }
        // Ownership and permissions are not enough on their own: in the
        // single-user threat model the attacker *is* the owner, and the script
        // is plain text inside a bundle the user can write. The signature seals
        // it, so verifying our own bundle is what actually detects a swap - and
        // it has to run on every launch, because the supervisor relaunches the
        // helper within seconds of it being killed.
        guard hasValidSignature() else { return nil }
        return (script, bridge)
    }

    /// Checks our own code signature, including sealed resources and nested
    /// code. `archmedia.pl` and `ArchMediaBridge.dylib` are both covered.
    private static func hasValidSignature() -> Bool {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            Diagnostics.media.error("cannot read own code signature; refusing to launch the helper")
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let validity = SecStaticCodeCheckValidity(staticCode, flags, nil)
        guard validity == errSecSuccess else {
            Diagnostics.media.error("own bundle failed signature validation (\(validity)); refusing to launch the helper")
            return false
        }
        return true
    }

    /// A path is only safe to execute if it really is the file inside our
    /// bundle: no symlink redirecting elsewhere, and not writable by anyone
    /// but its owner, so another process cannot swap the contents out from
    /// under us between checking and launching.
    private static func isSafeToExecute(_ url: URL, within root: URL) -> Bool {
        let manager = FileManager.default
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == url.standardizedFileURL.path else {
            Diagnostics.media.error("helper path is a symlink; refusing to load it")
            return false
        }
        guard resolved.path.hasPrefix(root.path + "/") else {
            Diagnostics.media.error("helper path escapes the app bundle; refusing to load it")
            return false
        }
        guard let attributes = try? manager.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else { return false }

        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid(), owner.uint32Value != 0 {
            Diagnostics.media.error("helper is owned by another user; refusing to load it")
            return false
        }
        if let permissions = (attributes[.posixPermissions] as? NSNumber)?.int16Value,
           permissions & 0o022 != 0 {
            Diagnostics.media.error("helper is group or world writable; refusing to load it")
            return false
        }
        return true
    }

    func start() {
        queue.async { [weak self] in self?.launch() }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            stopped = true
            process?.terminationHandler = nil
            process?.terminate()
            process = nil
            isRunning = false
        }
    }

    func send(_ command: [String: Any]) {
        queue.async { [weak self] in
            guard let self, let stdinPipe,
                  var data = try? JSONSerialization.data(withJSONObject: command)
            else { return }
            data.append(0x0A)
            // A dead pipe throws; the supervisor will already be restarting.
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private func launch() {
        guard !stopped, let paths = Self.helperPaths else {
            isUnavailable = true
            handler(["type": "error", "message": "bridge helper missing"])
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.script.path, paths.bridge.path, "serve"]
        task.environment = ["PATH": "/usr/bin:/bin"]

        let out = Pipe()
        let input = Pipe()
        task.qualityOfService = .utility
        task.standardOutput = out
        task.standardInput = input
        task.standardError = FileHandle.nullDevice

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async { self?.consume(chunk) }
        }

        task.terminationHandler = { [weak self] _ in
            guard let self else { return }
            queue.async {
                self.isRunning = false
                guard !self.stopped else { return }
                let delay = self.restartDelay
                self.restartDelay = min(delay * 2, 15)
                self.queue.asyncAfter(deadline: .now() + delay) { self.launch() }
            }
        }

        do {
            try task.run()
            process = task
            stdinPipe = input
            isRunning = true
        } catch {
            isUnavailable = true
            handler(["type": "error", "message": "bridge failed to launch: \(error.localizedDescription)"])
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            // Finish discarding the tail of a frame we already rejected.
            if resyncing {
                resyncing = false
                continue
            }
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            if object["type"] as? String == "ready" {
                restartDelay = 0.5
                isUnavailable = false
            }
            if object["type"] as? String == "error" { isUnavailable = true }
            handler(object)
        }
        // A producer that never emits a newline would otherwise fill memory.
        // Drop what we have and skip the rest of the frame, rather than
        // clearing mid-line and parsing the remainder as a fresh message.
        if buffer.count > Self.maximumFrame {
            Diagnostics.media.error("dropping oversized bridge frame")
            buffer.removeAll(keepingCapacity: false)
            resyncing = true
        }
    }
}
