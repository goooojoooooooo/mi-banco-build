import SwiftUI
import MiBancoCore

// Las piezas del arranque «logo en piezas»: el guion (`LaunchTimeline`, en Core) dice qué hay en cada instante y aquí
// solo se dibuja. Nada de esto decide nada: ni cuándo se enseña Inicio ni, por supuesto, cuándo se quita el bloqueo.

/// Qué tramo del guion se está representando.
enum LaunchAct: Equatable {
    /// El arranque entero, sin bloqueo: piezas, vuelo y negro que se aclara.
    case launch
    /// Sobre la marca del bloqueo: las piezas se montan y ahí se quedan.
    case lock
    /// Tras desbloquear: la marca vuela a su ranura (con las bandas en el arranque en frío).
    case exit(bands: Bool)
}

/// Cuándo empieza un tramo del arranque: ahora. (Solo en la demo de grabación: tras la espera que pida la prueba.)
enum LaunchClock {
    /// Los avisos del guion (encajar, montar Inicio, dejar pasar los toques, quitar la capa) se esperan con este
    /// margen: sin él, el sistema puede retrasar una espera hasta un 10 % de su duración.
    static let tolerance: Duration = .milliseconds(4)

    static func startDate() -> Date {
        #if DEBUG
        return Date().addingTimeInterval(DemoMode.launchHoldSeconds)
        #else
        return Date()
        #endif
    }
}

extension LaunchTimeline {
    /// El guion para el movimiento de ahora (intensidad, Reducir movimiento, Bajo consumo), con el muelle `fly` del kit.
    init(_ motion: MotionContext) {
        self.init(level: motion.level, reduceMotion: motion.reduce, lowPower: motion.lowPower, fly: SpringToken.fly.base)
    }
}

/// El reloj de un tramo del arranque: una sola `TimelineView` que calcula el fotograma y se lo pasa al contenido. Se
/// para en cuanto el tramo termina (`finished`) o si aún no ha empezado; quien la usa la quita de la pantalla al acabar.
struct LaunchStage<Content: View>: View {
    let timeline: LaunchTimeline
    let act: LaunchAct
    /// Cuándo empezó; nil = aún no (se dibuja el primer fotograma).
    let start: Date?
    /// Cuándo se tocó para saltar (solo en `.launch`).
    var skippedAt: Date? = nil
    let finished: Bool
    /// Multiplicador de tiempo de grabación (`MotionContext.timeMultiplier`).
    let timeMultiplier: Double
    @ViewBuilder let content: (LaunchFrame) -> Content

    var body: some View {
        TimelineView(.animation(paused: finished || start == nil)) { context in
            content(frame(at: context.date))
        }
    }

    private func frame(at date: Date) -> LaunchFrame {
        let multiplier = max(timeMultiplier, 0.01)
        var elapsed = 0.0
        var skipped: Double?
        if let start {
            elapsed = max(0, date.timeIntervalSince(start)) / multiplier
            if let skippedAt { skipped = max(0, skippedAt.timeIntervalSince(start)) / multiplier }
        }
        switch act {
        case .launch:
            if finished { return timeline.frame(at: timeline.duration, skipped: skipped != nil) }
            return timeline.frame(at: timeline.time(elapsed: elapsed, skippedAt: skipped), skipped: skipped != nil)
        case .lock:
            return timeline.lockFrame(at: finished ? timeline.lockDuration : elapsed)
        case .exit(let bands):
            return timeline.exitFrame(at: finished ? (timeline.exitDuration ?? 0) : elapsed, bands: bands)
        }
    }
}

/// La marca mientras se monta: la loseta llega (opacidad y escala), su canto se dibuja y, cuando las dos mitades de la
/// ola ya han encajado, la ola es la de siempre. Mientras las mitades vuelan las dibuja `LaunchHalvesCanvas` por encima.
struct LaunchMark: View {
    let frame: LaunchFrame
    var size: CGFloat = 96

    var body: some View {
        AppMark(
            size: size, drawn: frame.joined ? 1 : 0, edge: CGFloat(frame.edge), sheen: frame.sheen.map { CGFloat($0) },
            bodyOpacity: CGFloat(frame.body), bodyScale: CGFloat(0.82 + 0.18 * frame.body))
    }
}

