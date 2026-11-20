import Testing
@testable import MiBancoCore

@Suite struct DigitRollTests {
    @Test func countUpFromZero() {
        let cols = DigitRoll.columns(from: 0, to: 377475, digitCount: 6)
        #expect(cols.map { $0.to - $0.from } == [3, 17, 17, 14, 17, 15])
        #expect(cols.map(\.place) == [5, 4, 3, 2, 1, 0])
    }

    /// 3.774,75 -> 3.769,95. Decena: del 7 al 9 bajando son 8 pasos y, como el cambio es de 48 decenas, una vuelta más (-18).
    @Test func paymentRollsDown() {
        let cols = DigitRoll.columns(from: 377475, to: 376995, digitCount: 6)
        #expect(cols.map { $0.to - $0.from } == [0, 0, -1, -5, -18, -10])
    }

    @Test func delaysAndDurationsStagger() {
        let cols = DigitRoll.columns(from: 0, to: 377475, digitCount: 6)
        for (i, c) in cols.enumerated() {
            #expect(abs(c.delay - 0.022 * Double(i)) < 1e-9)
            #expect(abs(c.duration - (0.56 + 0.038 * Double(i))) < 1e-9)
        }
    }

    @Test func positionLandsAndOvershoots() {
        let c = DigitColumn(place: 0, from: 4, to: 9, delay: 0, duration: 0.6)
        #expect(DigitRoll.position(c, at: 0, overshoot: 0.17) == 4)
        #expect(abs(DigitRoll.position(c, at: 0.468, overshoot: 0.17) - 9.17) < 0.001)
        #expect(DigitRoll.position(c, at: 0.6, overshoot: 0.17) == 9)
        #expect(DigitRoll.position(c, at: 5, overshoot: 0.17) == 9)
    }

    @Test func speedIsZeroOutsideTheRoll() {
        let c = DigitColumn(place: 0, from: 4, to: 9, delay: 0.1, duration: 0.6)
        #expect(DigitRoll.speed(c, at: 0.05, overshoot: 0.17) == 0)
        #expect(DigitRoll.speed(c, at: 2, overshoot: 0.17) == 0)
        #expect(DigitRoll.speed(c, at: 0.2, overshoot: 0.17) > 5)
    }

    @Test func retargetFromFractionalPosition() {
        let c = DigitRoll.columns(from: 3000, to: 7000, digitCount: 4, startingAt: [3.4, 0, 0, 0])[0]
        #expect(c.from == 3.4)
        #expect(c.to == 7.0)
    }

    @Test func widerNumberKeepsRightAlignment() {
        let c = DigitRoll.columns(from: 99900, to: 144900, digitCount: 6)[0]
        #expect(c.from == 0)
        #expect(c.to == 1)
    }

    @Test func unchangedNumberDoesNotMove() {
        let cols = DigitRoll.columns(from: 12345, to: 12345, digitCount: 5)
        #expect(cols.allSatisfy { $0.to == $0.from })
    }
}

@Suite struct AmountMaskTests {
    @Test func maskNeverContainsDigitsNorDependsOnTheAmount() {
        for negative in [true, false] {
            let text = AmountMask.text(negative: negative, showsPlus: false)
            #expect(text.allSatisfy { !$0.isNumber })
            #expect(text.hasSuffix("•••,••\u{00A0}€"))
        }
        #expect(AmountMask.text(negative: true, showsPlus: false).hasPrefix("−"))
        #expect(AmountMask.text(negative: false, showsPlus: true).hasPrefix("+"))
        #expect(AmountMask.text(negative: false, showsPlus: false) == "•••,••\u{00A0}€")
    }

    /// El barajado del ojo usa dígitos propios (semilla y paso), no los del importe.
    @Test func scrambleIsDeterministicAndIndependentOfTheAmount() {
        let a = AmountMask.scrambledDigits(count: 6, step: 2, seed: 7)
        #expect(a == AmountMask.scrambledDigits(count: 6, step: 2, seed: 7))
        #expect(a.count == 6)
        #expect(a.allSatisfy { (0...9).contains($0) })
        #expect(a != AmountMask.scrambledDigits(count: 6, step: 3, seed: 7))
    }
}
