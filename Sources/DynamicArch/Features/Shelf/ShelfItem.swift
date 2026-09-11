import AppKit
import UniformTypeIdentifiers

/// One staged thing on the shelf. Items are content-addressed on disk under
/// Application Support so they survive relaunches and so dragging out works
/// even after the source file moved.
struct ShelfItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Path of the file we hand to other apps.
    var storedPath: String
    /// Where it came from, when it came from the file system.
    var originalPath: String?
    var addedAt: Date
    var byteSize: Int64
    var typeIdentifier: String
    /// True when we point at the user's original file instead of a copy.
    var isReference: Bool

    var url: URL { URL(fileURLWithPath: storedPath) }
    var originalURL: URL? { originalPath.map { URL(fileURLWithPath: $0) } }
    var type: UTType { UTType(typeIdentifier) ?? .data }

    var isImage: Bool { type.conforms(to: .image) }
    var isMovie: Bool { type.conforms(to: .movie) }
    var isAudio: Bool { type.conforms(to: .audio) }
    var isText: Bool { type.conforms(to: .text) }
    var isPDF: Bool { type.conforms(to: .pdf) }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    var symbolName: String {
        if isImage { return "photo" }
        if isMovie { return "film" }
        if isAudio { return "waveform" }
        if isPDF { return "doc.richtext" }
        if type.conforms(to: .archive) { return "shippingbox" }
        if type.conforms(to: .url) { return "link" }
        if isText { return "doc.text" }
        if type.conforms(to: .folder) { return "folder" }
        return "doc"
    }
}
