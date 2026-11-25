import SwiftUI
import MiBancoCore

// Costuras de movimiento (fase B, F1): objetos compartidos y modificadores que SOLO apuntan marcos en pantalla.
// Los dueños los crea `RootView` y los pasa por el entorno; quien no los recibe (vistas previas, galería, extensiones)
// ve `nil` y los modificadores no hacen nada. Ninguno cambia el diseño, los toques ni la accesibilidad.

/// Dónde está la ranura de la marca en la barra de Inicio: el arranque hace volar la marca hasta ahí.
@MainActor @Observable final class LaunchAnchor {
    /// El marco de la ranura (marca + nombre). Lo lee el arranque mientras dibuja el vuelo, así que es observado; la
    /// barra de Inicio es fija y solo cambia al aparecer, al buscar o al girar.
    var brandFrame: CGRect?
    /// Dentro de la ranura: el lado de la marca (a la izquierda) y el hueco hasta el nombre. Los apunta
    /// `.launchBrandSlot(markSide:gap:)` junto con el marco.
    @ObservationIgnored var brandMarkSide: CGFloat = 30
    @ObservationIgnored var brandGap: CGFloat = 10
    /// Dónde está la marca del bloqueo (y de la tapa del selector de apps, que usa el mismo diseño): de ahí sale
    /// volando al desbloquear. No se borra al quitarse el bloqueo: se lee justo después, en una acción, nunca en un
    /// `body` (por eso no es observado).
    @ObservationIgnored var lockMarkFrame: CGRect?

    /// Qué parte de la marca de la barra lleva ahora mismo la que vuela (y por tanto la ranura NO dibuja): así nunca
    /// hay dos marcas a la vista. Lo ponen y lo quitan las capas que vuelan (`LaunchSequence`, `LaunchExit`); la
    /// carcasa lo borra además si esas capas desaparecen por cualquier otro camino.
    enum Flying {
        /// Solo la marca (la salida del bloqueo): el nombre de la barra entra con Inicio.
        case mark
        /// La marca y el nombre (el arranque sin bloqueo: el nombre vuela con ella).
        case markAndName
    }

    var flying: Flying?
}

/// El vuelo de una tarjeta desde el abanico de Inicio hasta la cabecera de la pantalla del banco.
@MainActor @Observable final class CardFlight {
    struct Request: Equatable {
        let bank: BankID
        let card: AccountCard
        let source: CGRect
    }

    /// Qué tarjeta apuntó su marco con `.cardFlightSource(bank:card:)`.
    struct Source: Hashable {
        let bank: BankID
        let card: AccountCard
    }

    var request: Request?
    var destination: CGRect?
    var landed = false
    /// Marcos de las tarjetas de origen que están en pantalla (los apunta `.cardFlightSource`). Se apuntan en cada
    /// cambio de sitio (también al desplazar) y solo se leen al tocar: no son observados, apuntarlos no redibuja nada.
    @ObservationIgnored var sources: [Source: CGRect] = [:]

    /// Una petición de vuelo con el último marco apuntado de esa tarjeta; `nil` si no está en pantalla.
    func makeRequest(bank: BankID, card: AccountCard) -> Request? {
        guard let frame = sources[Source(bank: bank, card: card)] else { return nil }
        return Request(bank: bank, card: card, source: frame)
    }
}

/// Un cambio de pestaña: `token` sube en cada cambio, `direction` es 1 (hacia la derecha) o −1, y `suppressed`
/// apaga la entrada escalonada (por ejemplo, mientras vuela una tarjeta).
struct TabEntrance: Equatable {
    var token = 0
    var direction = 1
    var suppressed = false
}

/// Marcos de los importes de las filas, por movimiento: el importe del detalle sale volando desde ahí.
///
/// NO es `@Observable` a propósito: las filas apuntan su marco en cada fotograma de un desplazamiento, y con un
/// almacén observado cada apunte invalidaría a quien lo leyera en un `body`. Aquí no hay nada que observar: se apunta
/// sin redibujar nada y se lee una sola vez, en el instante del toque (`frame(for:)`), como pide f1-informe.md.
@MainActor final class DetailAmountFrames {
    private var frames: [UUID: CGRect] = [:]
    #if DEBUG
    /// Solo DEBUG: cuántos apuntes ha recibido (para la galería y las pruebas).
    private(set) var writes = 0
    #endif

    /// El último marco apuntado del importe de la fila de ese movimiento; nil si la fila no está en pantalla.
    func frame(for id: UUID) -> CGRect? { frames[id] }

