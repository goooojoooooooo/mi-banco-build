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

/// Una fila que se desliza hacia la izquierda y enseña sus acciones (76 pt cada una), como en la maqueta aprobada.
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
    let content: Content

    init(rowID: UUID, openRow: Binding<UUID?>, actions: [RowSwipeAction], @ViewBuilder content: () -> Content) {
        self.rowID = rowID
        self._openRow = openRow
        self.actions = actions
        self.content = content()
    }

    @Environment(\.motion) private var motion
    @State private var offset: CGFloat = 0
    @State private var dragBase: CGFloat = 0
    @State private var dragging = false
    @State private var openTick = 0

    private static var actionWidth: CGFloat { 76 }
    private var span: CGFloat { CGFloat(actions.count) * Self.actionWidth }
    private var isOpen: Bool { offset <= -span + 8 }

    var body: some View {
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
            .offset(x: offset)
            .background(alignment: .trailing) {
                // Las acciones solo existen mientras la fila está (algo) abierta: cerrada, no hay nada debajo.
                if offset < -0.5 { buttons }
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
        let reveal: CGFloat = min(max(-offset / 70, 0), 1)
        let open = isOpen
        return HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    action.perform()
                    close()
                } label: {
                    Text(action.title)
                        .titan(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(action.warning ? Theme.warning : Theme.label)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(action.warning ? Color(hex: "#2E2210") : Color(hex: "#2C2C2E"))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("row-action-\(action.id)")
            }
        }
        // Si el muelle se pasa un poco, las acciones se estiran con la fila: nunca queda un hueco negro entre las dos.
        .frame(width: max(span, -offset))
        .opacity(reveal)
        .allowsHitTesting(open)
        .accessibilityHidden(!open)
    }

    private func panBegan() {
        dragging = true
        dragBase = offset
        // Empezar a deslizar una fila cierra la que estuviera abierta.
        if openRow != nil, openRow != rowID { openRow = nil }
    }

    private func panMoved(_ translation: CGFloat) {
        offset = resisted(dragBase + translation)
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
        let target: CGFloat = open ? -span : 0
        if motion.reduce {
            offset = target
        } else {
            withAnimation(open ? motion.animation(.snap) : motion.calmAnimation(.snap)) { offset = target }
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
