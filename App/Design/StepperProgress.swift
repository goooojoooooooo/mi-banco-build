import SwiftUI
import MiBancoCore

/// Pasos de un proceso (Autorizar › Leer cuentas › Listo): nodos de 28 pt unidos por líneas que se rellenan.
/// El paso actual entra con un pequeño rebote, los hechos se rellenan de blanco con su ✓ dibujado y cada línea se
/// llena de izquierda a derecha (300 ms). `finished` da por hechos todos los pasos. Con Reducir movimiento todo cambia
/// con fundidos. Cada nodo es un elemento de accesibilidad con su estado.
/// Con tamaños de texto de accesibilidad los pasos pasan a una columna (nodo y título en una fila) para que los títulos
/// no se pisen ni se recorten; en horizontal, cada título cabe en el ancho de su paso y puede ocupar dos líneas.
///
/// Opcionales (por defecto, nada cambia):
/// - `caption`: una línea debajo que dice lo que se está haciendo; al cambiar se funde con una subida de 8 pt.
/// - `percent` + `since`: a la derecha de esa línea, el porcentaje (`StepPercent`, Core) contado desde `since`, el
///   instante en que empezó el paso en curso. Sigue el paso real: nunca alcanza el tope de un paso que no ha terminado.
/// - `spins`: un arco que gira alrededor del nodo en curso. Solo gira mientras hay un paso en marcha.
/// - `showsTitles = false`: solo los nodos y sus líneas (los títulos siguen en VoiceOver).
/// - `identifier`: para las pruebas; el porcentaje es `<identifier>-percent` y la línea, `<identifier>-caption`.
struct StepperProgress: View {
    let steps: [String]
    let current: Int
    let finished: Bool
    var caption: String? = nil
    var percent: StepPercent? = nil
    var since = Date.distantPast
    var spins = false
    var showsTitles = true
    var identifier: String? = nil

    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize

    private func phase(_ i: Int) -> StepNode.Phase {
        finished || i < current ? .done : (i == current ? .current : .pending)
    }

    private var transition: Animation {
        motion.reduce ? motion.fade : .easeInOut(duration: motion.seconds(0.3))
    }

