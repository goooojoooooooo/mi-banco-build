import Testing
@testable import MiBancoCore

@Suite struct MotionMathTests {
    private func near(_ a: Double, _ b: Double, _ tol: Double = 0.0005) -> Bool { abs(a - b) <= tol }

    @Test func balancedIsIdentity() {
        let spec = SpringSpec(response: 0.46, dampingFraction: 0.74)
        #expect(MotionMath.scaled(spec, level: .balanced) == spec)
    }

    @Test func subtleIsShorterAndCalmer() {
        let s = MotionMath.scaled(SpringSpec(response: 0.46, dampingFraction: 0.74), level: .subtle)
        #expect(near(s.response, 0.391))
        #expect(near(s.dampingFraction, 0.883))
    }

    @Test func expressiveBouncesMoreButCapped() {
        let e = MotionMath.scaled(SpringSpec(response: 0.46, dampingFraction: 0.74), level: .expressive)
        #expect(near(e.response, 0.5152))
        #expect(near(e.dampingFraction, 0.558))
        let capped = MotionMath.scaled(SpringSpec(response: 0.42, dampingFraction: 0.50), level: .expressive)
        #expect(near(capped.dampingFraction, 0.38))
    }

    @Test func timeMultiplierOnlyStretchesTime() {
        let s = MotionMath.scaled(SpringSpec(response: 0.46, dampingFraction: 0.74), level: .balanced, timeMultiplier: 4)
        #expect(near(s.response, 1.84))
        #expect(near(s.dampingFraction, 0.74))
    }

    @Test func staggerShrinksAndCaps() {
        let d = MotionMath.staggerDelays(count: 12, firstGap: 0.055, decay: 0.8)
        #expect(d.count == 12)
        for (got, want) in zip(d.prefix(5), [0, 0.055, 0.099, 0.1342, 0.16236]) {
            #expect(abs(got - want) < 0.0001)
        }
        for i in 9...11 { #expect(d[i] == d[8]) }
    }

    @Test func rubberBandIsMonotonicAndBounded() {
        #expect(MotionMath.rubberBand(0, dimension: 100) == 0)
        let values = [10, 50, 200, 2000].map { MotionMath.rubberBand($0, dimension: 100) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(MotionMath.rubberBand(2000, dimension: 100) < 100 / 0.55)
    }

    @Test func calmNeverBounces() {
        let spec = SpringSpec(response: 0.42, dampingFraction: 0.5)
        #expect(MotionMath.calm(spec) == SpringSpec(response: 0.42, dampingFraction: 1))
        for level in MotionLevel.allCases {
            #expect(MotionMath.calm(MotionMath.scaled(spec, level: level)).dampingFraction == 1)
        }
    }
}
