import Testing
@testable import MiBancoCore

/// Cómo se reparte un paso de la guía entre el dibujo y el texto (G21): una sola regla, con la tabla del fallo.
@Suite struct GuideStepLayoutTests {
    /// (H, T, R) → (orden, alto del dibujo). H: alto visible entre la cabecera y los botones fijos; T: lo imprescindible
    /// (aviso «¡Funciona!» si está, título, instrucción entera y «¿No te sale esto?» cerrado, con la separación al dibujo);
    /// R: «Empezar desde el principio» con su separación, o 0.
    @Test func laTablaDelFallo() {
        let table: [(Double, Double, Double, GuideStepOrder, Double)] = [
            (450, 206, 0, .drawingFirst, 244),
            (450, 206, 64, .drawingFirst, 180),
            (450, 234, 64, .drawingFirst, 180),
            (450, 270, 0, .drawingFirst, 180),
            (450, 270.5, 0, .textFirst, 180),
            (442, 280, 64, .textFirst, 180),
            (450, 460, 0, .textFirst, 180),
            (700, 200, 0, .drawingFirst, 395),
            (700, 200, 64, .drawingFirst, 395),
            (552, 300, 64, .drawingFirst, 188),
            (0, 100, 0, .textFirst, 180),
            (.nan, 100, 0, .textFirst, 180),
        ]
        for (h, t, r, order, drawing) in table {
            let got = guideStepArrangement(visible: h, essentials: t, restart: r)
            #expect(got == GuideStepArrangement(order: order, drawing: drawing), "H \(h), T \(t), R \(r)")
        }
    }

    @Test func loQueNoEsUnNumeroDejaElTextoArriba() {
        let odd: [(Double, Double, Double)] = [(.infinity, 100, 0), (450, .nan, 0), (450, -.infinity, 0), (450, 100, .nan),
                                               (450, 100, .infinity), (-10, 100, 0)]
        for (h, t, r) in odd {
            #expect(guideStepArrangement(visible: h, essentials: t, restart: r)
                    == GuideStepArrangement(order: .textFirst, drawing: 180), "H \(h), T \(t), R \(r)")
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
