import AppKit
import Quartz

/// Everything you can do to a staged item without leaving the island.
@MainActor
enum ShelfActions {
    static func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    static func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    static func copyToPasteboard(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
        Haptics.success()
    }

    static func airDrop(_ items: [ShelfItem], relativeTo view: NSView?) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let urls = items.map(\.url)
        guard service.canPerform(withItems: urls) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    static func share(_ items: [ShelfItem], from view: NSView, rect: NSRect) {
        let picker = NSSharingServicePicker(items: items.map(\.url))
        NSApp.activate(ignoringOtherApps: true)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    static func quickLook(_ items: [ShelfItem], startingAt index: Int) {
        QuickLookCoordinator.shared.present(urls: items.map(\.url), startingAt: index)
    }

    static func saveCopy(_ items: [ShelfItem]) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        for item in items {
            let target = destination.appendingPathComponent(item.name)
            try? FileManager.default.copyItem(at: item.url, to: target)
        }
        Haptics.success()
    }
}

/// QuickLook needs a key window and an active app; the island is neither by
/// design, so we borrow focus for the duration of the preview and hand it back.
@MainActor
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookCoordinator()

    private var urls: [URL] = []

    func present(urls: [URL], startingAt index: Int) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        // Quick Look needs an active app with a key window; an accessory app
        // has neither, so borrow both and hold the island open meanwhile.
        IslandModel.shared.acquireInteractionLock("quicklook")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.currentPreviewItemIndex = min(index, urls.count - 1)
        panel.reloadData()
    }

    /// Called by the panel when it goes away; hands focus and the island back.
    func endPreviewSession() {
        IslandModel.shared.releaseInteractionLock("quicklook")
        if !SettingsWindowController.shared.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        IslandModel.shared.scheduleClose(after: 0.4)
    }

    nonisolated func previewPanelDidClose(_ panel: QLPreviewPanel) {
        MainActor.assumeIsolated { endPreviewSession() }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
