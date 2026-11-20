import SwiftUI
import MiBancoCore

/// «•••,•• €» (con «−» o «+» delante según el signo y `sign`). No depende de las cifras del importe, solo de su signo.
func maskedEUR(_ cents: Int, sign: Bool) -> String {
    AmountMask.text(negative: cents < 0, showsPlus: sign && cents >= 0)
}

/// Cómo se dibuja un importe: en una línea («1.284,55 €», con signo si `sign`) o como cifra protagonista
/// (euros grandes y «,75 €» pequeños en otro color).
enum AmountStyle: Equatable {
    case plain(sign: Bool)
    case hero(euros: CGFloat, cents: CGFloat, centsColor: Color)
}

/// Un importe que rueda como un cuentakilómetros. Lee el modo privado, el movimiento y la entrada por capas del
/// entorno y se lo pasa a `RollingDigits`, que es quien dibuja.
struct RollingAmount: View {
    let cents: Int
    /// true = empieza en 0 y cuenta hasta `cents` cuando `revealed` pasa a true.
    var countsUp = true
    /// Para cifras fuera de la vista (la tarjeta aún no visible): cuenta cuando aparece.
    var revealed = true
    var style: AmountStyle = .plain(sign: false)

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @Environment(\.entrance) private var entrance

    var body: some View {
        RollingDigits(
            cents: cents, style: style, hidden: preferences.privateMode, countsUp: countsUp,
            revealed: revealed, motion: motion,
            restartToken: entrance.token, restartsOnToken: entrance.active && entrance.scope == .assembly)
    }
}

/// El dibujo del importe, sin depender del entorno de la app (lo usará también la notificación ampliada).
/// - Cada dígito es una columna de «0…9,0» recortada a una línea, desplazada con `offset` (`DigitRoll.position`), con un
///   degradado del 13 % arriba y abajo y una copia ya desenfocada cuya opacidad sigue a la velocidad (nunca un
///   desenfoque animado). Una sola `TimelineView` por importe, en pausa cuando nada rueda.
/// - Con `hidden`, nunca se dibuja una cifra real: solo «•••,•• €», o dígitos al azar que no salen del importe mientras el
///   ojo cambia (6 × 40 ms), y los puntos aparecen con 16 ms entre ellos. Al mostrar, se baraja y rueda a la cifra real en
///   0,38 s. VoiceOver lee `spokenAmount`.
/// - Con Reducir movimiento no hay giro ni barajado: la cifra se funde.
struct RollingDigits: View {
    let cents: Int
    let style: AmountStyle
    let hidden: Bool
    var countsUp: Bool
    var revealed: Bool
    var motion: MotionContext
    /// Cambia cuando Inicio se vuelve a montar por capas; si `restartsOnToken`, la cifra vuelve a contar desde 0.
    var restartToken: Int
    var restartsOnToken: Bool

    init(
        cents: Int, style: AmountStyle, hidden: Bool, countsUp: Bool = true, revealed: Bool = true,
        motion: MotionContext = MotionContext(), restartToken: Int = 0, restartsOnToken: Bool = false
    ) {
        self.cents = cents
        self.style = style
        self.hidden = hidden
        self.countsUp = countsUp
        self.revealed = revealed
        self.motion = motion
        self.restartToken = restartToken
        self.restartsOnToken = restartsOnToken
        // Con el modo privado puesto desde el principio, el primer fotograma ya son puntos (nunca cifras).
        _mode = State(initialValue: hidden ? .dots(Self.dotCount) : .real)
    }

    private enum Mode: Equatable {
        case real
        case scramble(Int)
        case dots(Int)
    }

    /// Los 5 puntos de «•••,••».
    private static let dotCount = 5

    @State private var value: Int?
    @State private var plan: [DigitColumn] = []
    @State private var planStart = Date.distantPast
    @State private var planID = 0
    @State private var rolling = false
    @State private var mode: Mode
    @State private var transition: Task<Void, Never>?
    @State private var seed = Int.random(in: 1...1_000_000)
    @State private var idealWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    // MARK: Cuerpo

