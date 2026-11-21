import Testing
@testable import MiBancoCore

/// Cómo se reparte un paso de la guía entre el dibujo y el texto (G21): una sola regla, con la tabla del fallo.
@Suite struct GuideStepLayoutTests {
    private struct Row {
        let h: Double
        let t: Double
        let r: Double
        let order: GuideStepOrder
        let drawing: Double
    }

    /// (H, T, R) → (orden, alto del dibujo). H: alto visible entre la cabecera y los botones fijos; T: lo imprescindible
    /// (aviso «¡Funciona!» si está, título, instrucción entera y «¿No te sale esto?» cerrado, con la separación al dibujo);
    /// R: «Empezar desde el principio» con su separación, o 0.
    @Test func laTablaDelFallo() {
        let table: [Row] = [
            Row(h: 450, t: 206, r: 0, order: .drawingFirst, drawing: 244),
            Row(h: 450, t: 206, r: 64, order: .drawingFirst, drawing: 180),
            Row(h: 450, t: 234, r: 64, order: .drawingFirst, drawing: 180),
            Row(h: 450, t: 270, r: 0, order: .drawingFirst, drawing: 180),
            Row(h: 450, t: 270.5, r: 0, order: .textFirst, drawing: 180),
            Row(h: 442, t: 280, r: 64, order: .textFirst, drawing: 180),
            Row(h: 450, t: 460, r: 0, order: .textFirst, drawing: 180),
            Row(h: 700, t: 200, r: 0, order: .drawingFirst, drawing: 395),
            Row(h: 700, t: 200, r: 64, order: .drawingFirst, drawing: 395),
            Row(h: 552, t: 300, r: 64, order: .drawingFirst, drawing: 188),
            Row(h: 0, t: 100, r: 0, order: .textFirst, drawing: 180),
            Row(h: .nan, t: 100, r: 0, order: .textFirst, drawing: 180),
        ]
        for row in table {
            let got = guideStepArrangement(visible: row.h, essentials: row.t, restart: row.r)
            #expect(got == GuideStepArrangement(order: row.order, drawing: row.drawing), "H \(row.h), T \(row.t), R \(row.r)")
        }
    }

    @Test func loQueNoEsUnNumeroDejaElTextoArriba() {
        let odd: [Row] = [
            Row(h: .infinity, t: 100, r: 0, order: .textFirst, drawing: 180),
            Row(h: 450, t: .nan, r: 0, order: .textFirst, drawing: 180),
            Row(h: 450, t: -.infinity, r: 0, order: .textFirst, drawing: 180),
            Row(h: 450, t: 100, r: .nan, order: .textFirst, drawing: 180),
            Row(h: 450, t: 100, r: .infinity, order: .textFirst, drawing: 180),
            Row(h: -10, t: 100, r: 0, order: .textFirst, drawing: 180),
        ]
        for row in odd {
            let got = guideStepArrangement(visible: row.h, essentials: row.t, restart: row.r)
            #expect(got == GuideStepArrangement(order: row.order, drawing: row.drawing), "H \(row.h), T \(row.t), R \(row.r)")
        }
    }

    /// Lo que la regla garantiza: si lo imprescindible cabe, se ve entero sin deslizar (dibujo arriba: dibujo + T <= H;
    /// texto arriba: T <= H); el reinicio se ve si H − T − R >= 180; el dibujo nunca baja de 180 ni pasa de 395.
    @Test func loImprescindibleNuncaQuedaDebajo() {
        var h = 300.0
        while h <= 800 {
            var t = 60.0
            while t <= 900 {
                for r in [0.0, 56, 64] {
                    let a = guideStepArrangement(visible: h, essentials: t, restart: r)
                    #expect(a.drawing >= 180 && a.drawing <= 395)
                    if t <= h {
                        let essentialsBottom = a.order == .drawingFirst ? a.drawing + t : t
                        #expect(essentialsBottom <= h, "H \(h), T \(t), R \(r)")
                    }
                    if h - t - r >= 180 {
                        #expect(a.order == .drawingFirst && a.drawing + t + r <= h, "H \(h), T \(t), R \(r)")
                    }
                }
                t += 7.5
            }
            h += 11
        }
    }
}
