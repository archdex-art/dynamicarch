import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clipboard history. Polls the change count - the only mechanism macOS
/// offers - at a rate that is free in CPU terms, and honours the community
/// markers apps use to say "do not record this".
@MainActor
@Observable
final class ClipboardStore {
    static let shared = ClipboardStore()

    struct Entry: Identifiable, Equatable {
        enum Payload: Equatable {
            case text(String)
            case image(NSImage)
            case files([URL])
        }

        let id = UUID()
        var payload: Payload
        var date: Date
        var sourceApp: String?

        var preview: String {
            switch payload {
            case .text(let text): text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .image: "Image"
            case .files(let urls): urls.map(\.lastPathComponent).joined(separator: ", ")
            }
        }

        var symbolName: String {
            switch payload {
            case .text(let text): text.hasPrefix("http") ? "link" : "text.alignleft"
            case .image: "photo"
            case .files: "doc"
            }
        }

        /// Files borrow the system's own icon for their type, which is both
        /// instantly recognisable and free.
        var activityIcon: NSImage? {
            switch payload {
            case .files(let urls):
                guard let first = urls.first else { return nil }
                let icon = NSWorkspace.shared.icon(forFile: first.path)
                icon.size = NSSize(width: 22, height: 22)
                return icon
            case .image(let image):
                return image
            case .text:
                return nil
            }
        }

        var activitySymbol: String? {
            switch payload {
            case .files, .image: nil
            case .text(let text): text.hasPrefix("http") ? "link" : "doc.on.clipboard.fill"
            }
        }

        var activityTitle: String {
            switch payload {
            case .files(let urls):
                urls.count == 1 ? (urls.first?.lastPathComponent ?? "File") : "\(urls.count) files"
            case .image:
                "Image copied"
            case .text(let text):
                text.hasPrefix("http") ? "Link copied" : "Text copied"
            }
        }

        /// Type and size: "PDF · 2.4 MB", "1024 x 768 · 240 KB", "128 characters".
        var activityDetail: String? {
            switch payload {
            case .files(let urls):
                var bytes: Int64 = 0
                for url in urls {
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    bytes += Int64(size)
                }
                let type: String? = urls.first.flatMap { url in
                    if let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
                        return contentType.localizedDescription ?? url.pathExtension.uppercased()
                    }
                    return url.pathExtension.isEmpty ? nil : url.pathExtension.uppercased()
                }
                let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                guard let type, !type.isEmpty else { return bytes > 0 ? size : nil }
                return bytes > 0 ? "\(type) · \(size)" : type
            case .image(let image):
                let pixels = image.representations.first.map { "\($0.pixelsWide) x \($0.pixelsHigh)" }
                let bytes = image.tiffRepresentation?.count ?? 0
                let size = bytes > 0
                    ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                    : nil
                let parts = [pixels, size].compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            case .text(let text):
                if text.hasPrefix("http"), let host = URL(string: text)?.host { return host }
                return text.count == 1 ? "1 character" : "\(text.count) characters"
            }
        }
    }

    private(set) var entries: [Entry] = []
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let limit = 60
    /// Longest clip kept verbatim.
    private static let textLimit = 64 * 1024

    private init() {}

    func start() {
        guard Preferences.shared.clipboardEnabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Password managers and similar mark their clips; never store those.
        let types = pasteboard.types ?? []
        let markers: Set<String> = ["org.nspasteboard.TransientType",
                                    "org.nspasteboard.ConcealedType",
                                    "org.nspasteboard.AutoGeneratedType",
                                    "com.agilebits.onepassword"]
        guard !types.contains(where: { markers.contains($0.rawValue) }) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.localizedName

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           urls.isEmpty == false {
            insert(Entry(payload: .files(urls), date: .now, sourceApp: source))
            return
        }
        if let text = pasteboard.string(forType: .string),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            // Bounded: history lives in memory for the session, and there is no
            // reason to hold a multi-megabyte paste - or keep that much of a
            // secret around - to show a one-line preview.
            insert(Entry(payload: .text(String(text.prefix(Self.textLimit))),
                         date: .now,
                         sourceApp: source))
            return
        }
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: data) {
            insert(Entry(payload: .image(image), date: .now, sourceApp: source))
        }
    }

    private func insert(_ entry: Entry) {
        if let existing = entries.first, existing.payload == entry.payload { return }
        withAnimation(Motion.content) {
            entries.insert(entry, at: 0)
            if entries.count > limit { entries.removeLast(entries.count - limit) }
        }
        announce(entry)
    }

    /// Copying is silent feedback by default; the island confirms it with the
    /// type's own icon, what kind of thing it was, and how big.
    private func announce(_ entry: Entry) {
        ActivityCenter.shared.present(
            IslandActivity(kind: .clipboard,
                           content: .badge(symbol: entry.activitySymbol,
                                           image: entry.activityIcon,
                                           title: entry.activityTitle,
                                           subtitle: entry.activityDetail,
                                           tint: Palette.accent),
                           duration: 2.0)
        )
    }

    func copy(_ entry: Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.payload {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .image(let image): pasteboard.writeObjects([image])
        case .files(let urls): pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        lastChangeCount = pasteboard.changeCount
        Haptics.success()
    }

    func remove(_ entry: Entry) {
        withAnimation(Motion.content) { entries.removeAll { $0.id == entry.id } }
    }

    func clear() {
        withAnimation(Motion.content) { entries.removeAll() }
    }
}
