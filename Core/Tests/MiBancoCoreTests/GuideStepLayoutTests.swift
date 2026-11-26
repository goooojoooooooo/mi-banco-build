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
            // Valores negativos (G27): R < 0 cuenta como 0; T < 0 no tiene sentido y deja el texto arriba.
            Row(h: 450, t: 250, r: -100, order: .drawingFirst, drawing: 200),
            Row(h: 450, t: -10, r: 0, order: .textFirst, drawing: 180),
        ]
        for row in table {
            let got = guideStepArrangement(visible: row.h, essentials: row.t, restart: row.r)
            #expect(got == GuideStepArrangement(order: row.order, drawing: row.drawing), "H \(row.h), T \(row.t), R \(row.r)")
        }
    }

    /// Con la ayuda abierta (G28): el dibujo cede su alto; si bajaría de 180 pt pasa a 0 (oculto).
    /// Filas con los marcos medidos en el iPhone de 393 pt y en el Pro Max, más un caso donde el dibujo cabe.
    @Test func conLaAyudaAbiertaElDibujoCedeElSitio() {
        let cases: [(h: Double, t: Double, r: Double, help: Double, order: GuideStepOrder, drawing: Double)] = [
            // iPhone pequeño: H 450,33, T + R = 270,33, ayuda 156,33 → quedarían 23,67 < 180 → 0 (oculto).
            (450.33, 206.33, 64, 156.33, .drawingFirst, 0),
            // Mismo paso con la ayuda más larga (240,33) → 0 (oculto).
            (450.33, 206.33, 64, 240.33, .drawingFirst, 0),
            // Pro Max: H 551,33, T + R = 270,33, ayuda 156,33 → quedarían 124,67 < 180 → 0 (oculto).
            (551.33, 206.33, 64, 156.33, .drawingFirst, 0),
            // Pantalla holgada donde el dibujo sigue cabiendo: 700 − 270 − 156 = 274.
            (700, 206, 64, 156, .drawingFirst, 274),
            // Tope superior del dibujo (395 pt).
            (900, 200, 0, 150, .drawingFirst, 395),
            // Frontera exacta de 180 pt: 180 se queda, 179,5 se oculta.
            (450, 200, 0, 70, .drawingFirst, 180),
            (450, 200, 0, 70.5, .drawingFirst, 0),
            // Con texto arriba (letra grande), el orden sigue siendo texto arriba y dibujo a 180 debajo.
            (450, 270.5, 0, 156, .textFirst, 180),
            // Ayuda negativa cuenta como 0 (cerrada); no finito deja texto arriba.
            (450, 234, 64, -50, .drawingFirst, 180),
            (450, 206, 0, .nan, .textFirst, 180),
            (450, 206, 0, .infinity, .textFirst, 180),
        ]
        for c in cases {
            let got = guideStepArrangement(visible: c.h, essentials: c.t, restart: c.r, help: c.help)
            #expect(got.order == c.order && abs(got.drawing - c.drawing) < 0.01,
                    "H \(c.h), T \(c.t), R \(c.r), help \(c.help): \(got)")
        }
    }

    /// Barrido con la ayuda abierta (G28): si dibujo arriba y T + R + help <= H, todas las piezas acaban en o por encima
    /// de H (sin nada que deslizar); el dibujo nunca sale entre 0 y 180 exclusivos.
    @Test func laAyudaAbiertaCabeYSinDibujoIntermedio() {
        var h = 300.0
        while h <= 800 {
            var t = 60.0
            while t <= 900 {
                for r in [0.0, 56, 64] {
                    for help in [0.0, 80, 156.33, 240.33, 400] {
                        let a = guideStepArrangement(visible: h, essentials: t, restart: r, help: help)
                        #expect(a.drawing == 0 || (a.drawing >= 180 && a.drawing <= 395),
                                "Dibujo prohibido \(a.drawing) para H \(h), T \(t), R \(r), help \(help)")
                        if help > 0 && a.order == .drawingFirst && t + r + help <= h {
                            #expect(a.drawing + t + r + help <= h + 1e-9,
                                    "Se pasa de H: \(a.drawing) + \(t) + \(r) + \(help) > \(h)")
                        }
                    }
                }
                t += 11.5
            }
            h += 13
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