    /// El arco gira solo en el nodo en curso y solo si el porcentaje (cuando lo hay) sigue en marcha.
    private func spinning(_ i: Int) -> Bool {
        spins && !finished && i == current && (percent?.isRunning ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(steps.indices, id: \.self) { i in
                            HStack(spacing: 12) {
                                StepNode(title: steps[i], number: i + 1, phase: phase(i), label: .beside, spinning: spinning(i))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(steps.indices, id: \.self) { i in
                            if i > 0 { link(filled: phase(i) != .pending).padding(.top, 13) }
                            StepNode(title: steps[i], number: i + 1, phase: phase(i), label: showsTitles ? .below : .none,
                                     spinning: spinning(i))
                        }
                    }
                }
            }
            if caption != nil || percent != nil { captionRow }
        }
        .animation(transition, value: current)
        .animation(transition, value: finished)
    }

    // MARK: Línea de estado y porcentaje

    private var captionRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            ZStack(alignment: .leading) {
                if let caption {
                    Text(caption)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(caption)
                        // En dos tiempos (ojo de diseño 14.4): la línea vieja se va en 0,1 s y solo entonces entra la nueva
                        // (0,15 s, subiendo 8 pt); nunca se leen las dos una encima de otra.
                        .transition(captionTransition)
                        .accessibilityIdentifier(identifier.map { "\($0)-caption" } ?? "")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(motion.calmAnimation(.enter), value: caption)
            if let percent {
                StepPercentText(percent: percent, since: since, stepNumber: min(current, steps.count - 1) + 1,
                                stepCount: steps.count, identifier: identifier.map { "\($0)-percent" } ?? "")
            }
        }
    }

    private var captionTransition: AnyTransition {
        let leave = motion.seconds(0.10)
        if motion.reduce {
            return .asymmetric(insertion: .opacity.animation(motion.fade.delay(leave)),
                               removal: .opacity.animation(.easeOut(duration: leave)))
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: motion.distance(8)))
                .animation(.easeOut(duration: motion.seconds(0.15)).delay(leave)),
            removal: .opacity.animation(.easeOut(duration: leave)))
    }

    private func link(filled: Bool) -> some View {
        Capsule()
            .fill(Color(hex: "#2E2E32"))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white)
                    // Con Reducir movimiento la línea no crece: se funde.
                    .scaleEffect(x: motion.reduce || filled ? 1 : 0, anchor: .leading)
                    .opacity(motion.reduce ? (filled ? 1 : 0) : 1)
            }
            .clipShape(Capsule())
            .padding(.horizontal, 6)
            .frame(minWidth: 16)
            .accessibilityHidden(true)
    }

    private struct StepNode: View {
        enum Phase { case pending, current, done }
        enum LabelPlace { case below, beside, none }
        let title: String
        let number: Int
        let phase: Phase
        let label: LabelPlace
        var spinning = false

        @Environment(\.motion) private var motion
        @State private var pop: CGFloat = 1

        var body: some View {
            Group {
                switch label {
                case .below:
                    VStack(spacing: 6) {
                        node
                        caption.multilineTextAlignment(.center).frame(width: 84)
                    }
                    // Los títulos no empujan las líneas: el nodo manda en el ancho y el título cabe en 84 pt.
                    .frame(width: 28, alignment: .top)
                case .beside:
                    HStack(spacing: 12) {
                        node
                        caption
                    }
                case .none:
                    node
                }
            }
            .onChange(of: phase) { _, new in
                guard !motion.reduce else { return }
                switch new {
                case .current:
                    pop = 0.7
                    withAnimation(.spring(response: motion.seconds(0.34), dampingFraction: 1 - min(0.62, 0.5 * motion.level.bounceScale))) {
                        pop = 1
                    }
                case .done:
                    // El relleno blanco entra con un bote (0,36 s), como en la maqueta.
                    pop = 0.72
                    withAnimation(.spring(response: motion.seconds(0.36), dampingFraction: 1 - min(0.62, 0.45 * motion.level.bounceScale))) {
                        pop = 1
                    }
                case .pending:
                    break
                }
            }
            .animation(motion.reduce ? motion.fade : .easeInOut(duration: motion.seconds(0.2)), value: phase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Paso \(number): \(title)")
            .accessibilityValue(phase == .done ? "hecho" : (phase == .current ? "en curso" : "pendiente"))
        }

        private var node: some View {
            ZStack {
                Circle().fill(phase == .done ? Color.white : Color(hex: "#141416"))
                Circle().strokeBorder(phase == .pending ? Color(hex: "#48484C") : Color.white,
                                      lineWidth: phase == .done ? 0 : 1.5)
                    .opacity(spinning ? 0.28 : 1)
                if spinning {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .transition(.opacity)
                }
                if phase == .done {
                    DrawnCheck(lineWidth: 3, color: .black)
                        .frame(width: 16, height: 16)
                }
                if spinning {
                    StepSpinner()
                        .transition(.opacity)
                }
            }
            .frame(width: 28, height: 28)
            .scaleEffect(pop)
        }

        private var caption: some View {
            Text(title)
                .titan(.caption)
                .foregroundStyle(phase == .pending ? Theme.label3 : Theme.label)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// El arco que gira alrededor del nodo en curso (un cuarto de vuelta de trazo, 420°/s como en la maqueta). La
/// `TimelineView` solo existe mientras el nodo está en curso (quien la monta la quita al terminar el paso) y, con
/// Reducir movimiento, el arco se queda quieto.
private struct StepSpinner: View {
    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    /// En la pantalla de un banco: con la hoja acoplada los pasos no se ven.
    @Environment(BankHeaderScroll.self) private var bankScroll: BankHeaderScroll?

    /// Se para con la app fuera de primer plano o con la hoja del banco tapando los pasos (menor m-1): una espera de
    /// minutos con la hoja arriba no gasta ni un fotograma.
    private var paused: Bool {
        scenePhase != .active || (bankScroll?.progress ?? 0) > 0.95
    }

    var body: some View {
        if motion.reduce {
            arc
        } else {
            TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
                let degrees = context.date.timeIntervalSinceReferenceDate * 420 / (motion.level.timeScale * motion.timeMultiplier)
                arc.rotationEffect(.degrees(degrees.truncatingRemainder(dividingBy: 360)))
            }
        }
    }

    private var arc: some View {
        Circle()
            .trim(from: 0, to: 0.26)
            .stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 27, height: 27)
            .accessibilityHidden(true)
    }
}

/// «45 %»: el porcentaje de `StepPercent` contado desde `since` (cuando empezó el paso en curso o, si ya acabó bien,
/// cuando acabó: entonces corre hasta 100 en 0,25 s, el remate). Se redibuja con una agenda FINITA de instantes (30 por
/// segundo durante lo que tarda en asentarse); después, nada se mueve hasta que cambie el paso. Con Reducir movimiento
/// no cuenta: enseña el suelo del paso (o 100) y cambia con un fundido. A 17 pt con cifras de ancho fijo: es el dato
/// protagonista de la espera (ojo de diseño 14.6). Para VoiceOver y las pruebas: «Paso 2 de 3, 45 por ciento».
struct StepPercentText: View {
    let percent: StepPercent
    let since: Date
    let stepNumber: Int
    let stepCount: Int
    /// Para las pruebas: va en el propio texto (un identificador puesto por fuera se lo quedaría el contenedor).
    var identifier = ""

    @Environment(\.motion) private var motion

    /// Lo que estira el tiempo: la intensidad y la cámara lenta.
    private var stretch: Double { max(0.05, motion.level.timeScale * motion.timeMultiplier) }

    /// Los instantes en los que la cifra puede cambiar: 30 por segundo durante 3,2 s (a tiempo del kit) desde `since`
    /// mientras el paso sigue; durante el remate, lo que dura (0,25 s del kit).
    private var schedule: [Date] {
        guard !motion.reduce else { return [since] }
        let seconds: Double
        switch percent.outcome {
        case .running: seconds = 3.2
        case .succeeded where percent.finishFrom < 100: seconds = StepPercent.finishSeconds + 0.05
        case .succeeded, .failed: return [since]
        }
        let frames = Int((seconds * stretch * 30).rounded(.up))
        return (0...min(frames, 3_000)).map { since.addingTimeInterval(Double($0) / 30) }
    }

    /// Lo que se dibuja (Core decide: en marcha, remate, congelado; con Reducir, sin contar).
    private func shown(at date: Date) -> Int {
        percent.drawn(elapsed: date.timeIntervalSince(since) / stretch, reduce: motion.reduce)
    }

    var body: some View {
        TimelineView(.explicit(schedule)) { context in
            // Una agenda ya pasada (se vuelve a la pantalla a mitad del paso) deja la fecha del último instante: se cuenta
            // con la hora de verdad.
            let value = shown(at: max(context.date, Date()))
            Text("\(value)\u{00A0}%")
                .titan(.row)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.label)
                .contentTransition(motion.reduce ? .opacity : .identity)
                .animation(motion.reduce ? motion.fade : nil, value: value)
                .accessibilityLabel("Paso \(stepNumber) de \(stepCount), \(value) por ciento")
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier(identifier)
        }
    }
}
