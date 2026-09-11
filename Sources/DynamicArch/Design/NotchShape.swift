import SwiftUI

/// The island silhouette.
///
/// Top corners curve *outward* so the body melts into the display bezel exactly
/// like the hardware cutout; bottom corners are continuous-curvature (squircle)
/// roundings rather than plain arcs, which is what makes the morph read as
/// Apple-native instead of "rounded rectangle".
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat = 6, bottomRadius: CGFloat = 14) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set {
            topRadius = max(0, newValue.first)
            bottomRadius = max(0, newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let top = min(topRadius, rect.height / 2)
        let bottom = min(bottomRadius, min(rect.height - top, rect.width / 2 - top))
        // Magic ratio for continuous curvature: pushing the control points out
        // to ~1.28r turns a circular arc into an Apple-style squircle corner.
        let k: CGFloat = 1.28

        // Start left of the body, at the very top edge (under the bezel).
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        // Inverted top-left fillet.
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + top),
            control1: CGPoint(x: rect.minX - top * (1 - 0.55), y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Left edge.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        // Bottom-left squircle.
        path.addCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - bottom + bottom * k * 0.45),
            control2: CGPoint(x: rect.minX + bottom - bottom * k * 0.45, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        // Bottom-right squircle.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control1: CGPoint(x: rect.maxX - bottom + bottom * k * 0.45, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - bottom + bottom * k * 0.45)
        )
        // Right edge.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        // Inverted top-right fillet.
        path.addCurve(
            to: CGPoint(x: rect.maxX + top, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.minY),
            control2: CGPoint(x: rect.maxX + top * (1 - 0.55), y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
