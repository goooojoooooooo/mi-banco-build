import SwiftUI

/// Pasos de un proceso (Autorizar › Leer cuentas › Listo): nodos de 28 pt unidos por líneas que se rellenan.
/// El paso actual entra con un pequeño rebote, los hechos se rellenan de blanco con su ✓ dibujado y cada línea se
/// llena de izquierda a derecha (300 ms). `finished` da por hechos todos los pasos. Con Reducir movimiento todo cambia
/// con fundidos. Cada nodo es un elemento de accesibilidad con su estado.
struct StepperProgress: View {
    let steps: [String]
    let current: Int
    let finished: Bool

    @Environment(\.motion) private var motion

    private func phase(_ i: Int) -> StepNode.Phase {
        finished || i < current ? .done : (i == current ? .current : .pending)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { i in
                if i > 0 { link(filled: phase(i) != .pending) }
                StepNode(title: steps[i], number: i + 1, phase: phase(i))
            }
        }
        .padding(.bottom, 24)
        .animation(motion.reduce ? motion.fade : .easeInOut(duration: motion.seconds(0.3)), value: current)
        .animation(motion.reduce ? motion.fade : .easeInOut(duration: motion.seconds(0.3)), value: finished)
    }

    private func link(filled: Bool) -> some View {
        Capsule()
            .fill(Color(hex: "#2E2E32"))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white)
                    .scaleEffect(x: filled ? 1 : 0, anchor: .leading)
                    .opacity(motion.reduce ? (filled ? 1 : 0) : 1)
            }
            .clipShape(Capsule())
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    private struct StepNode: View {
        enum Phase { case pending, current, done }
        let title: String
        let number: Int
        let phase: Phase

        @Environment(\.motion) private var motion
        @State private var pop: CGFloat = 1

        var body: some View {
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
            .overlay(alignment: .top) {
                Text(title)
                    .titan(.caption)
                    .foregroundStyle(phase == .pending ? Theme.label3 : Theme.label)
                    .fixedSize()
                    .offset(y: 34)
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
    }
}
