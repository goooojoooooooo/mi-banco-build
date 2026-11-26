import SwiftUI
import MiBancoCore

// El momento de éxito de una hoja (maqueta aprobada, `successNow`): el ✓ salta de 0,3 a 1 con rebote y se traza, y
// debajo entran el título, los datos y el botón a los 0,16 / 0,23 / 0,30 / 0,38 s. Solo son piezas de movimiento: los textos los pone quien las usa. Con Reducir movimiento todo
// se funde en su sitio. Tiempos, recorridos y rebote salen de `\.motion`; solo cambian escala, desplazamiento, opacidad
// y color.
// Regla D9: el ✓ del éxito (`SuccessMark`) y su háptica son SOLO para un traspaso que la app ha VISTO salir («He visto
// salir…») y para confirmaciones destructivas. «Mover dinero» solo prepara (copia un dato y abre el banco; el dinero lo
// envía el dueño allí): su paso «listo» usa `PreparedMark`, el ✓ neutro en aro de titanio, con una entrada tranquila.

/// El ✓ del éxito: disco blanco con el ✓ negro. Salta de 0,3 a 1 (muelle `release`) y el ✓ se traza 0,16 s después.
/// Solo para algo que de verdad ha pasado (ver la regla D9 arriba).
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
                #if DEBUG
                HomeProbe.shared.successMarks += 1
                #endif
                // Con Reducir movimiento entra cuando lo anterior ya se ha fundido (nunca dos pantallas superpuestas).
                withAnimation(motion.animation(.release).delay(motion.reduce ? motion.pause(0.22) : 0)) { popped = true }
                if motion.reduce {
                    drawn = true
                } else {
                    withAnimation(.easeOut(duration: motion.seconds(0.32)).delay(motion.seconds(0.16))) { drawn = true }
                }
            }
            .accessibilityHidden(true)
    }
}

/// El ✓ de «preparado» (no de «enviado»): aro fino de titanio sobre un disco apenas visible, con el ✓ de titanio que se
/// traza. Aparece con un fundido, sin salto ni rebote; con Reducir movimiento entra ya trazado cuando lo anterior se ha
/// fundido (`pause(0.22)` = lo que dura el fundido del kit).
struct PreparedMark: View {
    var size: CGFloat = 72

    @Environment(\.motion) private var motion
    @State private var shown = false
    @State private var drawn = false

    private static let titanium = Color(hex: "#D6D8DC")

    var body: some View {
        ZStack {
            Circle().fill(Theme.label.opacity(0.08))
            Circle().strokeBorder(Self.titanium.opacity(0.55), lineWidth: 1.5)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Self.titanium, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.42, height: size * 0.42)
        }
        .frame(width: size, height: size)
        .opacity(shown ? 1 : 0)
        .onAppear {
            #if DEBUG
            HomeProbe.shared.preparedMarks += 1
            #endif
            if motion.reduce {
                drawn = true
                withAnimation(motion.fade.delay(motion.pause(0.22))) { shown = true }
            } else {
                // 0,1 s después: el paso del importe ya se ha apagado donde aparece el aro (nada se monta encima).
                withAnimation(motion.calmAnimation(.enter).delay(motion.seconds(0.1))) { shown = true }
                withAnimation(.easeOut(duration: motion.seconds(0.35)).delay(motion.seconds(0.22))) { drawn = true }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Una pieza que entra después del ✓, en su turno (0 = el titular, 1 = el texto, 2 = los datos, 3 = el botón).
/// `calm`: sube sin pasarse de su sitio (el paso «listo» de «Mover dinero», que no celebra nada).
private struct SuccessEntrance: ViewModifier {
    let order: Int
    let calm: Bool
    @Environment(\.motion) private var motion
    @State private var landed = false

    private static let delays: [Double] = [0.16, 0.23, 0.30, 0.38]
    private static let rises: [CGFloat] = [18, 14, 18, 26]

    func body(content: Content) -> some View {
        let slot = min(max(order, 0), Self.delays.count - 1)
        content
            .offset(y: landed ? 0 : motion.distance(calm ? Self.rises[slot] * 0.6 : Self.rises[slot]))
            .opacity(landed ? 1 : 0)
            .onAppear {
                // Con Reducir movimiento, cuando el fundido del paso anterior ha terminado (`pause(0.22)`).
                let delay = motion.reduce ? motion.pause(0.22) : motion.seconds(Self.delays[slot])
                let curve = calm ? motion.calmAnimation(.enter) : motion.animation(.enter)
                withAnimation(curve.delay(delay)) { landed = true }
            }
    }
}

extension View {
    /// Entra tras el ✓, en su turno (ver `SuccessEntrance`). `calm`: sin rebote y con menos recorrido.
    func successEntrance(_ order: Int, calm: Bool = false) -> some View {
        modifier(SuccessEntrance(order: order, calm: calm))
    }
}
