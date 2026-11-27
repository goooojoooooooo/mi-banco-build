import Testing
@testable import MiBancoCore

/// Sonda pura del abanico con Reducir movimiento (m-7 punto 9): durante la transición del negro sobre Inicio y la
/// entrada del abanico, mide la visibilidad mínima (`max(inicio, abanico)`) y cuántos fotogramas tienen ambos a la vez
/// por encima del umbral de solape (20 %).
@Suite struct FanReduceAuditTests {
    /// Curva de salida suave aproximada (0→1 en [0, duration], tras `delay`).
    private func easeOut(t: Double, delay: Double, duration: Double) -> Double {
        let u = min(max((t - delay) / duration, 0), 1)
        return 1 - (1 - u) * (1 - u) * (1 - u)
    }

    @Test func staggeredFadeNeverBlanksNorOverlaps() {
        var audit = FanReduceAudit()
        // Igual que `WalletFan`: negro en 0,16 s, abanico en 0,22 s tras 0,13 s.
        for step in 0...80 {
            let t = Double(step) * 0.005
            let dark = easeOut(t: t, delay: 0, duration: 0.16)
            let fan = easeOut(t: t, delay: 0.13, duration: 0.22)
            audit.record(layer: .backdrop, opacity: dark)
            audit.record(layer: .fan, opacity: fan)
        }
        #expect(audit.samples > 10)
        #expect(audit.minVisiblePermille > 0, "No puede haber un fotograma en negro total")
        #expect(audit.overlapFrames == 0, "Inicio y el abanico no pueden solaparse por encima del 20 %")
    }

    @Test func simultaneousFadeDetectsOverlap() {
        var audit = FanReduceAudit()
        // Regresión: el abanico empieza a la vez que el negro (retardo 0).
        for step in 0...80 {
            let t = Double(step) * 0.005
            let dark = easeOut(t: t, delay: 0, duration: 0.16)
            let fan = easeOut(t: t, delay: 0, duration: 0.22)
            audit.record(layer: .backdrop, opacity: dark)
            audit.record(layer: .fan, opacity: fan)
        }
        #expect(audit.overlapFrames > 0, "Con retardo 0 debe detectar solape entre Inicio y el abanico")
    }

    @Test func gapBetweenFadesDetectsTotalBlack() {
        var audit = FanReduceAudit()
        // Regresión contraria: el abanico tarda demasiado y queda pantalla en negro total entre medias.
        for step in 0...100 {
            let t = Double(step) * 0.005
            let dark = easeOut(t: t, delay: 0, duration: 0.16)
            let fan = easeOut(t: t, delay: 0.25, duration: 0.22)
            audit.record(layer: .backdrop, opacity: dark)
            audit.record(layer: .fan, opacity: fan)
        }
        #expect(audit.minVisiblePermille == 0, "Con hueco entre los dos fundidos debe marcar 0 (negro total)")
        #expect(audit.overlapFrames == 0)
    }

    @Test func ignoresNonFiniteValues() {
        var audit = FanReduceAudit()
        audit.record(layer: .backdrop, opacity: .nan)
        audit.record(layer: .fan, opacity: .infinity)
        #expect(audit.samples == 0)
        #expect(audit.minVisiblePermille == 1_000)
        #expect(audit.overlapFrames == 0)
    }
}
