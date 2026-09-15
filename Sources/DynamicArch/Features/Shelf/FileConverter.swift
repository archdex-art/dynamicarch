import AVFoundation
import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// One-tap conversions for staged files. Everything runs on system frameworks -
/// no bundled binaries, no network.
enum FileConverter {
    struct Conversion: Identifiable, Hashable {
        enum Kind: Hashable {
            case image(UTType)
            case imagesToPDF
            case documentToPDF
            case extractAudio
            case transcodeVideo
            case compressImage
        }

        let id: String
        let title: String
        let kind: Kind
    }

    static func conversions(for item: ShelfItem) -> [Conversion] {
        var result: [Conversion] = []
        if item.isImage {
            for type in [UTType.png, .jpeg, .heic, .tiff] where type.identifier != item.typeIdentifier {
                result.append(Conversion(id: "img-\(type.identifier)",
                                         title: "to \(type.preferredFilenameExtension?.uppercased() ?? "Image")",
                                         kind: .image(type)))
            }
            result.append(Conversion(id: "img-pdf", title: "to PDF", kind: .imagesToPDF))
            result.append(Conversion(id: "img-compress", title: "Compress", kind: .compressImage))
        }
        if item.isMovie {
            result.append(Conversion(id: "mov-audio", title: "Extract audio (M4A)", kind: .extractAudio))
            result.append(Conversion(id: "mov-mp4", title: "to MP4", kind: .transcodeVideo))
        }
        if item.isAudio, item.type != .mpeg4Audio {
            result.append(Conversion(id: "aud-m4a", title: "to M4A", kind: .extractAudio))
        }
        if item.isText || item.type.conforms(to: .rtf) || item.typeIdentifier.contains("wordprocessingml") {
            result.append(Conversion(id: "doc-pdf", title: "to PDF", kind: .documentToPDF))
        }
        return result
    }

    @MainActor
    static func run(_ conversion: Conversion, on item: ShelfItem) {
        let source = item.url
        Task.detached(priority: .userInitiated) {
            let produced: URL?
            switch conversion.kind {
            case .image(let type): produced = convertImage(source, to: type, quality: 0.95)
            case .compressImage: produced = convertImage(source, to: .jpeg, quality: 0.6)
            case .imagesToPDF: produced = imagesToPDF([source])
            case .documentToPDF: produced = documentToPDF(source)
            case .extractAudio: produced = await exportAudio(source)
            case .transcodeVideo: produced = await exportVideo(source)
            }
            guard let produced else { return }
            await MainActor.run {
                ShelfStore.shared.ingest(urls: [produced])
                Haptics.success()
            }
        }
    }

    // MARK: - Images

    private static func convertImage(_ source: URL, to type: UTType, quality: Double) -> URL? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }
        let destinationURL = output(for: source, extension: type.preferredFilenameExtension ?? "png")
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL,
                                                                type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationURL
    }

    private static func imagesToPDF(_ sources: [URL]) -> URL? {
        let document = PDFDocument()
        for (index, source) in sources.enumerated() {
            guard let image = NSImage(contentsOf: source), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: index)
        }
        guard document.pageCount > 0 else { return nil }
        let destination = output(for: sources[0], extension: "pdf")
        return document.write(to: destination) ? destination : nil
    }

    private static func documentToPDF(_ source: URL) -> URL? {
        guard let attributed = try? NSAttributedString(
            url: source,
            options: [.documentType: documentType(for: source)],
            documentAttributes: nil
        ) else { return nil }

        let pageSize = CGSize(width: 612, height: 792)
        let inset: CGFloat = 48
        let textRect = CGRect(x: inset, y: inset,
                              width: pageSize.width - inset * 2,
                              height: pageSize.height - inset * 2)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var range = CFRange(location: 0, length: 0)
        var offset = 0

        repeat {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context)
            range = CTFrameGetVisibleStringRange(frame)
            offset += range.length
            context.endPDFPage()
        } while offset < attributed.length && range.length > 0

        context.closePDF()
        let destination = output(for: source, extension: "pdf")
        return (try? data.write(to: destination, options: .atomic)) != nil ? destination : nil
    }

    private static func documentType(for url: URL) -> NSAttributedString.DocumentType {
        switch url.pathExtension.lowercased() {
        case "rtf": .rtf
        case "rtfd": .rtfd
        // Deliberately *not* .html: AppKit's HTML importer is WebKit backed and
        // will fetch remote subresources, so converting a dropped page would
        // quietly make network requests on the user's behalf - and leak that
        // the file was opened. Imported as plain text instead.
        case "docx": .officeOpenXML
        case "odt": .openDocument
        default: .plain
        }
    }

    // MARK: - Media

    private static func exportAudio(_ source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let destination = output(for: source, extension: "m4a")
        try? FileManager.default.removeItem(at: destination)
        do {
            try await session.export(to: destination, as: .m4a)
            return destination
        } catch {
            return nil
        }
    }

    private static func exportVideo(_ source: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { return nil }
        let destination = output(for: source, extension: "mp4")
        try? FileManager.default.removeItem(at: destination)
        do {
            try await session.export(to: destination, as: .mp4)
            return destination
        } catch {
            return nil
        }
    }

    // MARK: - Paths

    private static func output(for source: URL, extension ext: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicArch", isDirectory: true)
        // Converted output is a copy of the user's document; keep it
        // owner-only rather than inheriting the umask.
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
