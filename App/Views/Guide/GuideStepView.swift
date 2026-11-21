import SwiftUI
import MiBancoCore

/// Un paso de la guía por pantalla: dibujo, título, una sola acción, ayuda y «Siguiente».
/// Los pasos se deslizan con un muelle (Reducir movimiento: fundido). Se empuja dentro de la navegación de Ajustes.
struct GuideStepView: View {
    let track: GuideTrack
    let model: LedgerModel

    @State private var index: Int
    @State private var forward = true
    @State private var pendingStep: Int?
    @State private var helpOpen = false
    /// Se acaba de abrir la ayuda: en cuanto el `ScrollView` tenga el contenido ya con ella, se desliza hasta ella.
    @State private var helpRevealPending = false
    /// El alto de la ayuda abierta (0 mientras no se ha medido).
    @State private var helpHeight: CGFloat = 0
    /// Cuántas veces se ha abierto la ayuda: los indicadores destellan al abrirla, no al cerrarla.
    @State private var helpOpenings = 0
    /// H: el alto visible entre la cabecera y los botones fijos.
    @State private var visibleHeight: CGFloat = 0
    /// Dónde acaba lo imprescindible dentro del contenido del paso: la ayuda empieza 8 pt más abajo.
    @State private var essentialsBottom: CGFloat = 0
    @State private var firstNoticeSeen = false
    @State private var shortcutsUnavailable = false
    /// Se abrió retomando una guía a medias: se ofrece «Empezar desde el principio».
    @State private var resumed: Bool
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// `start` es el paso de partida (demo), contando desde 0; `resume`, el paso en que se dejó la guía a medias.
    init(track: GuideTrack, model: LedgerModel, start: Int? = nil, resume: Int? = nil) {
        self.track = track
        self.model = model
        let count = guideSteps(for: track).count
        _index = State(initialValue: min(max(start ?? resume ?? 0, 0), count - 1))
        _resumed = State(initialValue: start == nil && resume != nil)
    }

    private var steps: [GuideStep] { guideSteps(for: track) }
    private var step: GuideStep { steps[index] }
    private var isLast: Bool { index == steps.count - 1 }
    private var bigText: Bool { typeSize.isAccessibilitySize }
    private var status: GuideStatus { guideStatus(track, in: model.state, now: Date()) }

