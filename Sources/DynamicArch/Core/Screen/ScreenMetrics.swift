import AppKit

/// Everything the island needs to know about the display it lives on.
///
/// All rects are in AppKit global screen coordinates (origin bottom-left of the
/// primary display).
struct ScreenMetrics: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    /// Physical camera-housing cutout, when the display has one.
    let hardwareNotch: CGSize?
    /// Height of the menu bar strip on this display.
    let menuBarHeight: CGFloat

    /// Size of the island in its resting state. On notched displays this is the
    /// exact cutout so the island is literally invisible when idle; on other
    /// displays we synthesise a pill that mimics one.
    var restingSize: CGSize {
        if let hardwareNotch { return hardwareNotch }
        return CGSize(width: 190, height: max(menuBarHeight, 24))
    }

    var hasHardwareNotch: Bool { hardwareNotch != nil }

    /// Horizontal centre of the cutout. Notches are not always pixel-centred on
    /// the display, so this is derived from the real auxiliary areas.
    var notchCenterX: CGFloat

    var restingRect: CGRect {
        let size = restingSize
        return CGRect(x: notchCenterX - size.width / 2,
                      y: frame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    init(screen: NSScreen) {
        displayID = screen.displayID
        frame = screen.frame
        menuBarHeight = screen.menuBarHeight

        if let notch = screen.hardwareNotchSize, let left = screen.auxiliaryTopLeftArea {
            hardwareNotch = notch
            notchCenterX = left.maxX + notch.width / 2
        } else {
            hardwareNotch = nil
            notchCenterX = screen.frame.midX
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
    }

    /// The camera housing, measured from the gap between the two auxiliary
    /// menu-bar areas. Returns nil on displays without a cutout.
    var hardwareNotchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea
        else { return nil }
        let width = right.minX - left.maxX
        guard width > 1 else { return nil }
        return CGSize(width: width, height: safeAreaInsets.top)
    }

    /// Menu bar strip height: the safe-area inset on notched displays, the
    /// classic menu bar thickness elsewhere.
    var menuBarHeight: CGFloat {
        if safeAreaInsets.top > 0 { return safeAreaInsets.top }
        return frame.maxY - visibleFrame.maxY
    }

    static func with(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    static var mouseScreen: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }
}
