import AppKit

/// Root AppKit view of the panel.
///
/// Two jobs, both of which SwiftUI cannot do correctly on its own:
/// 1. **Hit testing** - the panel is a large transparent surface sitting on top
///    of the menu bar. Every point outside the island's current shape must fall
///    through to whatever is underneath, otherwise we would eat menu-bar clicks.
/// 2. **Drag destination** - AppKit level drag handling works even when the
///    panel is not key and gives us precise enter/exit/drop semantics plus the
///    ability to widen the catch area while a drag is in flight.
final class IslandStageView: NSView {
    weak var model: IslandModel?

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = .clear
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff, .rtf, .html, .pdf,
                                 NSPasteboard.PasteboardType("public.item"),
                                 NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model else { return nil }
        guard model.interactiveRect(inStage: bounds).contains(point) else { return nil }
        return super.hitTest(point)
    }

    // MARK: - Dragging destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Diagnostics.drag.debug("draggingEntered: \(sender.draggingPasteboard.types?.count ?? 0) types")
        guard let model, Preferences.shared.shelfEnabled else { return [] }
        model.beginShelfTargeting()
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let model, Preferences.shared.shelfEnabled else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        model.updateShelfTargeting(inside: model.dropRect(inStage: bounds).contains(point))
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        model?.endShelfTargeting()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        Preferences.shared.shelfEnabled
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        Diagnostics.drag.info("performDragOperation")
        guard let model else { return false }
        model.endShelfTargeting()
        return model.acceptDrop(pasteboard: sender.draggingPasteboard)
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        model?.endShelfTargeting()
    }
}
