import SwiftUI

/// Central motion vocabulary.
///
/// Everything the island does uses one of these curves, which is what makes the
/// whole surface feel like one object instead of a pile of animated views.
/// Values are tuned for a 120 Hz ProMotion panel: springs short enough to feel
/// instant, damped enough to never wobble twice.
enum Motion {
    /// Rest -> open. A little bounce so the panel feels physical.
    static let expand = Animation.spring(response: 0.40, dampingFraction: 0.76, blendDuration: 0.12)
    /// Open -> rest. Slightly faster and tighter; overshoot on close reads as sloppy.
    static let collapse = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.10)
    /// Hover peek.
    static let peek = Animation.spring(response: 0.28, dampingFraction: 0.80, blendDuration: 0.08)
    /// Live activity in/out.
    static let activity = Animation.spring(response: 0.36, dampingFraction: 0.78, blendDuration: 0.10)
    /// Section changes: a touch longer than a content crossfade so the slide
    /// reads as movement between pages rather than a flicker.
    static let section = Animation.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)
    /// Content crossfades and small state flips inside the panel.
    static let content = Animation.spring(response: 0.26, dampingFraction: 0.90, blendDuration: 0.06)
    /// Continuous values that must never overshoot (progress bars, levels).
    static let value = Animation.interpolatingSpring(mass: 0.35, stiffness: 180, damping: 24)
    /// Snappy micro-interactions (button presses).
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.72)

    /// Asymmetric transition used by island content: new content rises and
    /// scales in from the notch, old content falls away.
    static var contentSwap: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.86, anchor: .top)
                .combined(with: .opacity)
                .combined(with: .offset(y: -6)),
            removal: .scale(scale: 0.94, anchor: .top)
                .combined(with: .opacity)
        )
    }

    /// Pages slide in from the direction of travel and out the opposite way,
    /// so a two-finger swipe feels like it is dragging the content along.
    static func sectionSlide(direction: Int) -> AnyTransition {
        let forward = direction >= 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    static var compactSwap: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.7, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.8, anchor: .center).combined(with: .opacity)
        )
    }
}
