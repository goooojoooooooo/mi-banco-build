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
/// Si queda sitio para el dibujo mínimo (H − T >= 180), el dibujo va arriba con el alto que dejan T y R (entre 180 y
/// 395). Si no, el texto va arriba y el dibujo, debajo a 180. Cualquier valor que no sea un número, H <= 0 o T < 0:
/// texto arriba. R < 0 cuenta como 0.
public func guideStepArrangement(visible: Double, essentials: Double, restart: Double) -> GuideStepArrangement {
    let minimum = GuideStepArrangement.minDrawing
    let textFirst = GuideStepArrangement(order: .textFirst, drawing: minimum)
    guard visible.isFinite, essentials.isFinite, restart.isFinite, visible > 0, essentials >= 0 else { return textFirst }
    let restart = max(0, restart)
    guard visible - essentials >= minimum else { return textFirst }
    let drawing = min(GuideStepArrangement.maxDrawing, max(minimum, visible - essentials - restart))
    return GuideStepArrangement(order: .drawingFirst, drawing: drawing)
}

/// Hasta dónde se desliza el contenido de un paso al abrir «¿No te sale esto?» (todo en puntos, desde arriba del
/// contenido). Si la ayuda cabe en lo visible, se ve entera con el mínimo movimiento (si ya se ve, no se mueve; si su
/// final queda debajo, ese final queda justo encima de los botones). Si no cabe, su primera línea queda arriba del todo.
/// Nunca pasa del final del contenido ni de arriba del todo.
/// - Parameters:
///   - top: dónde empieza la ayuda dentro del contenido.
///   - height: el alto de la ayuda.
///   - offset: el desplazamiento de ahora.
///   - visible: H, el alto visible.
///   - content: el alto del contenido ya con la ayuda.
public func guideHelpScrollTarget(top: Double, height: Double, offset: Double, visible: Double,
                                  content: Double) -> Double {
    let now = offset.isFinite ? max(0, offset) : 0
    guard top.isFinite, height.isFinite, visible.isFinite, content.isFinite, visible > 0, height >= 0 else { return now }
    let target = height <= visible ? min(max(now, top + height - visible), top) : top
    return min(max(0, target), max(0, content - visible))
}