    private var slide: AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        let back: Edge = forward ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: back).combined(with: .opacity))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                page
                    .id(step.id)
                    .transition(slide)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 70, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    if dx < 0 { advance() } else { goBack() }
                })
            controls
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Avisos al instante")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pendingStep) { _, target in
            if let target { applyPending(target) }
        }
        .onChange(of: index) { _, now in preferences.setGuideStep(track, now) }
        .onChange(of: status) { old, new in
            if case .notYet = old, case .working = new {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal) { firstNoticeSeen = true }
            }
        }
        .sensoryFeedback(trigger: firstNoticeSeen) { _, seen in seen ? SensoryFeedback.success : nil }
    }

    // MARK: Cabecera: «Parte 2 de 4 · Paso 9 de 22», la parte y los puntos de avance agrupados por parte

    private var header: some View {
        VStack(spacing: Theme.Space.small) {
            Text(guideProgressLabel(step, number: index + 1, total: steps.count))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.gutter)
                .accessibilityIdentifier("guide-step-counter")
            Text("\(guideParts[step.part - 1]) · \(track.title)")
                .font(.system(.footnote))
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.gutter)
                .accessibilityIdentifier("guide-step-part")
            HStack(spacing: 12) {
                ForEach(1...guideParts.count, id: \.self) { part in
                    HStack(spacing: 5) {
                        ForEach(steps.indices.filter { steps[$0].part == part }, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? Theme.label : (i < index ? Theme.label2 : Theme.passive))
                                .frame(width: i == index ? 18 : 6, height: 6)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: index)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        // La cabecera es una guía de orientación: con letra enorme se queda en un tamaño que no come la pantalla.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.top, Theme.Space.small)
        .padding(.bottom, Theme.Space.row)
    }

    // MARK: Contenido del paso

    /// Un solo `ScrollView` con un solo árbol de vistas: abrir la ayuda, el aviso «¡Funciona!» o el botón de empezar de
    /// nuevo nunca cambian ni rehacen el paso (el foco de VoiceOver se queda en «¿No te sale esto?»). El orden y el alto
    /// del dibujo los decide `guideStepArrangement` (Core) con lo que mide cada pieza: lo imprescindible nunca queda bajo
    /// los botones fijos cuando cabe.
    private var page: some View {
        GuideStepScroll { scroll in
            ScrollView {
                GuideStepStack(visible: visibleHeight, accessibility: bigText) {
                    GuideIllustrationView(step: step, track: track, fitted: true)
                        .accessibilityIdentifier("guide-drawing")
                        .layoutValue(key: GuidePieceKey.self, value: .drawing)
                    essentials(scroll)
                        .layoutValue(key: GuidePieceKey.self, value: .essentials)
                    if helpOpen {
                        helpText(scroll)
                            .layoutValue(key: GuidePieceKey.self, value: .help)
                    }
                    // Solo en una guía retomada y nunca en el primer paso: texto dentro del contenido, después de la ayuda.
                    if resumed && index > 0 {
                        restartButton
                            .layoutValue(key: GuidePieceKey.self, value: .restart)
                    }
                }
                .coordinateSpace(.named(Self.contentSpace))
                .padding(.horizontal, Theme.Space.gutter)
            }
            .scrollPosition(scroll.position)
            // Al abrir la ayuda, el deslizamiento espera a que el `ScrollView` tenga ya el contenido con ella, y va a un
            // desplazamiento calculado con lo medido (no a un identificador, que dentro de esta columna no movía nada).
            .onScrollGeometryChange(for: GuideScrollGeometry.self) { geometry in
                GuideScrollGeometry(content: geometry.contentSize.height,
                                    visible: geometry.containerSize.height,
                                    offset: geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { old, new in
                scroll.offset.current = new.offset
                guard helpRevealPending, new.content > old.content else { return }
                // La ayuda entra justo debajo de lo imprescindible, con 8 pt de separación encima.
                revealHelp(scroll, height: helpHeight > 0 ? helpHeight : new.content - old.content - Theme.Space.small,
                           visible: new.visible, content: new.content)
            }
            // Los indicadores se ven y destellan si el contenido es más alto que lo visible: al aparecer y al abrir la ayuda.
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: helpOpenings)
        }
    }

    /// El espacio de coordenadas del contenido del paso (arriba del contenido = 0, sin contar el desplazamiento).
    private static let contentSpace = "guide-step-content"

    /// Desliza una sola vez hasta la ayuda recién abierta: lo hace lo primero que llegue, su alto medido o el contenido
    /// ya más alto. Reducir movimiento: sin animación.
    private func revealHelp(_ scroll: GuideScrollControl, height: CGFloat, visible: CGFloat, content: CGFloat) {
        guard helpRevealPending else { return }
        helpRevealPending = false
        let y = CGFloat(guideHelpScrollTarget(top: Double(essentialsBottom + Theme.Space.small), height: Double(height),
                                              offset: Double(scroll.offset.current), visible: Double(visible),
                                              content: Double(content)))
        if reduceMotion {
            scroll.position.wrappedValue.scrollTo(y: y)
        } else {
            withAnimation(Theme.Motion.reveal) { scroll.position.wrappedValue.scrollTo(y: y) }
        }
    }

    /// Lo imprescindible para seguir el paso: el aviso «¡Funciona!» si ha llegado, el título, la instrucción entera y
    /// «¿No te sale esto?» cerrado. Es lo que mide T.
    private func essentials(_ scroll: GuideScrollControl) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.row) {
            if firstNoticeSeen { workingBanner.transition(.opacity.combined(with: .scale(scale: 0.96))) }
            Text(step.title)
                .font(.system(.title, weight: .bold))
                .foregroundStyle(Theme.label)
                // Con cualquier alto propuesto el título se parte en líneas: nunca se corta con «…».
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("guide-title")
            Text(Self.styled(step.instruction))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("guide-instruction")
            helpButton(scroll)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Lo imprescindible no se mueve al abrir o cerrar la ayuda: de aquí sale dónde empieza ella.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.contentSpace)).maxY } action: {
            essentialsBottom = $0
        }
    }

    private var restartButton: some View {
        Button {
            resumed = false
            move(to: 0)
        } label: {
            Text("Empezar desde el principio")
                .font(.system(.callout, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Theme.label2)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("guide-restart")
    }

    /// «¡Funciona!»: el ✓ se traza cuando llega el primer aviso real con la guía abierta.
    private var workingBanner: some View {
        HStack(spacing: Theme.Space.row) {
            DrawnCheck(lineWidth: 3, color: Theme.label)
                .frame(width: 26, height: 26)
            Text(track.isApplePay ? "¡Funciona! Ha llegado el primer pago con Apple Pay de \(track.bankName)."
                                  : "¡Funciona! Ha llegado el primer aviso de \(track.bankName).")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.row)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide-working")
    }

    private func helpButton(_ scroll: GuideScrollControl) -> some View {
        Button {
            if helpOpen {
                // Al cerrarla, el paso vuelve a donde estaba al abrirla a la vez que la ayuda se recoge: el contenido
                // no da un salto al encogerse. Reducir movimiento: vuelve sin animación.
                helpRevealPending = false
                let back = scroll.offset.beforeHelp
                if reduceMotion {
                    scroll.position.wrappedValue.scrollTo(y: back)
                    withAnimation(.easeOut(duration: 0.15)) { helpOpen = false }
                } else {
                    withAnimation(Theme.Motion.reveal) {
                        scroll.position.wrappedValue.scrollTo(y: back)
                        helpOpen = false
                    }
                }
            } else {
                scroll.offset.beforeHelp = scroll.offset.current
                helpHeight = 0
                helpRevealPending = true
                helpOpenings += 1
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.reveal) { helpOpen = true }
            }
        } label: {
            HStack(spacing: 6) {
                Text("¿No te sale esto?")
                    .font(.system(.callout, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(.caption, weight: .bold))
                    .rotationEffect(.degrees(helpOpen ? 180 : 0))
            }
            .foregroundStyle(Theme.label)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("guide-help")
        .accessibilityValue(helpOpen ? "Abierto" : "Cerrado")
    }

    private func helpText(_ scroll: GuideScrollControl) -> some View {
        Text(step.help)
            .font(.callout)
            .foregroundStyle(Theme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Theme.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
            // Se mide el alto (no la posición, que la transición desplaza): decide si se enseña entera o desde arriba.
            // El final del contenido aún no se conoce aquí: el `ScrollView` no deja pasar de él.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                helpHeight = height
                revealHelp(scroll, height: height, visible: visibleHeight, content: .greatestFiniteMagnitude)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityIdentifier("guide-help-text")
    }

    // MARK: Botones fijos: Abrir Atajos, Atrás, Siguiente

    private var controls: some View {
        VStack(spacing: Theme.Space.row) {
            if shortcutsUnavailable {
                Text("No se pudo abrir \(GuideNames.shortcutsApp). Búscala en tu iPhone o descárgala del App Store.")
                    .font(.footnote)
                    .foregroundStyle(Theme.label2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("guide-open-failed")
                    .transition(.opacity)
            }
            Button {
                shortcutsUnavailable = false
                guard let url = URL(string: "shortcuts://") else { return }
                // El sistema avisa si no ha podido abrirla (por ejemplo, si no está instalada).
                openURL(url) { accepted in
                    if !accepted { withAnimation(reduceMotion ? nil : Theme.Motion.quick) { shortcutsUnavailable = true } }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Abrir \(GuideNames.shortcutsApp)")
                }
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Theme.label)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("guide-open-shortcuts")

            HStack(spacing: Theme.Space.row) {
                if index > 0 {
                    Button { goBack() } label: {
                        Text("Atrás")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityIdentifier("guide-back")
                    .transition(.opacity)
                }
                Button { advance() } label: {
                    Text(isLast ? "Hecho" : "Siguiente")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("guide-next")
            }
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: index > 0)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.row)
        // Los botones van siempre fijos abajo; con letra enorme se quedan en un tamaño que deja sitio al contenido.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.bottom, Theme.Space.row)
        .background(Theme.canvas)
        .sensoryFeedback(Haptics.detent, trigger: index)
    }

    // MARK: Navegación entre pasos

    private func advance() {
        if isLast {
            preferences.setGuideStep(track, nil)
            dismiss()
        } else { move(to: index + 1) }
    }

    private func goBack() {
        if index > 0 { move(to: index - 1) }
    }

    /// Primero se fija el sentido y el paso al que ir; el cambio de paso se hace en `onChange`, ya con el sentido
    /// pintado, para que el paso que sale y el que entra se deslicen hacia el mismo lado (sin temporizadores).
    private func move(to target: Int) {
        forward = target > index
        pendingStep = target
    }

    private func applyPending(_ target: Int) {
        pendingStep = nil
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.18)) {
            index = target
            helpOpen = false
            helpRevealPending = false
            helpHeight = 0
            shortcutsUnavailable = false
        }
    }

    /// Lo que va entre «» en blanco y seminegrita; el resto, apagado.
    static func styled(_ text: String) -> AttributedString {
        var out = AttributedString()
        var inside = false
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            var part = AttributedString(buffer)
            part.foregroundColor = inside ? Theme.label : Theme.label2
            if inside { part.font = .body.weight(.semibold) }
            out += part
            buffer = ""
        }
        for ch in text {
            if ch == "«" {
                flush()
                inside = true
                buffer.append(ch)
            } else if ch == "»" {
                buffer.append(ch)
                flush()
                inside = false
            } else {
                buffer.append(ch)
            }
        }
        flush()
        return out
    }
}

// MARK: Desplazamiento de un paso

/// Dónde está el contenido de un paso: lo que se lee al deslizar, sin redibujar la vista en cada fotograma.
@MainActor private final class GuideScrollOffset {
    /// El desplazamiento de ahora (desde arriba del contenido).
    var current: CGFloat = 0
    /// El desplazamiento cuando se abrió la ayuda: al cerrarla se vuelve aquí.
    var beforeHelp: CGFloat = 0
}

/// Lo que necesitan la ayuda y su botón para mover el contenido de su paso.
@MainActor private struct GuideScrollControl {
    let position: Binding<ScrollPosition>
    let offset: GuideScrollOffset
}

/// El alto del contenido, el alto visible y el desplazamiento, tal como los ve el `ScrollView`.
private struct GuideScrollGeometry: Equatable {
    var content: CGFloat
    var visible: CGFloat
    var offset: CGFloat
}

/// El estado de desplazamiento nace y muere con cada paso (cada paso es un `ScrollView` nuevo, por su `.id`): una
/// posición de un paso nunca se aplica al siguiente.
private struct GuideStepScroll<Content: View>: View {
    @State private var position = ScrollPosition(idType: String.self)
    @State private var offset = GuideScrollOffset()
    private let content: (GuideScrollControl) -> Content

    init(@ViewBuilder content: @escaping (GuideScrollControl) -> Content) {
        self.content = content
    }

    var body: some View {
        content(GuideScrollControl(position: $position, offset: offset))
    }
}

// MARK: Reparto del paso entre el dibujo y el texto

/// Qué pieza del paso es cada vista de `GuideStepStack`.
private enum GuidePiece {
    case drawing, essentials, help, restart
}

private struct GuidePieceKey: LayoutValueKey {
    static let defaultValue = GuidePiece.essentials
}

/// Coloca las piezas de un paso en una columna, en el orden y con el alto de dibujo que decide `guideStepArrangement`.
/// Mide T (lo imprescindible + la separación al dibujo) y R (empezar de nuevo + su separación) en cada pasada, así que
/// el tamaño de letra, la letra en negrita o el aviso «¡Funciona!» entran solos en la cuenta. Las vistas son siempre las
/// mismas: solo cambia dónde van.
private struct GuideStepStack: Layout {
    /// H: el alto visible entre la cabecera y los botones fijos.
    var visible: CGFloat
    /// Con letra de accesibilidad se queda lo aprobado: el texto arriba y el dibujo debajo a su tamaño natural.
    var accessibility: Bool

    private struct Plan {
        var order: [Int]
        var heights: [CGFloat]
        var total: CGFloat
    }

    private func spacing(_ a: GuidePiece, _ b: GuidePiece) -> CGFloat {
        if a == .drawing || b == .drawing { return Theme.Space.gutter }
        if a == .essentials && b == .help { return Theme.Space.small }
        return Theme.Space.row
    }

    private func plan(width: CGFloat, subviews: Subviews) -> Plan {
        let pieces = subviews.map { $0[GuidePieceKey.self] }
        var heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let essentials = pieces.firstIndex(of: .essentials).map { heights[$0] } ?? 0
        let restart = pieces.firstIndex(of: .restart).map { heights[$0] + spacing(.essentials, .restart) } ?? 0
        let arrangement = accessibility
            ? GuideStepArrangement(order: .textFirst, drawing: GuideStepArrangement.maxDrawing)
            : guideStepArrangement(visible: Double(visible), essentials: Double(essentials + Theme.Space.gutter),
                                   restart: Double(restart))
        let sequence: [GuidePiece] = arrangement.order == .drawingFirst
            ? [.drawing, .essentials, .help, .restart]
            : [.essentials, .help, .restart, .drawing]
        var order: [Int] = []
        for piece in sequence {
            order += pieces.indices.filter { pieces[$0] == piece }
        }
        for i in pieces.indices where pieces[i] == .drawing { heights[i] = CGFloat(arrangement.drawing) }
        var total: CGFloat = 0
        for (n, i) in order.enumerated() {
            if n > 0 { total += spacing(pieces[order[n - 1]], pieces[i]) }
            total += heights[i]
        }
        return Plan(order: order, heights: heights, total: total)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: plan(width: width, subviews: subviews).total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = plan(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (n, i) in plan.order.enumerated() {
            if n > 0 { y += spacing(subviews[plan.order[n - 1]][GuidePieceKey.self], subviews[i][GuidePieceKey.self]) }
            subviews[i].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: plan.heights[i]))
            y += plan.heights[i]
        }
    }
}
