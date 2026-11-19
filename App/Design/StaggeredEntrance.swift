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

/// Sube `rise` pt y aparece con el muelle de montaje, `índice × 60 ms` después de empezar la entrada.
/// Fuera de una entrada (o con índice alto, o con Reducir movimiento) la pieza ya está en su sitio:
/// nunca se espera para poder tocar nada, y solo se animan opacidad y desplazamiento.
private struct StaggeredEntrance: ViewModifier {
    let index: Int
    let listIndex: Int?
    let rise: CGFloat
    let scale: CGFloat
    @Environment(\.entrance) private var entrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = -1

    private var effectiveIndex: Int? { entrance.scope == .assembly ? index : listIndex }
    private var animates: Bool {
        guard entrance.active, !reduceMotion, let i = effectiveIndex else { return false }
        return i < Theme.Motion.staggerLimit
    }
    private var visible: Bool { !animates || landed == entrance.token }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : scale)
            .offset(y: visible ? 0 : rise)
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard animates, let i = effectiveIndex else { return }
        let token = entrance.token
        withAnimation(Theme.Motion.assemble.delay(Double(i) * Theme.Motion.staggerStep)) { landed = token }
    }
}

extension View {
    /// `index`: orden en el montaje por capas. `listIndex`: orden dentro de la lista (solo las filas y el resumen),
    /// para la entrada al cambiar de tarjeta.
    func staggeredEntrance(_ index: Int, listIndex: Int? = nil, rise: CGFloat = 14, scale: CGFloat = 1) -> some View {
        modifier(StaggeredEntrance(index: index, listIndex: listIndex, rise: rise, scale: scale))
    }
}
