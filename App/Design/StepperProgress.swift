import SwiftUI

/// Pasos de un proceso (Autorizar › Leer cuentas › Listo): nodos de 28 pt unidos por líneas que se rellenan.
/// El paso actual entra con un pequeño rebote, los hechos se rellenan de blanco con su ✓ dibujado y cada línea se
/// llena de izquierda a derecha (300 ms). `finished` da por hechos todos los pasos. Con Reducir movimiento todo cambia
/// con fundidos. Cada nodo es un elemento de accesibilidad con su estado.
/// Con tamaños de texto de accesibilidad los pasos pasan a una columna (nodo y título en una fila) para que los títulos
/// no se pisen ni se recorten; en horizontal, cada título cabe en el ancho de su paso y puede ocupar dos líneas.
struct StepperProgress: View {
    let steps: [String]
    let current: Int
    let finished: Bool

    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize

    private func phase(_ i: Int) -> StepNode.Phase {
        finished || i < current ? .done : (i == current ? .current : .pending)
    }

    private var transition: Animation {
        motion.reduce ? motion.fade : .easeInOut(duration: motion.seconds(0.3))
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            StepNode(title: steps[i], number: i + 1, phase: phase(i), label: .beside)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        if i > 0 { link(filled: phase(i) != .pending).padding(.top, 13) }
                        StepNode(title: steps[i], number: i + 1, phase: phase(i), label: .below)
                    }
                }
            }
        }
        .animation(transition, value: current)
        .animation(transition, value: finished)
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
        enum LabelPlace { case below, beside }
        let title: String
        let number: Int
        let phase: Phase
        let label: LabelPlace

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
                }
            }
            .onChange(of: phase) { _, new in
                guard new == .current, !motion.reduce else { return }
                pop = 0.7
                withAnimation(.spring(response: motion.seconds(0.34), dampingFraction: 1 - min(0.62, 0.5 * motion.level.bounceScale))) {
                    pop = 1
                }
            }
            .animation(motion.reduce ? motion.fade : .easeInOut(duration: 0.2), value: phase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Paso \(number): \(title)")
            .accessibilityValue(phase == .done ? "hecho" : (phase == .current ? "en curso" : "pendiente"))
        }

        private var node: some View {
            ZStack {
                Circle().fill(phase == .done ? Color.white : Color(hex: "#141416"))
                Circle().strokeBorder(phase == .pending ? Color(hex: "#48484C") : Color.white,
                                      lineWidth: phase == .done ? 0 : 1.5)
                if phase == .done {
                    DrawnCheck(lineWidth: 3, color: .black)
                        .frame(width: 16, height: 16)
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
