import AppKit
import SwiftUI

/// Drags every staged file at once as a proper multi-item drag session with a
/// stacked preview - the thing SwiftUI's `.onDrag` cannot express.
struct MultiFileDragHandle: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.urls = urls
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.urls = urls
        nsView.needsDisplay = true
    }

    final class HandleView: NSView, NSDraggingSource {
        var urls: [URL] = []
        private var hovering = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) {
            hovering = true
            NSCursor.openHand.set()
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            hovering = false
            NSCursor.arrow.set()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
            (hovering ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.10)).setFill()
            path.fill()

            let title = urls.count > 1 ? "Drag \(urls.count)" : "Drag"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.82)
            ]
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                   y: (bounds.height - size.height) / 2),
                       withAttributes: attributes)
        }

        override func mouseDown(with event: NSEvent) {
            guard !urls.isEmpty else { return }

            var items: [NSDraggingItem] = []
            for (index, url) in urls.enumerated() {
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 48, height: 48)
                // Fan the icons out slightly so the stack reads as several files.
                let origin = NSPoint(x: bounds.midX - 24 + CGFloat(index % 5) * 5,
                                     y: bounds.midY - 24 - CGFloat(index % 5) * 4)
                item.setDraggingFrame(NSRect(origin: origin, size: icon.size), contents: icon)
                items.append(item)
            }

            let session = beginDraggingSession(with: items, event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            session.draggingFormation = .stack
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? [] : [.copy, .link, .generic]
        }
    }
}
