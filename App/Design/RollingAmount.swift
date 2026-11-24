import SwiftUI
import MiBancoCore
#if DEBUG
import Synchronization
#endif

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

    /// Opcional: sin preferencias (una vista previa, una hoja o ventana que no las recibe) no se cierra la app, y el ojo
    /// se lee de lo guardado y se observa en vivo: si el dueño lo cierra desde otro sitio, este importe se oculta al
    /// momento. En una extensión `UserDefaults.standard` es el de la extensión (el ojo no está en un App Group), así que
    /// ahí no se sabe: quien dibuje un importe fuera de la app usa `RollingDigits` y le pasa `hidden` de una fuente real.
    @Environment(AppPreferences.self) private var preferences: AppPreferences?
    /// El ojo guardado (misma clave y mismo almacén que `AppPreferences`; en la demo, el suyo propio sembrado al arrancar).
    @AppStorage(AppPreferences.privateModeKey, store: AppPreferences.privateModeStore) private var storedPrivateMode = false
    @Environment(\.motion) private var motion
    @Environment(\.entrance) private var entrance

    var body: some View {
        RollingDigits(
            cents: cents, style: style, hidden: preferences?.privateMode ?? storedPrivateMode, countsUp: countsUp,
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
/// - Toda decisión sobre qué se dibuja (cifra real, barajado o puntos, y a qué importe rodar) la toma `AmountReveal`
///   (Core, con pruebas); esta vista solo guarda los temporizadores y dibuja.
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
        _reveal = State(initialValue: AmountReveal(cents: cents, hidden: hidden))
        _popped = State(initialValue: hidden ? Self.dotCount : 0)
    }

    /// Los 5 puntos de «•••,••».
    private static let dotCount = 5

    @State private var value: Int?
    @State private var plan: [DigitColumn] = []
    @State private var planStart = Date.distantPast
    @State private var planID = 0
    @State private var rolling = false
    /// Qué se dibuja (cifra real, barajado o puntos) y a qué importe: lo decide `AmountReveal`.
    @State private var reveal: AmountReveal
    /// Paso del barajado (1…6) y cuántos puntos han salido ya (el pequeño salto de cada punto).
    @State private var scrambleStep = 0
    @State private var popped: Int
    @State private var transition: Task<Void, Never>?
    @State private var seed = Int.random(in: 1...1_000_000)
    @ScaledMetric(relativeTo: .largeTitle) private var heroScale = 1.0

    // MARK: Cuerpo

    var body: some View {
        fitted(content)
            // Con Reducir movimiento, cerrar el ojo se funde solo, lo anime o no quien llama.
            .modifier(ReduceFade(reduce: motion.reduce, fade: motion.fade, value: drawnNow))
            // Antes de empezar a contar (tarjeta vecina aún sin ver) no se enseña un 0 falso.
            .opacity(value == nil && drawnNow == .real && !hidden && countsUp && !motion.reduce ? 0 : 1)
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenAmount(cents, hidden: hidden))
            .onAppear(perform: start)
            .task(id: planID) { await finishRoll() }
            .onChange(of: hidden) { _, nowHidden in
                transition?.cancel()
                perform(reveal.apply(.eyeChanged(hidden: nowHidden), reduceMotion: motion.reduce))
            }
            .onChange(of: revealed) { _, _ in if value == nil { start() } }
            .onChange(of: restartToken) { _, _ in recount() }
            .onChange(of: cents) { _, new in perform(reveal.apply(.valueChanged(new), reduceMotion: motion.reduce)) }
    }

    /// Lo que se dibuja ahora. Si `hidden` ya es true pero `reveal` aún enseña cifras (el primer fotograma tras tocar
    /// el ojo), `AmountReveal` lo cubre: una cifra real no se dibuja nunca con el modo privado puesto.
    private var drawnNow: AmountReveal.Drawn { reveal.displayed(hiddenInput: hidden, reduceMotion: motion.reduce) }

    @ViewBuilder private var content: some View {
        switch drawnNow {
        case .real:
            // Los glifos se calculan una vez, fuera del cierre que se ejecuta en cada fotograma.
            let figures = glyphs(of: shownValue)
            ZStack {
                TimelineView(.animation(paused: !rolling)) { context in
                    let t = rolling ? context.date.timeIntervalSince(planStart) : Double.infinity
                    let _ = censusFrame()
                    row(figures, at: t)
                }
                .census(.face)
                .id(motion.reduce ? shownValue : 0)
                .transition(.opacity)
            }
            // Al cerrar el ojo las cifras se quitan al instante, aunque quien llama (o `ReduceFade`) anime el cambio:
            // nunca se funden encima de la máscara (K23). Al abrirlo sí aparecen fundiéndose.
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
        case .scramble:
            row(maskGlyphs(scrambleStep: scrambleStep), at: .infinity, blurAll: motion.richEffects ? 0.5 : 0)
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

    /// La tipografía propia del estilo; `.plain` no tiene (nil): dibuja con la del sitio donde se coloca.
    private func font(_ small: Bool) -> Font? {
        switch style {
        case .plain: nil
        case .hero: .system(size: baseSize(small), weight: .semibold)
        }
    }

    /// Cuerpo del texto de una parte del protagonista; crece con el tamaño de texto (hasta 1,35 y luego se encoge para caber).
    private func baseSize(_ small: Bool) -> CGFloat {
        guard case let .hero(euros, cents, _) = style else { return 0 }
        return (small ? cents : euros) * min(heroScale, 1.35)
    }

    /// Solo los céntimos de la cifra protagonista traen su color; lo demás (nil) se dibuja con el del sitio donde se
    /// coloca (el verde de un ingreso, etc.): `.foregroundStyle(.foreground)` no hereda, pisa el del llamante.
    private func glyphStyle(_ small: Bool) -> AnyShapeStyle? {
        if small, case .hero(_, _, let c) = style { return AnyShapeStyle(c) }
        return nil
    }

    private func blurRadius(_ small: Bool) -> CGFloat {
        switch style {
        case .plain: 1
        case .hero: baseSize(small) * 0.055
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
        let usesPlan = !plan.isEmpty && plan.count == digitTotal && drawnNow == .real
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(glyphs) { g in
                if let d = g.digit {
                    let still = g.fixed ?? Double(String(g.char)) ?? 0
                    let pos = usesPlan ? DigitRoll.position(plan[d], at: t, overshoot: overshoot) : still
                    let speed = usesPlan && motion.richEffects ? DigitRoll.speed(plan[d], at: t, overshoot: overshoot) : 0
                    DigitCell(position: pos, blur: max(blurAll, min(1, speed / 16) * 0.85), blurRadius: blurRadius(g.small))
                        .cellFont(font(g.small))
                        .cellStyle(glyphStyle(g.small))
                } else if let dot = g.dot {
                    // La máscara es el «•» de la propia tipografía, en la fuente de su celda (grande en euros, pequeña
                    // en céntimos), con el avance del propio glifo.
                    BulletCell(visible: dotVisible(dot))
                        .cellFont(font(g.small))
                        .cellStyle(glyphStyle(g.small))
                } else {
                    Text(String(g.char))
                        .accessibilityLabel(cellLabel(g.char))
                        .cellFont(font(g.small))
                        .cellStyle(glyphStyle(g.small))
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .modifier(HeroTracking(euros: heroEuros))
    }

    /// La etiqueta de una celda de texto suelta («€», la coma, el signo). VoiceOver no las lee (el importe entero es UN
    /// elemento con su etiqueta), pero las pruebas de toque ven cada texto por separado: con el ojo cerrado ninguna
    /// celda dice «€» (las pantallas comprueban que en modo privado no queda ni un «€» a la vista de las pruebas).
    private func cellLabel(_ char: Character) -> String {
        hidden ? "importe oculto" : String(char)
    }

    private func dotVisible(_ index: Int) -> Bool {
        reveal.drawn == .dots ? index < popped : true
    }

    /// Si no cabe, el importe se encoge entero, nunca celda a celda, y UNA sola vez: escala exacta = min(1, ancho ofrecido /
    /// ancho natural), calculada por la maquetación (`FitBox`) con una sola cara viva (K22; antes, una escalera de 11
    /// copias en `ViewThatFits`). Lo que ocupa es lo que se ve: la caja mide natural × escala y la cara se dibuja con esa
    /// misma escala (la lee de la caja con `visualEffect`, en el mismo fotograma, sin `@State` ni medidas a destiempo).
    /// - El hueco: la cara va sobre una copia oculta del importe real con cada cifra cambiada por «0» (`slotGlyphs`). El
    ///   ancho natural es el mayor de los dos, así que la máscara ocupa el mismo hueco, con la misma escala, que las cifras
    ///   a las que sustituye (K23) y el importe no cambia de tamaño mientras cuenta.
    /// - El protagonista ocupa todo el ancho y se encoge hacia la izquierda.
    /// - Una línea (`.plain`) nunca pasa del ancho que se le ofrece. Cuánto se le ofrece en una fila lo decide
    ///   `AmountRowLayout` (el título hasta su ancho ideal; el importe a tamaño completo si cabe y, si no, hasta la mitad).
    @ViewBuilder private func fitted<V: View>(_ face: V) -> some View {
        let box = FitBox {
            ZStack(alignment: heroEuros != nil ? .leading : .trailing) {
                // Copia de medida: solo texto, sin `TimelineView` ni temporizadores; no hace nada por fotograma.
                slotRow(slotGlyphs).census(.slot).hidden()
                face
            }
            .fixedSize()
            // El área de toque es la caja (abajo, `contentShape`), no el dibujo.
            .allowsHitTesting(false)
            .visualEffect { content, proxy in
                content.scaleEffect(fitScale(in: proxy), anchor: .topLeading)
            }
        }
        .coordinateSpace(.named(fitSpace))
        .contentShape(Rectangle())
        if heroEuros != nil {
            box.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            box
        }
    }

    /// El hueco del importe real (`cents`) con cada cifra cambiada por «0»: mide lo mismo que las celdas de las cifras
    /// (cada una es un «0» oculto) sin decir cuáles son. Lo mismo para la máscara (que no tiene cifras).
    private var slotGlyphs: [Glyph] {
        let parts = texts(of: cents)
        func zeroed(_ text: String) -> String {
            String(text.map { $0.isASCII && $0.isNumber ? "0" : $0 })
        }
        return build(main: zeroed(parts.main), small: zeroed(parts.small), random: nil)
    }

    /// Una fila de solo texto con las mismas celdas, tipografías y espaciado que `row`, para medir (siempre oculta).
    private func slotRow(_ glyphs: [Glyph]) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(glyphs) { g in
                Text(String(g.char)).accessibilityLabel(cellLabel(g.char)).cellFont(font(g.small))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .modifier(HeroTracking(euros: heroEuros))
        .accessibilityHidden(true)
    }

    // MARK: Estados

    private func digitCount(_ value: Int) -> Int { max(3, String(abs(value)).count) }

    private func start() {
        // Oculto desde el principio: no hay nada que contar; al mostrar, el barajado del ojo rueda hasta la cifra real.
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

    /// Hace lo que `AmountReveal` ha decidido. Aquí no se decide nada: solo se mueven los dígitos y los temporizadores.
    private func perform(_ action: AmountReveal.Action) {
        switch action {
        case .none:
            break
        case .rollTo(let target):
            // Un importe que llega antes de estrenarse (aún sin cuenta) empieza su cuenta.
            if let old = value { roll(to: target, from: old, positions: currentPositions()) } else { start() }
        case .crossFadeTo(let target):
            withAnimation(motion.fade) {
                value = target
                plan = []
                rolling = false
            }
        case .startScramble(let generation):
            startScramble(generation)
        case .showDots:
            rolling = false
            withAnimation(motion.fade) { popped = Self.dotCount }
        }
    }

    /// El ojo: se baraja 240 ms con dígitos propios y los puntos aparecen (o, al mostrar, rueda hasta la cifra real).
    /// Al acabar, `AmountReveal` dice qué toca; un aviso de un barajado ya cancelado no hace nada (generación vieja).
    private func startScramble(_ generation: Int) {
        scrambleStep = 0
        popped = 0
        transition = Task { @MainActor in
            for step in 1...6 {
                scrambleStep = step
                try? await Task.sleep(for: .milliseconds(40))
                if Task.isCancelled { return }
            }
            switch reveal.apply(.scrambleEnded(generation: generation), reduceMotion: motion.reduce) {
            case .showDots:
                rolling = false
                for count in 1...Self.dotCount {
                    withAnimation(motion.animation(.snap)) { popped = count }
                    try? await Task.sleep(for: .milliseconds(16))
                    if Task.isCancelled { return }
                }
            case .rollTo(let target):
                let random = AmountMask.scrambledDigits(count: Self.dotCount, step: 6, seed: seed)
                let from = random.reduce(0) { $0 * 10 + $1 }
                roll(to: target, from: from, positions: random.map(Double.init), base: 0.38, perColumn: 0.03, stagger: 0.014)
            default:
                break
            }
        }
    }
}

/// La caja de un importe: mide lo natural de su hijo × escala, con escala = min(1, ancho ofrecido / ancho natural)
/// (nunca más ancha que lo ofrecido: no se sale de la fila). Coloca al hijo a su tamaño natural en su esquina; el hijo
/// se dibuja escalado con `fitScale(in:)`, que lee esta misma caja (`fitSpace`). Las líneas de base se escalan igual,
/// para que una fila alineada por la base siga alineada.
private struct FitBox: Layout {
    static func scale(natural: CGFloat, offered: CGFloat?) -> CGFloat {
        guard let offered, offered.isFinite, natural > 0 else { return 1 }
        return max(0, min(1, offered / natural))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(.unspecified)
        let s = Self.scale(natural: natural.width, offered: proposal.width)
        return CGSize(width: natural.width * s, height: natural.height * s)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(child.sizeThatFits(.unspecified)))
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        guard let child = subviews.first else { return nil }
        let natural = child.sizeThatFits(.unspecified)
        let s = natural.width > 0 ? bounds.width / natural.width : 1
        return bounds.minY + child.dimensions(in: .unspecified)[guide] * s
    }
}

/// El espacio de coordenadas de cada `FitBox` (el más cercano gana: cada importe lee el suyo).
private let fitSpace = "RollingAmount.fit"

/// La escala con que se dibuja el hijo de una `FitBox`: ancho de la caja / ancho natural del hijo. En `visualEffect`
/// (fuera del actor principal), así que es una función libre.
private func fitScale(in proxy: GeometryProxy) -> CGFloat {
    let natural = proxy.size.width
    guard natural > 0, let box = proxy.bounds(of: .named(fitSpace)) else { return 1 }
    return max(0, min(1, box.width / natural))
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
/// La tira se pinta en un `Canvas` del tamaño de la celda (solo las cifras que asoman), no como 11 vistas desplazadas:
/// la geometría de esas vistas, aunque recortada, hacía el marco del importe (VoiceOver, toques) de hasta 16 líneas.
private struct DigitCell: View {
    let position: Double
    let blur: Double
    let blurRadius: CGFloat

    var body: some View {
        let f = position.truncatingRemainder(dividingBy: 10)
        let place = f < 0 ? f + 10 : f
        let blur = blur
        let blurRadius = blurRadius
        Text("0")
            .hidden()
            .overlay {
                Canvas { context, size in
                    // La línea k de la tira dice k mod 10 y está a (k − place) líneas de la celda.
                    func strip(_ layer: GraphicsContext) {
                        let line = size.height
                        for k in 0...10 {
                            let y = (CGFloat(k) - CGFloat(place)) * line
                            guard y > -line, y < line else { continue }
                            var digit = layer.resolve(Text(String(k % 10)))
                            // El color de quien coloca el importe (B-1), como en las demás celdas.
                            digit.shading = .foreground
                            layer.draw(digit, at: CGPoint(x: size.width / 2, y: y + line / 2), anchor: .center)
                        }
                    }
                    var sharp = context
                    sharp.opacity = 1 - blur * 0.7
                    strip(sharp)
                    if blur > 0.001 {
                        context.drawLayer { layer in
                            layer.addFilter(.blur(radius: blurRadius))
                            layer.opacity = blur
                            strip(layer)
                        }
                    }
                }
            }
            .clipped()
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.13),
                            .init(color: .black, location: 0.87), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
    }
}

/// Un punto de la máscara: el «•» de la propia tipografía, con su avance, en la fuente que le ponga la celda. Aparece
/// con un pequeño salto; ocupa su sitio desde el principio para que la cifra no se mueva mientras salen.
private struct BulletCell: View {
    let visible: Bool

    var body: some View {
        Text("•")
            // Solo para las pruebas de toque (VoiceOver lee el importe entero como un elemento): ni «•» ni «€».
            .accessibilityLabel("importe oculto")
            .scaleEffect(visible ? 1 : 0.3)
            .opacity(visible ? 1 : 0)
    }
}

/// `.font(nil)` y `.foregroundStyle(.foreground)` no significan «hereda»: la tipografía y el color solo se aplican si
/// el estilo trae uno propio.
private extension View {
    @ViewBuilder func cellFont(_ font: Font?) -> some View {
        if let font { self.font(font) } else { self }
    }

    @ViewBuilder func cellStyle(_ style: AnyShapeStyle?) -> some View {
        if let style { self.foregroundStyle(style) } else { self }
    }
}

#if DEBUG
/// Solo DEBUG: lo que hay montado de cada importe, para que la galería compruebe que cada uno monta UNA cara con cifras
/// reales (con su `TimelineView`), UNA copia de medida (solo texto, oculta) y que en reposo ninguna dibuja fotogramas
/// (K22). Se cuenta con `onAppear`/`onDisappear` de cada identidad montada. Antes cada cara guardaba una ficha en su
/// `@State`, pero el valor inicial de `@State` se crea en CADA `init` y SwiftUI se queda con la última vista, así que una
/// cara redibujada al menos una vez contaba dos fichas (18 para 9 importes).
enum RollingAmountCensus {
    fileprivate static let faces = Atomic<Int>(0)
    fileprivate static let slots = Atomic<Int>(0)
    fileprivate static let frames = Atomic<Int>(0)
    /// Caras con cifras reales montadas ahora (cada una con su `TimelineView`).
    static var liveFaces: Int { faces.load(ordering: .relaxed) }
    /// Copias de medida montadas ahora (texto oculto, sin `TimelineView`).
    static var measuringSlots: Int { slots.load(ordering: .relaxed) }
    /// Fotogramas dibujados por todas las caras desde el arranque.
    static var faceFrames: Int { frames.load(ordering: .relaxed) }
}
#endif

private enum CensusEntry { case face, slot }

private extension View {
    /// Solo DEBUG: apunta esta vista en `RollingAmountCensus` mientras está montada; en Release no hace nada.
    @ViewBuilder func census(_ entry: CensusEntry) -> some View {
        #if DEBUG
        // `Atomic` no se copia: cada rama usa el suyo directamente.
        onAppear {
            switch entry {
            case .face: _ = RollingAmountCensus.faces.add(1, ordering: .relaxed)
            case .slot: _ = RollingAmountCensus.slots.add(1, ordering: .relaxed)
            }
        }
        .onDisappear {
            switch entry {
            case .face: _ = RollingAmountCensus.faces.subtract(1, ordering: .relaxed)
            case .slot: _ = RollingAmountCensus.slots.subtract(1, ordering: .relaxed)
            }
        }
        #else
        self
        #endif
    }
}

/// Solo DEBUG: cuenta un fotograma de la `TimelineView` de una cara; en Release no hace nada.
private func censusFrame() {
    #if DEBUG
    _ = RollingAmountCensus.frames.add(1, ordering: .relaxed)
    #endif
}

/// Con Reducir movimiento, el cambio de lo que se dibuja (cifra ↔ puntos) se funde por sí solo. Sin `if/else` (cambiar
/// Reducir movimiento no rehace el importe entero) y sin `.animation(nil)` (sin Reducir, la animación de quien llama
/// sigue intacta).
private struct ReduceFade: ViewModifier {
    let reduce: Bool
    let fade: Animation
    let value: AmountReveal.Drawn

    func body(content: Content) -> some View {
        content.transaction(value: value) { transaction in
            if reduce { transaction.animation = fade }
        }
    }
}
