import CoreGraphics
import Foundation

/// Deterministic generator so motion paths are reproducible in tests.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum MotionPath {
    /// A short, slightly curved out-and-back loop in global display coordinates.
    ///
    /// The pointer eases out to a random point up to `amplitude` away, returns along a different
    /// curve, and the final point is exactly `origin` (clamped to `bounds`). Every point stays
    /// inside `bounds`.
    public static func natural<R: RandomNumberGenerator>(
        from origin: CGPoint,
        amplitude: Double,
        steps: Int,
        bounds: CGRect,
        using rng: inout R
    ) -> [CGPoint] {
        let home = clamp(origin, to: bounds)
        let steps = max(steps, 4)
        let amplitude = max(amplitude, 1)

        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let reach = amplitude * Double.random(in: 0.6...1.0, using: &rng)
        var target = CGPoint(x: home.x + reach * cos(angle), y: home.y + reach * sin(angle))
        // Near a screen edge, head the other way instead of getting squashed against it.
        if !inside(target, bounds) {
            target = CGPoint(x: home.x - reach * cos(angle), y: home.y - reach * sin(angle))
        }

        let outLeg = curve(from: home, to: target, bend: Double.random(in: 0.15...0.5, using: &rng))
        let backLeg = curve(from: target, to: home, bend: -Double.random(in: 0.15...0.5, using: &rng))

        let outSteps = steps / 2
        let backSteps = steps - outSteps
        var points: [CGPoint] = []
        for i in 1...outSteps {
            points.append(outLeg(ease(Double(i) / Double(outSteps))))
        }
        for i in 1...backSteps {
            points.append(backLeg(ease(Double(i) / Double(backSteps))))
        }

        // Sub-point jitter on intermediate points only; the endpoint stays exact.
        for i in 0..<(points.count - 1) {
            points[i].x += Double.random(in: -0.5...0.5, using: &rng)
            points[i].y += Double.random(in: -0.5...0.5, using: &rng)
        }
        points[points.count - 1] = home
        return points.map { clamp($0, to: bounds) }
    }

    /// Quadratic Bézier whose control point sits off the midpoint, perpendicular to the chord,
    /// by `bend` × chord length.
    static func curve(from a: CGPoint, to b: CGPoint, bend: Double) -> (Double) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let control = CGPoint(x: (a.x + b.x) / 2 - dy * bend, y: (a.y + b.y) / 2 + dx * bend)
        return { t in
            let u = 1 - t
            return CGPoint(
                x: u * u * a.x + 2 * u * t * control.x + t * t * b.x,
                y: u * u * a.y + 2 * u * t * control.y + t * t * b.y
            )
        }
    }

    /// Smoothstep ease-in-out.
    static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    static func inside(_ p: CGPoint, _ r: CGRect) -> Bool {
        p.x >= r.minX && p.x <= r.maxX - 1 && p.y >= r.minY && p.y <= r.maxY - 1
    }

    /// Clamp into `r`. Display bounds are half-open, so the last valid pixel is `max - 1`.
    public static func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(p.x, r.minX), r.maxX - 1),
            y: min(max(p.y, r.minY), r.maxY - 1)
        )
    }
}
