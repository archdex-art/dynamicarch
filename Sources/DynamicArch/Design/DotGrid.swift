import SwiftUI

/// The Nothing OS reveal: a grid of dots that lights up outward from the
/// centre as the island opens, then settles into a faint matrix behind the
/// content.
///
/// Drawn in a single `Canvas` pass rather than hundreds of views - a 600 x 240
/// panel holds roughly 1,500 dots, which is fine as one draw call and ruinous
/// as a view hierarchy. The wave is a pure function of one animated number, so
/// it interpolates with the island's own spring instead of running a timer.
struct DotGridReveal: View {
    /// 0 = dark, 1 = fully revealed. Animate this, never the dots.
    var progress: Double
    var spacing: CGFloat = 9
    var dotSize: CGFloat = 1.6
    var tint: Color = .white
    /// How visible the grid stays once the reveal has finished.
    var restOpacity: Double = 0.10

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            guard progress > 0.001 else { return }
            let columns = Int((size.width / spacing).rounded(.up))
            let rows = Int((size.height / spacing).rounded(.up))
            guard columns > 0, rows > 0 else { return }

            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxDistance = max(1, hypot(centre.x, centre.y))
            // The wavefront travels a little past the far corner so the last
            // ring of dots also gets to settle rather than snapping on.
            let front = progress * 1.35
            let resolved = Color.white

            for row in 0...rows {
                for column in 0...columns {
                    let point = CGPoint(x: CGFloat(column) * spacing + spacing / 2,
                                        y: CGFloat(row) * spacing + spacing / 2)
                    guard point.x <= size.width, point.y <= size.height else { continue }

                    let normalised = hypot(point.x - centre.x, point.y - centre.y) / maxDistance
                    let lead = front - normalised
                    guard lead > 0 else { continue }

                    // Bright at the wavefront, fading back to the resting grid.
                    let flare = max(0, 1 - lead * 3.2)
                    let opacity = min(1, restOpacity * progress + flare * 0.85)
                    guard opacity > 0.01 else { continue }

                    let scale = 1 + flare * 1.4
                    let diameter = dotSize * scale
                    let rect = CGRect(x: point.x - diameter / 2,
                                      y: point.y - diameter / 2,
                                      width: diameter,
                                      height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(resolved.opacity(opacity)))
                }
            }
        }
        .foregroundStyle(tint)
        .allowsHitTesting(false)
    }
}