    func record(_ frame: CGRect?, for id: UUID) {
        frames[id] = frame
        #if DEBUG
        writes += 1
        #endif
    }
}

extension EnvironmentValues {
    @Entry var launchAnchor: LaunchAnchor? = nil
    @Entry var cardFlight: CardFlight? = nil
    @Entry var tabEntrance = TabEntrance()
    @Entry var detailAmountFrames: DetailAmountFrames? = nil
    /// El bloqueo se está fundiendo con su marca y nada vuela (Sutil, Reducir movimiento): la ranura de la marca de la
    /// barra de Inicio no se dibuja hasta que el bloqueo se haya ido (`ShellState.hidesBrandSlot`).
    @Entry var brandSlotHiddenByLock = false
}

extension View {
    /// Apunta el marco de la ranura de la marca en `LaunchAnchor.brandFrame` y la esconde mientras vuela la marca del
    /// arranque (la marca que vuela aterriza justo encima y en ese instante la ranura vuelve a dibujarse: nunca hay
    /// dos). La ranura es: la marca (un cuadrado de `markSide`) a la izquierda, `gap` y el nombre.
    func launchBrandSlot(markSide: CGFloat = 30, gap: CGFloat = 10) -> some View {
        modifier(LaunchBrandSlot(markSide: markSide, gap: gap))
    }

    /// Apunta el marco de esta tarjeta como posible origen de un vuelo (`CardFlight.sources`).
    func cardFlightSource(bank: BankID, card: AccountCard) -> some View {
        modifier(CardFlightSource(source: CardFlight.Source(bank: bank, card: card)))
    }

    /// Apunta el marco de la cabecera donde aterriza la tarjeta (`CardFlight.destination`).
    func cardFlightDestination() -> some View {
        modifier(CardFlightDestination())
    }

    /// Apunta el marco del importe de la fila de este movimiento (`DetailAmountFrames.frames[id]`).
    func detailAmountSource(id: UUID) -> some View {
        modifier(DetailAmountSource(id: id))
    }
}

private struct LaunchBrandSlot: ViewModifier {
    let markSide: CGFloat
    let gap: CGFloat
    @Environment(\.launchAnchor) private var anchor
    @Environment(\.brandSlotHiddenByLock) private var hiddenByLock

    /// Cuánto de la ranura, desde la izquierda, deja de dibujarse: nada, la marca, o todo.
    private var hiddenLeading: CGFloat {
        if hiddenByLock { return .infinity }
        switch anchor?.flying {
        case nil: 0
        case .mark: markSide + gap / 2
        case .markAndName: .infinity
        }
    }

    func body(content: Content) -> some View {
        content
            // Solo deja de DIBUJARSE (una máscara): el botón sigue en su sitio para VoiceOver y para los toques, y su
            // marco no cambia. En reposo la máscara lo deja pasar todo.
            .mask { BrandSlotMask(hiddenLeading: hiddenLeading) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                anchor?.brandMarkSide = markSide
                anchor?.brandGap = gap
                anchor?.brandFrame = frame
            }
            .onDisappear { anchor?.brandFrame = nil }
    }
}

/// La máscara de la ranura de la marca: todo, menos `hiddenLeading` puntos desde la izquierda. Con margen alrededor
/// para no recortar nada que la marca pinte fuera de su marco.
private struct BrandSlotMask: Shape {
    var hiddenLeading: CGFloat

    func path(in rect: CGRect) -> Path {
        let cut = min(max(0, hiddenLeading), rect.width)
        guard cut < rect.width else { return Path() }
        let margin: CGFloat = 12
        let left = cut > 0 ? rect.minX + cut : rect.minX - margin
        return Path(CGRect(
            x: left, y: rect.minY - margin, width: rect.maxX + margin - left, height: rect.height + margin * 2))
    }
}

private struct CardFlightSource: ViewModifier {
    let source: CardFlight.Source
    @Environment(\.cardFlight) private var flight

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { flight?.sources[source] = $0 }
            .onDisappear { flight?.sources[source] = nil }
    }
}

private struct CardFlightDestination: ViewModifier {
    @Environment(\.cardFlight) private var flight

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { flight?.destination = $0 }
            .onDisappear { flight?.destination = nil }
    }
}

private struct DetailAmountSource: ViewModifier {
    let id: UUID
    @Environment(\.detailAmountFrames) private var store

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store?.record($0, for: id) }
            .onDisappear { store?.record(nil, for: id) }
    }
}
