import SwiftUI

/// Las pantallas empujadas (Gasto, la pantalla de un banco…) montan sus piezas escalonadas la primera vez que se ven
/// (no al volver atrás). Con Reducir movimiento (`motion.reduce`: el del sistema o el forzado para grabar), todo aparece
/// ya colocado. La ventana en la que las piezas pueden entrar dura 1,2 s al tiempo del kit: sigue la intensidad y la
/// cámara lenta.
private struct AssemblesOnFirstAppear: ViewModifier {
    @State private var entrance = Entrance()
    @State private var played = false
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        content
            .environment(\.entrance, entrance)
            .onAppear {
                guard !played, !motion.reduce else { return }
                played = true
                let token = entrance.token + 1
                entrance = Entrance(token: token, active: true, scope: .assembly)
                let window = motion.seconds(MotionEntranceWindow.seconds)
                Task {
                    try? await Task.sleep(for: .seconds(window))
                    if entrance.token == token { entrance.active = false }
                }
            }
    }
}

/// Lo que dura abierta una entrada por capas, en segundos del kit (antes de aplicar intensidad y cámara lenta).
enum MotionEntranceWindow {
    static let seconds = 1.2
}

extension View {
    func assemblesOnFirstAppear() -> some View { modifier(AssemblesOnFirstAppear()) }
}

/// La entrada escalonada de las pantallas de Gasto con los tiempos del kit (`\.motion`): cada pieza sube y aparece con el
/// muelle `enter`, una tras otra (46 ms × 0,84ⁿ, como en la maqueta), y obedece la intensidad (recorrido y rebote), la
/// cámara lenta y Reducir movimiento (sin recorrido: un fundido). Mismo contrato que `.staggeredEntrance` del kit (que
/// aún va con tiempos fijos): `index` es el orden en el montaje por capas y `listIndex` el orden dentro de la lista al
/// cambiar de mes. Fuera de una entrada la pieza ya está en su sitio; solo se animan opacidad y desplazamiento.
/// `slide` es un recorrido horizontal (los avisos entran desde 40 pt a la derecha).
private struct MotionEntrance: ViewModifier {
    let index: Int
    let listIndex: Int?
    let rise: CGFloat
    let slide: CGFloat
    @Environment(\.entrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landed = -1

    private var effectiveIndex: Int? { entrance.scope == .assembly ? index : listIndex }
    private var animates: Bool { entrance.active && effectiveIndex != nil }
    private var visible: Bool { !animates || landed == entrance.token }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(x: visible ? 0 : motion.distance(slide), y: visible ? 0 : motion.distance(rise))
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard animates, let i = effectiveIndex else { return }
        let token = entrance.token
        withAnimation(motion.animation(.enter).delay(motion.stagger(i, firstGap: 0.046, decay: 0.84))) { landed = token }
    }
}

extension View {
    /// Ver `MotionEntrance`. `rise` es el recorrido al nivel Equilibrado (16 pt en la maqueta).
    func motionEntrance(_ index: Int, listIndex: Int? = nil, rise: CGFloat = 16, slide: CGFloat = 0) -> some View {
        modifier(MotionEntrance(index: index, listIndex: listIndex, rise: rise, slide: slide))
    }
}

/// Una pieza que sube y aparece ella sola, `delay` segundos (del kit) después de que `active` pase a ser cierto (o de
/// aparecer, si ya lo es). Para momentos con su propio guion (el banco recién conectado, la bienvenida, la vista previa
/// de un extracto), donde cada pieza tiene su instante. Con Reducir movimiento, solo el fundido. `bounce` es el rebote
/// al nivel Equilibrado (0 = el muelle `enter` de siempre). Al terminar de llegar avisa con `onLanded`.
private struct RisesIn: ViewModifier {
    let active: Bool
    let delay: Double
    let rise: CGFloat
    let scale: CGFloat
    let bounce: Double
    let onLanded: (() -> Void)?
    @Environment(\.motion) private var motion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || motion.reduce ? 1 : scale)
            .offset(y: shown ? 0 : motion.distance(rise))
            .onAppear { if active { arrive() } }
            .onChange(of: active) { _, now in
                if now {
                    arrive()
                } else {
                    shown = false
                }
            }
    }

    private func arrive() {
        guard !shown else { return }
        let spring: Animation = bounce > 0 && !motion.reduce
            ? .spring(response: motion.seconds(0.5), dampingFraction: max(0.45, 1 - bounce * motion.level.bounceScale))
            : motion.animation(.enter)
        withAnimation(spring.delay(motion.seconds(max(0, delay)))) {
            shown = true
        } completion: {
            onLanded?()
        }
    }
}

extension View {
    /// Ver `RisesIn`. `delay` en segundos al nivel Equilibrado; `rise` en puntos al nivel Equilibrado.
    func risesIn(when active: Bool = true, after delay: Double = 0, rise: CGFloat = 14, scale: CGFloat = 1,
                 bounce: Double = 0, onLanded: (() -> Void)? = nil) -> some View {
        modifier(RisesIn(active: active, delay: delay, rise: rise, scale: scale, bounce: bounce, onLanded: onLanded))
    }
}
