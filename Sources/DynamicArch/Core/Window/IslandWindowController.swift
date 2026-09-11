import AppKit
import SwiftUI

/// Owns one island: a fixed-size transparent panel pinned to the top of a
/// display, with the SwiftUI island hosted inside it.
@MainActor
final class IslandWindowController {
    let metrics: ScreenMetrics
    private let model: IslandModel
    private let panel: IslandPanel
    private let stage: IslandStageView
    private let host: NSHostingView<IslandRootView>

    init(screen: NSScreen, model: IslandModel) {
        self.metrics = ScreenMetrics(screen: screen)
        self.model = model

        model.attach(metrics: metrics)

        let frame = Self.panelFrame(metrics: metrics, stageSize: model.stageSize)
        panel = IslandPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        stage = IslandStageView(frame: CGRect(origin: .zero, size: frame.size))
        stage.autoresizingMask = [.width, .height]
        stage.model = model

        host = NSHostingView(rootView: IslandRootView(model: model))
        host.frame = stage.bounds
        host.autoresizingMask = [.width, .height]
        // Transparent host: only the island shape paints.
        host.layer?.backgroundColor = .clear
        if #available(macOS 14.0, *) {
            host.sceneBridgingOptions = []
        }
        stage.addSubview(host)

        panel.contentView = stage
        panel.setFrame(frame, display: false)

        // The model decides, from pointer position and drag state, when the
        // panel may claim mouse events.
        model.interactivityHandler = { [weak panel] interactive in
            guard let panel, panel.ignoresMouseEvents == interactive else { return }
            panel.ignoresMouseEvents = interactive == false
        }
        model.refreshInteractivity()
        panel.sharingType = Preferences.shared.hideFromScreenCapture ? .none : .readOnly
        panel.orderFrontRegardless()
    }

    static func panelFrame(metrics: ScreenMetrics, stageSize: CGSize) -> CGRect {
        // Even width keeps the island's centred frame on whole points, and an
        // integral origin keeps the shape's edges on pixel boundaries.
        var width = min(stageSize.width, metrics.frame.width).rounded(.down)
        if width.truncatingRemainder(dividingBy: 2) != 0 { width -= 1 }
        let height = min(stageSize.height, metrics.frame.height).rounded(.down)
        return CGRect(x: (metrics.notchCenterX - width / 2).rounded(),
                      y: (metrics.frame.maxY - height).rounded(),
                      width: width,
                      height: height)
    }

    func refreshFrame() {
        panel.setFrame(Self.panelFrame(metrics: metrics, stageSize: model.stageSize), display: true)
    }

    func applyTheme() {
        panel.appearance = NSAppearance(named: Preferences.shared.theme.appearance)
        panel.contentView?.needsDisplay = true
    }

    func updateCaptureVisibility() {
        panel.sharingType = Preferences.shared.hideFromScreenCapture ? .none : .readOnly
    }

    /// Raises the panel back above the menu bar. Some system transitions
    /// (fullscreen entry, display sleep) reshuffle window levels.
    func reassertLevel() {
        panel.level = .mainMenu + 3
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }
}
