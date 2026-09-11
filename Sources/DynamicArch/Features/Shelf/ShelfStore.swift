import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The file shelf: a staging tray that lives in the island.
///
/// Drop anything in - files, images, selected text, links - hold it while you
/// change spaces or apps, then drag it back out. Items are copied into our own
/// storage by default so moving or deleting the original does not break the
/// drag-out, and they expire on a schedule the user controls.
@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()

    private(set) var items: [ShelfItem] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    /// Number of ingests currently in flight, for the loading shimmer.
    private(set) var pendingIngests = 0
    private(set) var lastError: String?

    private let fileManager = FileManager.default
    private var expiryTimer: Timer?
    private var thumbnailRequests: Set<UUID> = []

    private let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicArch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    private init() {
        loadIndex()
    }

    func start() {
        guard expiryTimer == nil else { return }
        purgeExpired()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpired() }
        }
    }

    func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Ingest

    /// Pull everything droppable out of a pasteboard. Returns false when there
    /// was nothing we could take, so the drag can be rejected cleanly.
    @discardableResult
    func ingest(pasteboard: NSPasteboard) -> Bool {
        var sources: [IngestSource] = []

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            sources.append(contentsOf: urls.map { .file($0) })
        }

        if sources.isEmpty,
           let webURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !webURLs.isEmpty {
            sources.append(contentsOf: webURLs.map { .link($0) })
        }

        if sources.isEmpty {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = pasteboard.data(forType: type) {
                    sources.append(.imageData(data, type == .png ? UTType.png : UTType.tiff))
                    break
                }
            }
        }

        if sources.isEmpty, let text = pasteboard.string(forType: .string), !text.isEmpty {
            sources.append(.text(text))
        }

        guard !sources.isEmpty else { return false }
        ingest(sources: sources)
        return true
    }

    func ingest(urls: [URL]) {
        ingest(sources: urls.map { .file($0) })
    }

    private enum IngestSource {
        case file(URL)
        case link(URL)
        case imageData(Data, UTType)
        case text(String)
    }

    private func ingest(sources: [IngestSource]) {
        pendingIngests += sources.count
        let copies = Preferences.shared.shelfCopiesFiles
        let root = root

        Task.detached(priority: .userInitiated) {
            var built: [ShelfItem] = []
            var problem: String?

            for source in sources {
                do {
                    built.append(try Self.materialise(source, root: root, copying: copies))
                } catch {
                    problem = error.localizedDescription
                }
            }

            let created = built
            let failure = problem
            await MainActor.run { [weak self] in
                guard let self else { return }
                pendingIngests = max(0, pendingIngests - sources.count)
                lastError = failure
                guard !created.isEmpty else { return }
                withAnimation(Motion.content) {
                    self.items.insert(contentsOf: created, at: 0)
                }
                self.saveIndex()
                created.forEach { self.loadThumbnail(for: $0) }
            }
        }
    }

    private nonisolated static func materialise(_ source: IngestSource, root: URL, copying: Bool) throws -> ShelfItem {
        let fileManager = FileManager.default
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)

        func finish(name: String, destination: URL, original: URL?, reference: Bool) throws -> ShelfItem {
            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let type = (try? destination.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
            return ShelfItem(id: id,
                             name: name,
                             storedPath: destination.path,
                             originalPath: original?.path,
                             addedAt: .now,
                             byteSize: size,
                             typeIdentifier: type.identifier,
                             isReference: reference)
        }

        switch source {
        case .file(let url):
            guard fileManager.fileExists(atPath: url.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            if !copying {
                return try finish(name: url.lastPathComponent, destination: url, original: url, reference: true)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            return try finish(name: url.lastPathComponent, destination: destination, original: url, reference: false)

        case .imageData(let data, let type):
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Self.stampFormatter.string(from: .now)
            let name = "Image \(stamp).\(type.preferredFilenameExtension ?? "png")"
            let destination = directory.appendingPathComponent(name)
            try data.write(to: destination)
            return try finish(name: name, destination: destination, original: nil, reference: false)

        case .text(let text):
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? "Text"
            let trimmed = String(firstLine.prefix(40)).replacingOccurrences(of: "/", with: "-")
            let name = "\(trimmed.isEmpty ? "Text" : trimmed).txt"
            let destination = directory.appendingPathComponent(name)
            try text.write(to: destination, atomically: true, encoding: .utf8)
            return try finish(name: name, destination: destination, original: nil, reference: false)

        case .link(let url):
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let host = url.host ?? "Link"
            let name = "\(host).webloc"
            let destination = directory.appendingPathComponent(name)
            let plist: [String: Any] = ["URL": url.absoluteString]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: destination)
            return try finish(name: name, destination: destination, original: nil, reference: false)
        }
    }

    private nonisolated static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    // MARK: - Mutation

    func remove(_ item: ShelfItem) {
        withAnimation(Motion.content) {
            items.removeAll { $0.id == item.id }
        }
        thumbnails[item.id] = nil
        discardStorage(for: item)
        saveIndex()
    }

    func removeAll() {
        let current = items
        withAnimation(Motion.content) { items.removeAll() }
        thumbnails.removeAll()
        current.forEach(discardStorage)
        saveIndex()
    }

    /// Staged copies go to the Trash, never straight to unlink: clearing the
    /// shelf must not be able to destroy the only copy of something. Items that
    /// merely reference a file the user already owns are left alone.
    private func discardStorage(for item: ShelfItem) {
        guard !item.isReference else { return }
        let container = item.url.deletingLastPathComponent()
        guard container.path.hasPrefix(root.path), container.path != root.path else { return }
        do {
            try fileManager.trashItem(at: container, resultingItemURL: nil)
        } catch {
            try? fileManager.removeItem(at: container)
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        saveIndex()
    }

    func purgeExpired() {
        let hours = Preferences.shared.shelfRetentionHours
        guard hours > 0 else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(hours) * 3600)
        let expired = items.filter { $0.addedAt < cutoff }
        guard !expired.isEmpty else { return }
        expired.forEach(remove)
    }

    /// Drop items whose backing file vanished (user emptied the trash, etc).
    func validate() {
        let missing = items.filter { !fileManager.fileExists(atPath: $0.storedPath) }
        guard !missing.isEmpty else { return }
        withAnimation(Motion.content) {
            items.removeAll { item in missing.contains { $0.id == item.id } }
        }
        saveIndex()
    }

    // MARK: - Thumbnails

    func thumbnail(for item: ShelfItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        loadThumbnail(for: item)
        return nil
    }

    private func loadThumbnail(for item: ShelfItem) {
        guard thumbnails[item.id] == nil, !thumbnailRequests.contains(item.id) else { return }
        thumbnailRequests.insert(item.id)
        let url = item.url
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: 96, height: 96),
                                                   scale: scale,
                                                   representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation.map { NSImage(cgImage: $0.cgImage, size: CGSize(width: 96, height: 96)) }
            Task { @MainActor in
                guard let self else { return }
                self.thumbnailRequests.remove(item.id)
                guard let image else { return }
                self.thumbnails[item.id] = image
            }
        }
    }

    // MARK: - Persistence

    private func saveIndex() {
        let snapshot = items
        Task.detached(priority: .utility) { [indexURL] in
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return }
        items = decoded.filter { fileManager.fileExists(atPath: $0.storedPath) }
    }
}
