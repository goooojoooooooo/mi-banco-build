import Testing
@testable import MiBancoCore

/// Reglas puras de la fila deslizada (N-1 y N-2): el importe y las acciones nunca tienen opacidad > 0 a la vez (ni al
/// abrir ni al cerrar), y con texto de accesibilidad el nombre nunca entra en el borde izquierdo ni se recorta.
@Suite struct SwipeRowMotionTests {
    @Test func amountAndActionsAreNeverVisibleTogether() {
        // Barrido completo de apertura y cierre cada 0,5 pt.
        for step in 0...360 {
            let offset = -Double(step) * 0.5
            let amount = SwipeRowMotion.amountOpacity(offset: offset)
            let actions = SwipeRowMotion.actionsOpacity(offset: offset)
            #expect(amount >= 0 && amount <= 1)
            #expect(actions >= 0 && actions <= 1)
            #expect(amount == 0 || actions == 0, "En offset \(offset): importe=\(amount), acciones=\(actions)")
        }
    }

    @Test func amountFadesBeforeActionsEnter() {
        #expect(SwipeRowMotion.amountOpacity(offset: 0) == 1)
        #expect(SwipeRowMotion.amountOpacity(offset: 10) == 1)
        #expect(SwipeRowMotion.amountOpacity(offset: -12.5) == 0.5)
        #expect(SwipeRowMotion.amountOpacity(offset: -25) == 0)
        #expect(SwipeRowMotion.amountOpacity(offset: -144) == 0)

        #expect(SwipeRowMotion.actionsOpacity(offset: 0) == 0)
        #expect(SwipeRowMotion.actionsOpacity(offset: -25) == 0)
        #expect(SwipeRowMotion.actionsOpacity(offset: -50) == 0.5)
        #expect(SwipeRowMotion.actionsOpacity(offset: -75) == 1)
        #expect(SwipeRowMotion.actionsOpacity(offset: -144) == 1)
    }

    @Test func normalSizeShiftsByFortyPercent() {
        let shift = SwipeRowMotion.contentShift(offset: -144, span: 144, leadingShiftLimit: nil)
        #expect(abs(shift - (-57.6)) < 1e-9)
        #expect(SwipeRowMotion.contentShift(offset: 0, span: 144, leadingShiftLimit: nil) == 0)
    }

    @Test func accessibilitySizeKeepsFirstLetterPastTheLeadingEdge() {
        let gutter = 20.0
        let span = 134.0
        // Tamaños de losa desde AX1 (~66 pt) hasta AX5 (~125 pt) más 14 pt de hueco.
        for tileSize in [66.0, 78.0, 94.0, 104.0, 111.0, 125.0] {
            let limit = tileSize + 14.0
            let shift = SwipeRowMotion.contentShift(offset: -span, span: span, leadingShiftLimit: limit)
            let nameMinX = gutter + limit + shift
            #expect(nameMinX >= gutter - 1e-9, "Con losa \(tileSize): la primera letra queda en x=\(nameMinX)")
            #expect(shift <= 0 && abs(shift) <= span + 1e-9)
        }
        // Al arrastrar hacia la derecha (resistencia elástica), no se invierte ni se dispara.
        let right = SwipeRowMotion.contentShift(offset: 12, span: span, leadingShiftLimit: 118)
        #expect(right > 0 && right <= 12)
    }
}
