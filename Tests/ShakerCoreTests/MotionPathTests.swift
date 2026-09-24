import CoreGraphics
import Foundation
import Testing
@testable import ShakerCore

private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

@Suite struct MotionPathTests {
    @Test(arguments: 0..<200)
    func returnsToOriginAndStaysWithinAmplitude(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed))
        let origin = CGPoint(x: 700, y: 450)
        let path = MotionPath.natural(from: origin, amplitude: 10, steps: 16, bounds: screen, using: &rng)
        #expect(path.count == 16)
        #expect(path.last == origin)
        // Bézier hull ≤ amplitude, plus ≤ 0.71 of jitter.
        #expect(path.allSatisfy { distance($0, origin) <= 11 })
        // It actually goes somewhere.
        #expect(path.map { distance($0, origin) }.max()! >= 5)
    }

    @Test(arguments: 0..<200)
    func staysOnScreenInCorners(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed))
        for corner in [CGPoint(x: 0, y: 0), CGPoint(x: 1439, y: 899), CGPoint(x: 0, y: 899), CGPoint(x: 1439, y: 0)] {
            let path = MotionPath.natural(from: corner, amplitude: 30, steps: 20, bounds: screen, using: &rng)
            #expect(path.allSatisfy { $0.x >= 0 && $0.x <= 1439 && $0.y >= 0 && $0.y <= 899 })
            #expect(path.last == corner)
        }
    }

    @Test func worksOnSecondaryDisplayWithNegativeOrigin() {
        var rng = SplitMix64(seed: 7)
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let origin = CGPoint(x: -1000, y: 300)
        let path = MotionPath.natural(from: origin, amplitude: 8, steps: 12, bounds: left, using: &rng)
        #expect(path.last == origin)
        #expect(path.allSatisfy { left.contains($0) })
    }

    @Test func offScreenOriginIsClamped() {
        var rng = SplitMix64(seed: 1)
        let path = MotionPath.natural(from: CGPoint(x: 5000, y: -50), amplitude: 8, steps: 12, bounds: screen, using: &rng)
        #expect(path.last == CGPoint(x: 1439, y: 0))
    }

    @Test func sameSeedSamePath() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        let o = CGPoint(x: 100, y: 100)
        #expect(
            MotionPath.natural(from: o, amplitude: 8, steps: 12, bounds: screen, using: &a)
                == MotionPath.natural(from: o, amplitude: 8, steps: 12, bounds: screen, using: &b)
        )
    }

    @Test func tooFewStepsAreRaisedToFour() {
        var rng = SplitMix64(seed: 3)
        #expect(MotionPath.natural(from: CGPoint(x: 100, y: 100), amplitude: 8, steps: 1, bounds: screen, using: &rng).count == 4)
    }
}
