import SwiftUI

/// Las pantallas empujadas de Gasto montan sus piezas escalonadas la primera vez que se ven (no al volver atrás).
/// Con Reducir movimiento, todo aparece ya colocado.
private struct AssemblesOnFirstAppear: ViewModifier {
    @State private var entrance = Entrance()
    @State private var played = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.entrance, entrance)
            .onAppear {
                guard !played, !reduceMotion else { return }
                played = true
                let token = entrance.token + 1
                entrance = Entrance(token: token, active: true, scope: .assembly)
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    if entrance.token == token { entrance.active = false }
                }
            }
    }
}

extension View {
    func assemblesOnFirstAppear() -> some View { modifier(AssemblesOnFirstAppear()) }
}

/// La entrada escalonada de las pantallas de Gasto con los tiempos del kit (`\.motion`): cada pieza sube y aparece con el
/// muelle `enter`, una tras otra (46 ms × 0,84ⁿ, como en la maqueta), y obedece la intensidad (recorrido y rebote), la
/// cámara lenta y Reducir movimiento (sin recorrido: un fundido). Mismo contrato que `.staggeredEntrance` del kit (que
/// aún va con tiempos fijos): `index` es el orden en el montaje por capas y `listIndex` el orden dentro de la lista al
/// cambiar de mes. Fuera de una entrada la pieza ya está en su sitio; solo se animan opacidad y desplazamiento.
private struct MotionEntrance: ViewModifier {
    let index: Int
    let listIndex: Int?
    let rise: CGFloat
    @Environment(\.entrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landed = -1

    private var effectiveIndex: Int? { entrance.scope == .assembly ? index : listIndex }
    private var animates: Bool { entrance.active && effectiveIndex != nil }
    private var visible: Bool { !animates || landed == entrance.token }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : motion.distance(rise))
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
    func motionEntrance(_ index: Int, listIndex: Int? = nil, rise: CGFloat = 16) -> some View {
        modifier(MotionEntrance(index: index, listIndex: listIndex, rise: rise))
    }
}
