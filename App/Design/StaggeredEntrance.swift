import SwiftUI

/// Una entrada escalonada en curso. `token` cambia en cada entrada; mientras `active`, las piezas aparecen
/// una tras otra (60 ms). `scope`: `.assembly` = montaje de Inicio por capas (al arrancar y al desbloquear) o de la hoja;
/// `.list` = solo la lista, al cambiar de tarjeta.
struct Entrance: Equatable {
    enum Scope: Equatable { case assembly, list }
    var token = 0
    var active = false
    var scope = Scope.assembly
}

extension EnvironmentValues {
    @Entry var entrance = Entrance()
}

/// Sube `rise` pt y aparece con el muelle `enter` del kit, escalonada: 55 ms tras la primera pieza y cada hueco un
/// 20 % más corto (55 ms × 0,8ⁿ). Lee `\.motion`: obedece la intensidad (tiempos, recorrido y rebote), Reducir
/// movimiento —también el forzado al grabar: las piezas solo se funden, sin subir ni crecer— y la cámara lenta.
/// Fuera de una entrada (o con índice alto) la pieza ya está en su sitio: nunca se espera para poder tocar nada, y
/// solo se animan opacidad, escala y desplazamiento.
private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let listIndex: Int?
    let rise: CGFloat
    let scale: CGFloat
    @Environment(\.entrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landed = -1

    private var effectiveIndex: Int? { entrance.scope == .assembly ? index : listIndex }
    private var animates: Bool {
        guard entrance.active, let i = effectiveIndex else { return false }
        return i < Theme.Motion.staggerLimit
    }
    private var visible: Bool { !animates || landed == entrance.token }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || motion.reduce ? 1 : scale)
            .offset(y: visible ? 0 : motion.distance(rise))
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard animates, let i = effectiveIndex else { return }
        let token = entrance.token
        // `motion.animation` ya es un fundido con Reducir movimiento, y `motion.stagger` no espera.
        withAnimation(motion.animation(.enter).delay(StaggerPlan.delay(i, motion: motion))) { landed = token }
    }
}

/// El retardo de la pieza `index` de una entrada escalonada del kit (55 ms × 0,8ⁿ, según intensidad y cámara lenta;
/// 0 con Reducir movimiento).
enum StaggerPlan {
    static func delay(_ index: Int, motion: MotionContext) -> Double {
        motion.stagger(index, firstGap: 0.055, decay: 0.8)
    }
}

extension View {
    /// `index`: orden en el montaje por capas. `listIndex`: orden dentro de la lista (solo las filas y el resumen),
    /// para la entrada al cambiar de tarjeta.
    func staggeredEntrance(_ index: Int, listIndex: Int? = nil, rise: CGFloat = 14, scale: CGFloat = 1) -> some View {
        modifier(StaggeredEntrance(index: index, listIndex: listIndex, rise: rise, scale: scale))
    }
}