/// El fondo del arranque en un solo `Canvas` a pantalla completa: las 26 líneas de velocidad que salen de la marca y
/// las dos bandas de titanio que la cruzan y se ensanchan. Va por debajo de la marca. No recibe toques.
struct LaunchSkyCanvas: View {
    let frame: LaunchFrame
    /// Centro de la marca en este lienzo.
    let center: CGPoint

    var body: some View {
        // Copias locales y cierre `@Sendable`: el lienzo no lee propiedades de la vista ni depende del hilo principal.
        let frame = frame
        let center = center
        Canvas { @Sendable context, size in
            drawLaunchLines(frame, center: center, in: context, size: size)
            drawLaunchBands(frame, center: center, in: context, size: size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Las dos mitades de la ola llegando desde esquinas opuestas con su estela, en un `Canvas` a pantalla completa que va
/// por ENCIMA de la marca (la loseta llega detrás de ellas). Solo existe mientras vuelan. No recibe toques.
struct LaunchHalvesCanvas: View {
    let frame: LaunchFrame
    /// Centro y lado de la marca en este lienzo.
    let center: CGPoint
    let markSize: CGFloat
    /// Recorrido según la intensidad: giro de las piezas y largo de su estela.
    let distanceScale: Double

    var body: some View {
        let frame = frame
        let center = center
        let markSize = markSize
        let distanceScale = distanceScale
        Canvas { @Sendable context, _ in
            drawLaunchHalves(frame, center: center, markSize: markSize, distanceScale: distanceScale, in: context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Las líneas de velocidad: cada una tiene su ángulo, su punto de salida, su largo y su retraso, fijos (no hay azar
/// entre fotogramas); salen de la marca hacia fuera, cada vez más deprisa, y se apagan.
private func drawLaunchLines(_ frame: LaunchFrame, center: CGPoint, in context: GraphicsContext, size: CGSize) {
    guard let progress = frame.lines else { return }
    let color = Color(hex: "#D7DADF")
    let reach = Double(hypot(size.width, size.height)) * 0.62
    let count = 26
    for k in 0..<count {
        let angle = Double(k) / Double(count) * 2 * Double.pi + sin(Double(k) * 12.9898) * 0.12
        let inner = 30 + Double((k * 37) % 60)
        let length = 26 + Double((k * 53) % 70)
        let delay = Double((k * 29) % 100) / 100 * 0.32
        let t = min(1, max(0, (progress - delay) / 0.68))
        guard t > 0, t < 1 else { continue }
        let eased = t * t
        let near = CGFloat(inner + reach * eased)
        let far = near + CGFloat(length * (0.4 + eased))
        let ux = CGFloat(cos(angle))
        let uy = CGFloat(sin(angle))
        var path = Path()
        path.move(to: CGPoint(x: center.x + ux * near, y: center.y + uy * near))
        path.addLine(to: CGPoint(x: center.x + ux * far, y: center.y + uy * far))
        let width: CGFloat = k % 3 == 0 ? 1.5 : 1
        context.stroke(
            path, with: .color(color.opacity(0.75 * sin(Double.pi * t))),
            style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

/// Las dos bandas de titanio: una horizontal y una diagonal, las dos por el centro de la marca. Primero se traza una
/// línea fina; después se ensancha y se apaga.
private func drawLaunchBands(_ frame: LaunchFrame, center: CGPoint, in context: GraphicsContext, size: CGSize) {
    guard frame.bandDraw.count == 2, frame.bandWiden.count == 2 else { return }
    let gradient = Gradient(colors: [Color(hex: "#F3F4F6"), Color(hex: "#9DA2AA"), Color(hex: "#3A3B3F")])
    let starts = [CGPoint(x: center.x - 700, y: center.y), CGPoint(x: center.x - 560, y: center.y + 560)]
    let ends = [CGPoint(x: center.x + 700, y: center.y), CGPoint(x: center.x + 560, y: center.y - 560)]
    for band in 0..<2 {
        let drawn = CGFloat(frame.bandDraw[band])
        let widen = frame.bandWiden[band]
        guard drawn > 0, widen < 1 else { continue }
        let from = starts[band]
        let to = ends[band]
        var path = Path()
        path.move(to: from)
        path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * drawn, y: from.y + (to.y - from.y) * drawn))
        var layer = context
        // Retoque 2: las bandas solo se ven sobre el negro ENTERO (nunca por encima de la tarjeta ni del título de Inicio
        // que se enciende debajo) y, al ensancharse, como mucho a 0,35. Ronda 1 (I-2): multiplicar por el negro aún las
        // dejaba ver sobre la tarjeta a medio encender; ahora se apagan del todo antes de que el negro baje de 0,85.
        layer.opacity = min(0.75 * pow(1 - widen, 1.6), widen > 0 ? 0.35 : 0.75) * launchBandVisibility(black: frame.black)
        layer.stroke(
            path,
            with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
            style: StrokeStyle(lineWidth: CGFloat(1 + 120 * widen), lineCap: .butt))
    }
}

/// Cuánto se ven las bandas según el negro que tienen debajo: enteras con el negro entero y nada en cuanto el negro baja
/// de 0,85 (debajo ya empieza a verse Inicio).
func launchBandVisibility(black: Double) -> Double {
    let k = min(1, max(0, (black - 0.85) / 0.15))
    return k * k * (3 - 2 * k)
}

/// Las dos mitades de la ola (la curva partida por su punto medio, 12–14): cada una viene de una esquina, girada, con
/// una estela fina tan larga como rápida va. Con `piece` = 1 están exactamente donde `AppMark` dibuja la ola.
private func drawLaunchHalves(
    _ frame: LaunchFrame, center: CGPoint, markSize: CGFloat, distanceScale: Double, in context: GraphicsContext
) {
    guard !frame.joined else { return }
    // Todo se mide en la caja de 120 de la marca, como en `AppMark`.
    let u = markSize / 120
    let origin = CGPoint(x: center.x - markSize / 2, y: center.y - markSize / 2)
    let wave = CGRect(x: origin.x + 21.6 * u, y: origin.y + 15.2 * u, width: 76.8 * u, height: 76.8 * u)
    let s = wave.width / 24
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: wave.minX + x * s, y: wave.minY + y * s) }
    let shading = GraphicsContext.Shading.linearGradient(
        MarkPalette.waveGradient,
        startPoint: CGPoint(
            x: wave.minX + MarkPalette.waveStart.x * wave.width, y: wave.minY + MarkPalette.waveStart.y * wave.height),
        endPoint: CGPoint(
            x: wave.minX + MarkPalette.waveEnd.x * wave.width, y: wave.minY + MarkPalette.waveEnd.y * wave.height))
    let remaining = CGFloat(1 - frame.piece)
    let trailColor = Color(hex: "#E9EBEE")
    let lineWidth: CGFloat = 1.9 * 3.2 * u
    for half in 0..<2 {
        var path = Path()
        let travel: CGSize
        let pivot: CGPoint
        if half == 0 {
            path.move(to: point(4, 16))
            path.addCurve(to: point(12, 14), control1: point(7, 10), control2: point(9, 10))
            travel = CGSize(width: -250, height: 290)
            pivot = CGPoint(x: origin.x + 47 * u, y: origin.y + 55 * u)
        } else {
            path.move(to: point(12, 14))
            path.addCurve(to: point(20, 12), control1: point(15, 18), control2: point(17, 18))
            travel = CGSize(width: 250, height: -290)
            pivot = CGPoint(x: origin.x + 73 * u, y: origin.y + 65 * u)
        }
        var layer = context
        layer.opacity = frame.pieceOpacity
        layer.translateBy(x: travel.width * remaining, y: travel.height * remaining)
        let speed = CGFloat(min(70, abs(frame.pieceSpeed) * 9) * distanceScale)
        let trail = speed * max(0, remaining) * u
        if trail > 0.5 {
            let distance = hypot(travel.width, travel.height)
            var line = Path()
            line.move(to: pivot)
            line.addLine(to: CGPoint(
                x: pivot.x + travel.width / distance * trail, y: pivot.y + travel.height / distance * trail))
            let opacity = Double(min(0.7, trail / 40))
            layer.stroke(line, with: .color(trailColor.opacity(opacity)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        let turn = (half == 0 ? -1.0 : 1.0) * 16 * distanceScale * Double(remaining)
        layer.translateBy(x: pivot.x, y: pivot.y)
        layer.rotate(by: .degrees(turn))
        layer.translateBy(x: -pivot.x, y: -pivot.y)
        layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

extension View {
    /// Solo DEBUG y solo en la demo: un elemento invisible de 1 pt que las pruebas de toque leen para saber qué capa del
    /// arranque está montada y en qué estado. En Release no hace nada.
    @ViewBuilder func launchProbe(_ identifier: String, value: String) -> some View {
        #if DEBUG
        if DemoMode.isActive {
            background(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier(identifier)
                    .accessibilityValue(value)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
