// Cómo se reparte la pantalla de un paso de la guía entre el dibujo y el texto. Una sola regla, sin variantes:
// lo que él necesita para seguir el paso (la instrucción entera y «¿No te sale esto?») nunca queda bajo los botones
// fijos cuando cabe, en cualquier iPhone y con cualquier tamaño de letra.

/// En qué orden van el dibujo y el texto de un paso.
public enum GuideStepOrder: Equatable, Sendable {
    /// Dibujo arriba y, debajo, lo imprescindible: todo cabe sin deslizar.
    case drawingFirst
    /// Lo imprescindible arriba, después «Empezar desde el principio» si está, y el dibujo debajo a 180 pt; se desliza.
    case textFirst
}

/// El orden y el alto del dibujo (en puntos) de un paso.
public struct GuideStepArrangement: Equatable, Sendable {
    public let order: GuideStepOrder
    public let drawing: Double

    public init(order: GuideStepOrder, drawing: Double) {
        self.order = order
        self.drawing = drawing
    }

    /// El dibujo no baja de aquí (por debajo ya no se lee) ni pasa de su tamaño natural.
    public static let minDrawing = 180.0
    public static let maxDrawing = 395.0
}

/// - Parameters:
///   - visible: H, el alto visible entre la cabecera y los botones fijos.
///   - essentials: T, lo imprescindible medido: el aviso «¡Funciona!» si se ve, el título, la instrucción entera y
///     «¿No te sale esto?» cerrado, con sus separaciones y la separación al dibujo.
///   - restart: R, «Empezar desde el principio» con su separación cuando se ofrece; si no, 0.
///   - help: el alto medido de la ayuda abierta más su separación (8 pt), o 0 cuando está cerrada (G28).
/// Si queda sitio para el dibujo mínimo (H − T >= 180), el dibujo va arriba: con ayuda cerrada su alto está entre 180 y
/// 395; con ayuda abierta es H − T − R − help (tope 395), o 0 (oculto) si baja de 180. Si H − T < 180, el texto va arriba
/// y el dibujo debajo a 180. Cualquier valor que no sea un número, H <= 0 o T < 0: texto arriba. R < 0 o help < 0 cuentan como 0.
public func guideStepArrangement(visible: Double, essentials: Double, restart: Double,
                                 help: Double = 0) -> GuideStepArrangement {
    let minimum = GuideStepArrangement.minDrawing
    let textFirst = GuideStepArrangement(order: .textFirst, drawing: minimum)
    guard visible.isFinite, essentials.isFinite, restart.isFinite, help.isFinite,
          visible > 0, essentials >= 0 else { return textFirst }
    let restart = max(0, restart)
    let help = max(0, help)
    guard visible - essentials >= minimum else { return textFirst }
    if help == 0 {
        let drawing = min(GuideStepArrangement.maxDrawing, max(minimum, visible - essentials - restart))
        return GuideStepArrangement(order: .drawingFirst, drawing: drawing)
    }
    let available = visible - essentials - restart - help
    let drawing = available < minimum ? 0 : min(GuideStepArrangement.maxDrawing, available)
    return GuideStepArrangement(order: .drawingFirst, drawing: drawing)
}
