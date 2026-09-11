import Foundation

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
    private var restartDelay: TimeInterval = 0.5
    private var stopped = false

    private(set) var isRunning = false
    /// Set when the bridge reports that MediaRemote is unreachable, which is the
    /// signal to fall back to scripting bridges.
    private(set) var isUnavailable = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    static var helperPaths: (script: URL, bridge: URL)? {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates: [(URL, URL)] = [
            (contents.appendingPathComponent("Resources/archmedia.pl"),
             contents.appendingPathComponent("Frameworks/ArchMediaBridge.dylib")),
            (development.appendingPathComponent("Helper/archmedia.pl"),
             development.appendingPathComponent("build/helpers/ArchMediaBridge.dylib")),
        ]
        for (script, bridge) in candidates
        where FileManager.default.fileExists(atPath: script.path)
            && FileManager.default.fileExists(atPath: bridge.path) {
            return (script, bridge)
        }
        return nil
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
        // Guard against a wedged producer filling memory.
        if buffer.count > 8 * 1024 * 1024 { buffer.removeAll(keepingCapacity: false) }
    }
}
