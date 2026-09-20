import SwiftUI

/// A list of numbers SwiftUI can interpolate.
///
/// `animatableData` has to be a single `VectorArithmetic` value, and nesting
/// ten `AnimatablePair`s to morph a ten-point curve is unreadable. This lets a
/// shape animate its whole set of control points as one value, so a preset
/// change sweeps the response curve smoothly instead of snapping it.
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: AnimatableVector { AnimatableVector([]) }

    /// Mismatched lengths are padded rather than dropped: SwiftUI can ask for
    /// arithmetic against `.zero` mid-transition, and truncating there would
    /// collapse the curve to a point for one frame.
    private static func combine(_ lhs: AnimatableVector,
                                _ rhs: AnimatableVector,
                                _ transform: (Double, Double) -> Double) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < lhs.values.count ? lhs.values[index] : 0
            let right = index < rhs.values.count ? rhs.values[index] : 0
            result[index] = transform(left, right)
        }
        return AnimatableVector(result)
    }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, +)
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        combine(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        for index in values.indices { values[index] *= rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}