    var body: some View {
        fitted(content)
            // Antes de empezar a contar (tarjeta vecina aún sin ver) no se enseña un 0 falso.
            .opacity(value == nil && mode == .real && !hidden && countsUp && !motion.reduce ? 0 : 1)
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenAmount(cents, hidden: hidden))
            .onAppear(perform: start)
            .task(id: planID) { await finishRoll() }
            .onChange(of: hidden) { _, nowHidden in toggle(hidden: nowHidden) }
            .onChange(of: revealed) { _, _ in if value == nil { start() } }
            .onChange(of: restartToken) { _, _ in recount() }
            .onChange(of: cents) { _, new in changed(to: new) }
    }

    /// Lo que se dibuja ahora. Si `hidden` ya es true pero el estado aún enseña cifras (el primer fotograma tras tocar
    /// el ojo), se dibujan dígitos al azar: una cifra real no se dibuja nunca con el modo privado puesto.
    private var effectiveMode: Mode {
        if hidden, mode == .real { return .scramble(0) }
        return mode
    }

    @ViewBuilder private var content: some View {
        switch effectiveMode {
        case .real:
            ZStack {
                TimelineView(.animation(paused: !rolling)) { context in
                    let t = rolling ? context.date.timeIntervalSince(planStart) : Double.infinity
                    row(glyphs(of: shownValue), at: t)
                }
                .id(motion.reduce ? shownValue : 0)
                .transition(.opacity)
            }
        case .scramble(let step):
            row(maskGlyphs(scrambleStep: step), at: .infinity, blurAll: motion.richEffects ? 0.5 : 0)
        case .dots:
            row(maskGlyphs(), at: .infinity)
        }
    }

    /// El valor que dibuja el modo `.real` (solo se lee con el modo privado apagado).
    private var shownValue: Int { value ?? (countsUp && !motion.reduce ? 0 : cents) }

    // MARK: Glifos

    private struct Glyph: Identifiable {
        let id: Int
        let char: Character
        let small: Bool
        /// Índice de la columna (de izquierda a derecha) si es un dígito.
        let digit: Int?
        /// Posición fija de la tira (dígito al azar del barajado); nil = la de la rodada.
        let fixed: Double?
        /// Orden del punto entre los puntos de la máscara, si lo es.
        let dot: Int?
    }

    private func texts(of value: Int) -> (main: String, small: String) {
        switch style {
        case .plain(let sign):
            (sign ? signedEUR(value) : formatEUR(value).replacingOccurrences(of: "-", with: "−"), "")
        case .hero:
            splitEUR(value)
        }
    }

    private func glyphs(of value: Int) -> [Glyph] {
        let parts = texts(of: value)
        return build(main: parts.main, small: parts.small, random: nil)
    }

    /// Máscara «•••,•• €» (solo depende del signo). Con `scrambleStep`, cada punto es un dígito al azar.
    private func maskGlyphs(scrambleStep: Int? = nil) -> [Glyph] {
        var sign = false
        if case .plain(let s) = style { sign = s }
        let text = maskedEUR(cents, sign: sign)
        var main = text
        var small = ""
        if case .hero = style, let i = text.lastIndex(of: ",") {
            main = String(text[..<i])
            small = String(text[i...])
        }
        let random = scrambleStep.map { AmountMask.scrambledDigits(count: Self.dotCount, step: $0, seed: seed) }
        return build(main: main, small: small, random: random)
    }

    private func build(main: String, small: String, random: [Int]?) -> [Glyph] {
        var out: [Glyph] = []
        var digit = 0
        var dot = 0
        func add(_ text: String, isSmall: Bool) {
            for ch in text {
                let id = out.count
                if ch == "•" {
                    if let random {
                        let value = Double(random[min(dot, random.count - 1)])
                        out.append(Glyph(id: id, char: ch, small: isSmall, digit: digit, fixed: value, dot: nil))
                        digit += 1
                    } else {
                        out.append(Glyph(id: id, char: ch, small: isSmall, digit: nil, fixed: nil, dot: dot))
                    }
                    dot += 1
                } else if ch.isASCII, ch.isNumber {
                    out.append(Glyph(id: id, char: ch, small: isSmall, digit: digit, fixed: nil, dot: nil))
                    digit += 1
                } else {
                    out.append(Glyph(id: id, char: ch, small: isSmall, digit: nil, fixed: nil, dot: nil))
                }
            }
        }
        add(main, isSmall: false)
        add(small, isSmall: true)
        return out
    }

    // MARK: Fila

    private func font(_ small: Bool) -> Font? {
        switch style {
        case .plain: nil
        case let .hero(euros, cents, _): .system(size: small ? cents : euros, weight: .semibold)
        }
    }

    /// Solo la cifra protagonista cambia el color; en una línea simple se hereda del entorno (verde de un ingreso, etc.).
    private func glyphStyle(_ small: Bool) -> AnyShapeStyle {
        if small, case .hero(_, _, let c) = style { return AnyShapeStyle(c) }
        return AnyShapeStyle(.foreground)
    }

    private func blurRadius(_ small: Bool) -> CGFloat {
        switch style {
        case .plain: 1
        case let .hero(euros, cents, _): (small ? cents : euros) * 0.055
        }
    }

    private var overshoot: Double { 0.17 * motion.level.bounceScale }

    private var heroEuros: CGFloat? {
        if case .hero(let e, _, _) = style { return e }
        return nil
    }

    /// `t` = segundos desde que empezó la rodada (`.infinity` = asentado). `blurAll` fuerza una copia desenfocada fija
    /// (el barajado del ojo).
    private func row(_ glyphs: [Glyph], at t: Double, blurAll: Double = 0) -> some View {
        let digitTotal = glyphs.compactMap(\.digit).count
        let usesPlan = !plan.isEmpty && plan.count == digitTotal && effectiveMode == .real
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(glyphs) { g in
                if let d = g.digit {
                    let still = g.fixed ?? Double(String(g.char)) ?? 0
                    let pos = usesPlan ? DigitRoll.position(plan[d], at: t, overshoot: overshoot) : still
                    let speed = usesPlan && motion.richEffects ? DigitRoll.speed(plan[d], at: t, overshoot: overshoot) : 0
                    DigitCell(position: pos, blur: max(blurAll, min(1, speed / 16) * 0.85), blurRadius: blurRadius(g.small))
                        .font(font(g.small))
                        .foregroundStyle(glyphStyle(g.small))
                } else if let dot = g.dot {
                    Text(String(g.char))
                        .font(font(g.small))
                        .foregroundStyle(glyphStyle(g.small))
                        .scaleEffect(dotVisible(dot) ? 1 : 0.3)
                        .opacity(dotVisible(dot) ? 1 : 0)
                } else {
                    Text(String(g.char))
                        .font(font(g.small))
                        .foregroundStyle(glyphStyle(g.small))
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .modifier(HeroTracking(euros: heroEuros))
    }

    private func dotVisible(_ index: Int) -> Bool {
        if case .dots(let popped) = effectiveMode { return index < popped }
        return true
    }

    /// Los importes protagonistas se encogen hasta un 60 % si no caben (como `minimumScaleFactor(0.6)`).
    @ViewBuilder private func fitted<V: View>(_ view: V) -> some View {
        if heroEuros != nil {
            view
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { idealWidth = $0 }
                .scaleEffect(fitScale, anchor: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        } else {
            view.fixedSize()
        }
    }

    private var fitScale: CGFloat {
        guard idealWidth > 0, availableWidth > 0 else { return 1 }
        return min(1, max(0.6, availableWidth / idealWidth))
    }

    // MARK: Estados

    private func digitCount(_ value: Int) -> Int { max(3, String(abs(value)).count) }

    private func start() {
        // Oculto desde el principio: no hay nada que contar; al mostrar, `toggle` rueda hasta la cifra real.
        guard !hidden, value == nil, revealed else { return }
        if countsUp, !motion.reduce {
            value = 0
            roll(to: cents, from: 0, positions: nil)
        } else {
            value = cents
        }
    }

    /// Dos pasos: primero 0 (la capa aún está oculta) y, tras 0,15 s, la cuenta (como `CountingAmount`).
    private func recount() {
        guard restartsOnToken, countsUp, revealed, !hidden, !motion.reduce else { return }
        value = 0
        plan = []
        roll(to: cents, from: 0, positions: nil, delay: 0.15)
    }

    private func changed(to new: Int) {
        // Con el modo privado puesto no se toca nada visible: al mostrar, se rueda hasta la cifra de entonces.
        guard !hidden, mode == .real else { return }
        guard let old = value else { return start() }
        if motion.reduce {
            withAnimation(motion.fade) {
                value = new
                plan = []
            }
        } else {
            roll(to: new, from: old, positions: currentPositions())
        }
    }

    /// Dónde está ahora cada tira (con decimales si va rodando), para seguir desde ahí.
    private func currentPositions() -> [Double]? {
        guard !plan.isEmpty else { return nil }
        let t = rolling ? Date().timeIntervalSince(planStart) : Double.infinity
        return plan.map { DigitRoll.position($0, at: t, overshoot: overshoot) }
    }

    private func roll(
        to new: Int, from old: Int, positions: [Double]?, delay: Double = 0,
        base: Double = 0.56, perColumn: Double = 0.038, stagger: Double = 0.022
    ) {
        let n = digitCount(new)
        var aligned: [Double]?
        if let positions {
            // Alineado a la derecha: las columnas nuevas de la izquierda empiezan en 0.
            aligned = Array(repeating: 0, count: max(0, n - positions.count)) + Array(positions.suffix(n))
        }
        plan = DigitRoll.columns(
            from: old, to: new, digitCount: n, startingAt: aligned,
            base: motion.seconds(base), perColumn: motion.seconds(perColumn), stagger: motion.seconds(stagger))
        value = new
        planStart = Date().addingTimeInterval(delay)
        rolling = true
        planID += 1
    }

    private func finishRoll() async {
        guard rolling else { return }
        let end = plan.map { $0.delay + $0.duration }.max() ?? 0
        let wait = max(0, planStart.timeIntervalSinceNow) + end + 0.05
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        rolling = false
    }

    /// El ojo: se baraja 240 ms con dígitos propios y los puntos aparecen (o, al mostrar, rueda hasta la cifra real).
    private func toggle(hidden nowHidden: Bool) {
        transition?.cancel()
        if motion.reduce {
            withAnimation(motion.fade) {
                if nowHidden {
                    mode = .dots(Self.dotCount)
                } else {
                    mode = .real
                    value = cents
                    plan = []
                    rolling = false
                }
            }
            return
        }
        transition = Task { @MainActor in
            for step in 1...6 {
                mode = .scramble(step)
                try? await Task.sleep(for: .milliseconds(40))
                if Task.isCancelled { return }
            }
            if nowHidden {
                rolling = false
                for popped in 1...Self.dotCount {
                    withAnimation(motion.animation(.snap)) { mode = .dots(popped) }
                    try? await Task.sleep(for: .milliseconds(16))
                    if Task.isCancelled { return }
                }
            } else {
                let random = AmountMask.scrambledDigits(count: Self.dotCount, step: 6, seed: seed)
                let from = random.reduce(0) { $0 * 10 + $1 }
                roll(to: cents, from: from, positions: random.map(Double.init), base: 0.38, perColumn: 0.03, stagger: 0.014)
                mode = .real
            }
        }
    }
}

/// `tracking` solo de la cifra protagonista (−3 % del cuerpo de los euros).
private struct HeroTracking: ViewModifier {
    let euros: CGFloat?

    @ViewBuilder func body(content: Content) -> some View {
        if let euros { content.tracking(-euros * 0.03) } else { content }
    }
}

/// Un dígito: tira «0…9,0» recortada a una línea y desplazada a `position`; una copia ya desenfocada cuya opacidad
/// (`blur`, 0…1) sigue a la velocidad. El desenfoque es fijo; lo único que cambia es el desplazamiento y la opacidad.
private struct DigitCell: View {
    let position: Double
    let blur: Double
    let blurRadius: CGFloat

    var body: some View {
        let f = position.truncatingRemainder(dividingBy: 10)
        let place = f < 0 ? f + 10 : f
        Text("0")
            .hidden()
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    strip.opacity(1 - blur * 0.7)
                    if blur > 0.001 {
                        strip.blur(radius: blurRadius).opacity(blur)
                    }
                }
                .visualEffect { content, proxy in
                    content.offset(y: -CGFloat(place) * proxy.size.height / 11)
                }
            }
            .clipped()
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.13),
                            .init(color: .black, location: 0.87), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
    }

    private var strip: some View {
        VStack(spacing: 0) {
            ForEach(0..<11, id: \.self) { Text(String($0 % 10)) }
        }
        .fixedSize()
    }
}
