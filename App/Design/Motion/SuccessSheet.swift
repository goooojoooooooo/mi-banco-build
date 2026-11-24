import SwiftUI
import MiBancoCore

// El momento de éxito de una hoja (maqueta aprobada, `successNow`): el ✓ salta de 0,3 a 1 con rebote y se traza, y
// debajo entran el título, los datos y el botón a los 0,16 / 0,23 / 0,30 / 0,38 s; el botón principal empieza apagado y
// se enciende a los 0,9 s. Solo son piezas de movimiento: los textos los pone quien las usa («Mover dinero» prepara un
// traspaso, nunca lo envía: aquí no hay ningún «Enviado»). Con Reducir movimiento todo se funde en su sitio.
// Tiempos, recorridos y rebote salen de `\.motion`; solo cambian escala, desplazamiento, opacidad y color.

/// El ✓ del éxito: disco blanco con el ✓ negro. Salta de 0,3 a 1 (muelle `release`) y el ✓ se traza 0,16 s después.
struct SuccessMark: View {
    var size: CGFloat = 76

    @Environment(\.motion) private var motion
    @State private var popped = false
    @State private var drawn = false

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay {
                CheckShape()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round, lineJoin: .round))
                    .padding(size * 0.25)
            }
            .scaleEffect(popped || motion.reduce ? 1 : 0.3)
            .opacity(popped ? 1 : 0)
            .onAppear {
                withAnimation(motion.animation(.release)) { popped = true }
                if motion.reduce {
                    drawn = true
                } else {
                    withAnimation(.easeOut(duration: motion.seconds(0.32)).delay(motion.seconds(0.16))) { drawn = true }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Una pieza que entra después del ✓, en su turno (0 = el titular, 1 = el texto, 2 = los datos, 3 = el botón).
private struct SuccessEntrance: ViewModifier {
    let order: Int
    @Environment(\.motion) private var motion
    @State private var landed = false

    private static let delays: [Double] = [0.16, 0.23, 0.30, 0.38]
    private static let rises: [CGFloat] = [18, 14, 18, 26]

    func body(content: Content) -> some View {
        let slot = min(max(order, 0), Self.delays.count - 1)
        content
            .offset(y: landed ? 0 : motion.distance(Self.rises[slot]))
            .opacity(landed ? 1 : 0)
            .onAppear {
                let delay = motion.reduce ? 0 : motion.seconds(Self.delays[slot])
                withAnimation(motion.animation(.enter).delay(delay)) { landed = true }
            }
    }
}

extension View {
    /// Entra tras el ✓ del éxito, en su turno (ver `SuccessEntrance`).
    func successEntrance(_ order: Int) -> some View {
        modifier(SuccessEntrance(order: order))
    }
}

/// El botón principal de un éxito: empieza apagado (gris) y se enciende (blanco) a los 0,9 s. Se puede tocar desde el
/// principio; se hunde como el cristal (0,88) al tocar.
struct SuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SuccessButtonFace(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct SuccessButtonFace<Face: View>: View {
    let label: Face
    let pressed: Bool

    @Environment(\.motion) private var motion
    @State private var lit = false

    var body: some View {
        label
            .foregroundStyle(lit ? Theme.onTileSelected : Theme.label3)
            .background(lit ? Theme.tileSelected : Color(hex: "#2C2C2E"), in: Capsule())
            .scaleEffect(pressed && !motion.reduce ? 0.94 : 1)
            .opacity(pressed && motion.reduce ? 0.7 : 1)
            .animation(pressed ? motion.animation(.pressIn) : motion.animation(.release), value: pressed)
            .onAppear {
                withAnimation(.easeOut(duration: motion.seconds(0.45)).delay(motion.seconds(0.9))) { lit = true }
            }
    }
}
