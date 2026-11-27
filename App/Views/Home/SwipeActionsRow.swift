import SwiftUI
import UIKit
import MiBancoCore

/// Una acción que aparece al deslizar una fila.
struct RowSwipeAction: Identifiable {
    /// También es el final de su identificador de accesibilidad (`row-action-<id>`).
    let id: String
    let title: String
    /// En ámbar (por ejemplo «No es mío»).
    var warning = false
    let perform: () -> Void
}

/// Una fila que se desliza hacia la izquierda y enseña sus acciones (cápsulas de 64 pt sobre gris titanio), que entran
/// por la derecha sobre el importe; el contenido solo se aparta un 40 %, así el nombre sigue a la vista.
/// - El contenido sigue al dedo 1:1; más allá de las acciones (o hacia la derecha) hay resistencia de goma.
/// - Al soltar se abre si ha pasado de 70 pt o si el dedo iba rápido hacia la izquierda; si no, se cierra. Abrir lleva
///   el muelle `snap`; cerrar, el mismo sin rebote. Con Reducir movimiento no hay viaje al soltar: se coloca.
/// - Solo hay una fila abierta: abrir otra (o empezar a deslizar otra) cierra esta. Tocar una fila abierta la cierra.
/// - El gesto es un reconocedor de arrastre que SOLO empieza si el dedo va más en horizontal que en vertical
///   (`HorizontalPan`): un arrastre vertical ni lo toca, así que bajar la lista, tocar la fila y mantenerla pulsada
///   (menú) siguen igual. (Un `DragGesture` simultáneo no servía: la lista cancelaba el arrastre de la fila.)
/// VoiceOver no desliza: quien use la fila declara las mismas acciones con `accessibilityAction(named:)`.
struct SwipeActionsRow<Content: View>: View {
    let rowID: UUID
    @Binding var openRow: UUID?
    let actions: [RowSwipeAction]
    /// Con texto de accesibilidad: ancho de la losa + su hueco, para que al abrirse el contenido se aparte lo justo y
    /// la primera letra del nombre quede entera fuera del borde izquierdo (N-2). nil en tamaños normales.
    let leadingShiftLimit: CGFloat?
    let content: Content

    init(
        rowID: UUID,
        openRow: Binding<UUID?>,
        actions: [RowSwipeAction],
        leadingShiftLimit: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.rowID = rowID
        self._openRow = openRow
        self.actions = actions
        self.leadingShiftLimit = leadingShiftLimit
        self.content = content()
    }

    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var offset: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @State private var dragging = false
    @State private var openTick = 0
    /// N-1: las acciones siguen montadas durante toda la animación de cierre hasta su `completion`, así salen siguiendo
    /// `offset` y `SwipeRevealOpacity` igual que al abrir (nunca «Nota» y el importe a la vez).
    @State private var actionsMounted = false
    /// Guarda de generación: si la fila vuelve a abrirse antes de que acabe un cierre anterior, esa `completion` no
    /// desmonta las acciones.
    @State private var closeGeneration = 0

    /// Cada acción en tamaño normal es una cápsula de 64 pt, con 6 pt entre ellas y 10 pt de margen al borde.
    /// Con texto de accesibilidad la fila va apilada y es muy alta: las dos cápsulas se apilan en vertical con 140 pt de
    /// ancho para que «Nota» y «No es mío» se lean enteros, sin partirse a mitad de palabra («Not / a», «No / es…»).
    private static var actionWidth: CGFloat { 64 }
    private static var stackedActionWidth: CGFloat { 140 }
    private static var actionGap: CGFloat { 6 }
    private static var edgeMargin: CGFloat { 10 }

    private var keepsActionsOnClose: Bool {
        #if DEBUG
        return !DemoMode.oldSwipeClose
        #else
        return true
        #endif
    }

    private var usesStackedActions: Bool {
        #if DEBUG
        if DemoMode.oldSwipeClose { return false }
        #endif
        return typeSize.isAccessibilitySize
    }

    private var span: CGFloat {
        if usesStackedActions {
            return Self.stackedActionWidth + Self.edgeMargin
        }
        return CGFloat(actions.count) * Self.actionWidth + CGFloat(max(actions.count - 1, 0)) * Self.actionGap + Self.edgeMargin
    }
    private var isOpen: Bool { offset <= -span + 8 }

    /// Desplazamiento horizontal del contenido según la apertura y el tamaño de texto (`SwipeRowMotion`, Core):
    /// - tamaño normal: 40 % (el nombre sigue a la vista);
    /// - texto de accesibilidad: como mucho `leadingShiftLimit` (losa + hueco), para que la primera letra del nombre
    ///   quede entera en el margen izquierdo sin fundirse en el borde (N-2).
    private var contentOffset: CGFloat {
        #if DEBUG
        if DemoMode.oldSwipe { return offset * 0.4 }
        if DemoMode.fullSwipe { return offset }
        if DemoMode.oldSwipeClose, typeSize.isAccessibilitySize { return offset }
        #endif
        return CGFloat(SwipeRowMotion.contentShift(
            offset: Double(offset),
            span: Double(span),
            leadingShiftLimit: typeSize.isAccessibilitySize ? leadingShiftLimit.map(Double.init) : nil
        ))
    }

