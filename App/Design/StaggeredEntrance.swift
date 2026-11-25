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
    /// Espera antes de la primera pieza y la cadencia (s, a nivel Equilibrado): por defecto 0 y 55 ms × 0,8ⁿ.
    var lead: Double = 0
    var firstGap: Double = 0.055
    var decay: Double = 0.8
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
        let delay = motion.reduce ? 0 : motion.seconds(lead) + motion.stagger(i, firstGap: firstGap, decay: decay)
        withAnimation(motion.animation(.enter).delay(delay)) { landed = token }
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

    /// La misma entrada con su propia espera inicial y cadencia (`lead` s; `firstGap` × `decay`ⁿ), p. ej. las líneas del
    /// detalle: desde 0,15 s, 55 ms × 0,82ⁿ.
    func staggeredEntrance(_ index: Int, rise: CGFloat, lead: Double, firstGap: Double, decay: Double) -> some View {
        modifier(StaggeredEntrance(index: index, listIndex: nil, rise: rise, scale: 1, lead: lead, firstGap: firstGap, decay: decay))
    }
}

// MARK: - Cambio de pestaña (T1)

/// La pestaña que entra: su contenido llega desde 70 pt en la dirección del cambio (el muelle `enter`) mientras se
/// funde en 0,17 s; con Reducir movimiento solo el fundido. Lee `\.tabEntrance`, que `RootView` da a cada pestaña:
/// el de la pestaña elegida cambia de `token` en el MISMO instante en que se elige (así no hay ni un fotograma de la
/// pestaña entera antes de la entrada); las demás lo llevan `suppressed` y no se mueven. Al abrir la app no entra
/// nada (`token` 0). Solo opacidad y desplazamiento: los toques llegan desde el primer fotograma.
private struct TabContentEntrance: ViewModifier {
    @Environment(\.tabEntrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landedOffset = -1
    @State private var landedOpacity = -1

    private func landed(_ value: Int) -> Bool { entrance.suppressed || entrance.token == 0 || value == entrance.token }

    func body(content: Content) -> some View {
        content
            .opacity(landed(landedOpacity) ? 1 : 0)
            .offset(x: landed(landedOffset) || motion.reduce ? 0 : motion.distance(70) * CGFloat(entrance.direction))
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard !entrance.suppressed, entrance.token > 0 else { return }
        let token = entrance.token
        withAnimation(.easeOut(duration: motion.seconds(0.17))) { landedOpacity = token }
        withAnimation(motion.animation(.enter)) { landedOffset = token }
    }
}

/// Un grupo de la pestaña que entra (título, bloques): tras la llegada del contenido, sube 16 pt y aparece escalonado
/// como en el prototipo (30 ms y luego 46 ms × 0,84ⁿ; el primero no sube). Para los dueños de cada pestaña: basta con
/// `.tabGroupEntrance(n)` en cada grupo. Con Reducir movimiento solo se funde, sin esperas.
private struct TabGroupEntrance: ViewModifier {
    let index: Int
    let rise: CGFloat
    @Environment(\.tabEntrance) private var entrance
    @Environment(\.motion) private var motion
    @State private var landed = -1

    private var visible: Bool {
        entrance.suppressed || entrance.token == 0 || index >= Theme.Motion.staggerLimit || landed == entrance.token
    }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || motion.reduce || index == 0 ? 0 : motion.distance(rise))
            .onAppear(perform: land)
            .onChange(of: entrance.token) { _, _ in land() }
    }

    private func land() {
        guard !entrance.suppressed, entrance.token > 0, index < Theme.Motion.staggerLimit else { return }
        let token = entrance.token
        let delay = motion.reduce ? 0 : motion.seconds(0.03) + motion.stagger(index, firstGap: 0.046, decay: 0.84)
        withAnimation(motion.animation(.enter).delay(delay)) { landed = token }
    }
}

extension View {
    /// El contenido entero de una pestaña al elegirla (lo pone `RootView`).
    func tabContentEntrance() -> some View { modifier(TabContentEntrance()) }

    /// Un grupo dentro de una pestaña: entra escalonado cuando se elige la pestaña (`index` 0 = el primero).
    func tabGroupEntrance(_ index: Int, rise: CGFloat = 16) -> some View {
        modifier(TabGroupEntrance(index: index, rise: rise))
    }
}
