import Testing
@testable import MiBancoCore

/// Lote final (ojo de diseño 7, retoque 5): la cifra protagonista quieta en ≤ 0,8 s a todos los niveles, las pequeñas en
/// 0,45 s y una duración propia para quien la necesite.
@Suite struct RollTimingTests {
    /// Lo que tarda de verdad en asentarse la última columna de las que salen de `DigitRoll.columns`.
    private func settled(_ timing: RollTiming, digits: Int) -> Double {
        let cols = DigitRoll.columns(
            from: 0, to: 9_999_999, digitCount: digits,
            base: timing.base, perColumn: timing.perColumn, stagger: timing.stagger)
        return cols.map { $0.delay + $0.duration }.max() ?? 0
    }

    @Test func totalIsWhenTheLastColumnSettles() {
        for n in 1...9 {
            #expect(abs(RollTiming.count.total(digitCount: n) - settled(.count, digits: n)) < 1e-9)
        }
    }

    @Test func leadSettlesWithinEightTenthsAtEveryLevel() {
        for level in MotionLevel.allCases {
            for n in 1...9 {
                let t = RollLength.lead.timing(.count, digitCount: n, level: level)
                #expect(settled(t, digits: n) <= RollLength.leadLimit + 1e-9, "\(level) \(n) columnas")
            }
        }
        // 3.774,75 € (6 columnas) a Expresivo duraba 0,96 s.
        #expect(RollTiming.count.scaled(MotionLevel.expressive.timeScale).total(digitCount: 6) > 0.8)
    }

    @Test func leadKeepsItsPaceWhenItAlreadyFits() {
        let t = RollLength.lead.timing(.count, digitCount: 3, level: .balanced)
        #expect(t == RollTiming.count)
    }

    @Test func briefRollsInFortyFiveHundredths() {
        for level in MotionLevel.allCases {
            for n in 1...9 {
                let t = RollLength.brief.timing(.count, digitCount: n, level: level)
                #expect(settled(t, digits: n) <= RollLength.briefLimit + 1e-9, "\(level) \(n) columnas")
            }
        }
        let balanced = RollLength.brief.timing(.count, digitCount: 5, level: .balanced)
        #expect(abs(settled(balanced, digits: 5) - 0.45) < 1e-9)
    }

    @Test func customLengthLastsWhatIsAsked() {
        let t = RollLength.seconds(1.2).timing(.count, digitCount: 5, level: .balanced)
        #expect(abs(settled(t, digits: 5) - 1.2) < 1e-9)
        // Con Sutil, más corta; con Expresivo, nunca más larga de lo pedido.
        let subtle = RollLength.seconds(1.2).timing(.count, digitCount: 5, level: .subtle)
        #expect(abs(settled(subtle, digits: 5) - 1.2 * MotionLevel.subtle.timeScale) < 1e-9)
        let expressive = RollLength.seconds(1.2).timing(.count, digitCount: 5, level: .expressive)
        #expect(abs(settled(expressive, digits: 5) - 1.2) < 1e-9)
    }

    @Test func shapeIsKept() {
        let t = RollTiming.count.lasting(0.45, digitCount: 6)
        #expect(abs(t.perColumn / t.base - RollTiming.count.perColumn / RollTiming.count.base) < 1e-9)
        #expect(abs(t.stagger / t.base - RollTiming.count.stagger / RollTiming.count.base) < 1e-9)
    }

    /// Ojo de diseño 2.1: al cerrar el ojo nunca queda solo «, €». Cada casilla enseña su punto o el dígito al aza
    /// del último fotograma del barajado, nunca nada.
    @Test func closingNeverLeavesAnEmptyCell() {
        let last = AmountMask.scrambledDigits(count: 5, step: 6, seed: 42)
        for popped in 0...5 {
            let cells = AmountMask.closingCells(count: 5, popped: popped, seed: 42)
            #expect(cells.count == 5)
            for (i, cell) in cells.enumerated() {
                if i < popped { #expect(cell == nil) } else { #expect(cell == last[i]) }
            }
        }
        #expect(AmountMask.closingCells(count: 5, popped: 0, seed: 42).allSatisfy { $0 != nil })
    }

    /// 16.2: los totales de Suscripciones ruedan explícitamente en 0,45 s (`RollLength.subscriptionsTotals`), respetan
    /// `MotionLevel` (más corto en Sutil, nunca por encima de 0,45 s en Equilibrado/Expresivo) y escalan con cámara lenta.
    @Test func subscriptionsTotalsRollInFortyFiveHundredths() {
        #expect(RollLength.subscriptionsTotals == .seconds(0.45))
        for n in 1...9 {
            let balanced = RollLength.subscriptionsTotals.timing(.count, digitCount: n, level: .balanced)
            let expressive = RollLength.subscriptionsTotals.timing(.count, digitCount: n, level: .expressive)
            let subtle = RollLength.subscriptionsTotals.timing(.count, digitCount: n, level: .subtle)
            #expect(abs(settled(balanced, digits: n) - 0.45) < 1e-9, "Equilibrado \(n) columnas")
            #expect(abs(settled(expressive, digits: n) - 0.45) < 1e-9, "Expresivo \(n) columnas")
            #expect(abs(settled(subtle, digits: n) - 0.45 * MotionLevel.subtle.timeScale) < 1e-9, "Sutil \(n) columnas")
        }
        // Con cámara lenta (×4), 0,45 s pasan a 1,80 s.
        let slow = RollLength.subscriptionsTotals.timing(.count, digitCount: 5, level: .balanced).scaled(4)
        #expect(abs(settled(slow, digits: 5) - 1.8) < 1e-9)
        // Diferencia real frente a `.brief` en Sutil: `.brief` topa el 0,80 × 0,85 = 0,68 s en 0,45 s; `.seconds(0.45)` escala a 0,3825 s.
        let briefSubtle = RollLength.brief.timing(.count, digitCount: 5, level: .subtle)
        let explicitSubtle = RollLength.subscriptionsTotals.timing(.count, digitCount: 5, level: .subtle)
        #expect(settled(explicitSubtle, digits: 5) < settled(briefSubtle, digits: 5) - 0.05)
    }
}