    var body: some View {
        let shift = contentOffset
        let showActions = keepsActionsOnClose ? (actionsMounted || offset < -0.5) : (offset < -0.5)
        content
            .background(Theme.canvas)
            .overlay {
                // Abierta, un toque en la fila la cierra (no abre el detalle).
                if offset < -4 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
            }
            // El importe de la fila (donde esté: a la derecha, o debajo del nombre con texto grande) se apaga en los
            // primeros 25 pt (`SwipeRowMotion.amountOpacity`) y las acciones solo entran después (`actionsOpacity`):
            // nunca se leen a la vez, ni al abrir ni al cerrar.
            .environment(\.swipeOpenOffset, offset)
            .offset(x: shift)
            // Lo que sale por la izquierda se desvanece (nunca letras cortadas a cuchillo). Con texto de accesibilidad
            // es más estrecho (16 pt) para quedar por fuera del margen de 20 pt donde empieza la primera letra del nombre.
            .overlay(alignment: .leading) {
                LeadingEdgeFade(amount: min(max(-shift / 12, 0), 1), width: typeSize.isAccessibilitySize ? 16 : 20)
            }
            // Telón negro siguiendo el borde izquierdo de las cápsulas (al abrir y al cerrar): el nombre nunca pasa por
            // debajo de las cápsulas.
            .modifier(TrailingActionCurtain(offset: keepsActionsOnClose ? offset : 0))
            .overlay(alignment: .trailing) {
                if showActions {
                    buttons
                        .offset(x: max(0, span + offset))
                        .transition(keepsActionsOnClose ? .identity : .opacity)
                }
            }
            .clipped()
            .gesture(HorizontalPan(began: panBegan, moved: panMoved, ended: panEnded))
            .onChange(of: openRow) { _, new in
                if new == rowID {
                    // Abierta desde fuera (demo de las ráfagas).
                    if !isOpen, !dragging { settle(open: true) }
                } else if offset != 0, !dragging {
                    settle(open: false)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: openTick)
    }

    private var buttons: some View {
        let open = isOpen
        let stacked = usesStackedActions
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: Self.actionGap))
            : AnyLayout(HStackLayout(spacing: Self.actionGap))
        // Cápsulas redondeadas como el resto de la app, las dos sobre el mismo gris titanio; «No es mío» solo con el
        // texto en ámbar (sin fondo marrón).
        return layout {
            ForEach(actions) { action in
                Button {
                    action.perform()
                    close()
                } label: {
                    let label = Text(action.title)
                        .titan(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(action.warning ? Theme.warning : Theme.label)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(stacked ? 1 : 0.8)
                        .allowsTightening(true)
                        .padding(.horizontal, stacked ? 8 : 4)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .background(Color(hex: "#2C2C2E"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if stacked {
                        label.dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    } else {
                        label
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("row-action-\(action.id)")
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, Self.edgeMargin)
        // Si el muelle se pasa un poco, las acciones se estiran con la fila: nunca queda un hueco negro entre las dos.
        .frame(width: max(span, -offset))
        .modifier(SwipeRevealOpacity(offset: offset))
        .allowsHitTesting(open)
        .accessibilityHidden(!open)
    }

    private func panBegan() {
        closeGeneration += 1
        dragging = true
        dragBase = offset
        // Empezar a deslizar una fila cierra la que estuviera abierta.
        if openRow != nil, openRow != rowID { openRow = nil }
    }

    private func panMoved(_ translation: CGFloat) {
        offset = resisted(dragBase + translation)
        if offset < -0.5 { actionsMounted = true }
    }

    /// El dedo sube (`speed` en pt/s, negativa hacia la izquierda) o el sistema cancela el arrastre.
    private func panEnded(_ speed: CGFloat, _ cancelled: Bool) {
        dragging = false
        if cancelled {
            // La fila no se queda a medias.
            settle(open: offset < -span / 2)
        } else {
            settle(open: (offset < -70 && speed < 400) || speed < -500)
        }
    }

    /// Goma en los dos extremos: hacia la derecha casi no cede; más allá de las acciones, algo más.
    private func resisted(_ x: CGFloat) -> CGFloat {
        if x > 0 {
            return CGFloat(MotionMath.rubberBand(Double(x), dimension: 30))
        }
        if x < -span {
            return -span - CGFloat(MotionMath.rubberBand(Double(-span - x), dimension: 40))
        }
        return x
    }

    private func settle(open: Bool) {
        closeGeneration += 1
        let gen = closeGeneration
        let target: CGFloat = open ? -span : 0
        if open { actionsMounted = true }
        if motion.reduce {
            offset = target
            if !open { actionsMounted = false }
        } else if open, offset == 0, !dragging {
            // Abierta desde cerrada sin dedo (desde fuera: la demo de las ráfagas): primero se montan las acciones con la
            // fila casi cerrada y, en el pase siguiente, se abre con su muelle. Así siguen la apertura fotograma a
            // fotograma, como con el dedo (montadas ya abiertas, aparecerían de golpe). Si entretanto se cierra (o la
            // abre el dedo), el paso siguiente no hace nada.
            offset = -1
            let spring = motion.animation(.snap)
            let row = rowID
            Task { @MainActor in
                guard openRow == row, offset == -1, !dragging else { return }
                withAnimation(spring) { offset = target }
            }
        } else if open {
            withAnimation(motion.animation(.snap)) { offset = target }
        } else {
            withAnimation(motion.calmAnimation(.snap)) {
                offset = 0
            } completion: {
                if closeGeneration == gen, offset >= -0.5, !dragging {
                    actionsMounted = false
                }
            }
        }
        if open {
            if openRow != rowID {
                openTick += 1
                openRow = rowID
            }
        } else if openRow == rowID {
            openRow = nil
        }
    }

    private func close() {
        settle(open: false)
    }
}

/// El borde izquierdo de la fila deslizada: va del negro del fondo a transparente, tan visible como diga `amount`
/// (0 = cerrada, no se ve; 1 = del todo). Lo que sale por la izquierda se desvanece. Solo cambia opacidad y no recibe
/// toques.
private struct LeadingEdgeFade: View {
    let amount: CGFloat
    var width: CGFloat = 20

    var body: some View {
        LinearGradient(colors: [Theme.canvas, Theme.canvas.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
            .opacity(amount)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Telón negro que sigue el borde izquierdo de las cápsulas fotograma a fotograma (al abrir y al cerrar): evita que el
/// nombre del comercio o el subtítulo pasen por debajo de las cápsulas (sin usar `.mask`).
private struct TrailingActionCurtain: ViewModifier, Animatable {
    var offset: CGFloat

    nonisolated var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        let cut = max(0, -offset)
        let fade = min(14, cut)
        content.overlay(alignment: .trailing) {
            if cut > 0.5 {
                HStack(spacing: 0) {
                    LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                    Theme.canvas
                        .frame(width: cut)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

/// La opacidad de las acciones al abrir o cerrar la fila, según lo abierta que está EN CADA FOTOGRAMA (`SwipeRowMotion`,
/// Core): solo empieza a subir tras los 25 pt en los que el importe ya está a 0 (nunca visibles a la vez).
private struct SwipeRevealOpacity: ViewModifier, Animatable {
    var offset: CGFloat

    nonisolated var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(SwipeRowMotion.actionsOpacity(offset: Double(offset)))
    }
}

extension EnvironmentValues {
    /// Cuánto está abierta (en pt, negativo hacia la izquierda) la fila deslizable que contiene esta vista; 0 = cerrada.
    @Entry var swipeOpenOffset: CGFloat = 0
}

/// El importe de una fila deslizable: se apaga en los primeros 25 pt de apertura (antes de que se lean las acciones) y
/// vuelve al cerrarse, siguiendo la apertura fotograma a fotograma (`Animatable`). Se apaga el importe entero, sea cifra o
/// máscara: nunca una máscara transparente sobre una cifra.
struct SwipeAmountFade: ViewModifier {
    @Environment(\.swipeOpenOffset) private var offset

    func body(content: Content) -> some View {
        #if DEBUG
        let fades = !DemoMode.oldSwipe
        #else
        let fades = true
        #endif
        content
            .modifier(SwipeAmountOpacity(offset: fades ? offset : 0))
    }
}

private struct SwipeAmountOpacity: ViewModifier, Animatable {
    var offset: CGFloat

    nonisolated var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }

    func body(content: Content) -> some View {
        let shown = SwipeRowMotion.amountOpacity(offset: Double(offset))
        #if DEBUG
        content
            .opacity(shown)
            .onChange(of: shown == 0, initial: false) { _, hidden in
                if hidden { HomeProbe.shared.rowAmountHidden += 1 }
            }
        #else
        content.opacity(shown)
        #endif
    }
}

/// Un arrastre de un dedo que solo empieza si va más en horizontal que en vertical. Es un reconocedor de UIKit porque
/// ahí se puede decidir ANTES de empezar (`gestureRecognizerShouldBegin`): si el dedo va en vertical, este reconocedor
/// falla y la lista se desplaza como siempre; si va en horizontal, empieza él (está más adentro que la lista) y la
/// lista no se mueve.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let began: () -> Void
    /// Desplazamiento horizontal desde donde empezó.
    let moved: (CGFloat) -> Void
    /// Velocidad horizontal al soltar y si el sistema lo canceló.
    let ended: (CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            began()
        case .changed:
            moved(recognizer.translation(in: recognizer.view).x)
        case .ended:
            ended(recognizer.velocity(in: recognizer.view).x, false)
        case .cancelled, .failed:
            ended(0, true)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
