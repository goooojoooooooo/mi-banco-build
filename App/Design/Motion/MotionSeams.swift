import SwiftUI
import MiBancoCore

// Costuras de movimiento (fase B, F1): objetos compartidos y modificadores que SOLO apuntan marcos en pantalla.
// Los dueños los crea `RootView` y los pasa por el entorno; quien no los recibe (vistas previas, galería, extensiones)
// ve `nil` y los modificadores no hacen nada. Ninguno cambia el diseño, los toques ni la accesibilidad.

/// Dónde está la ranura de la marca en la barra de Inicio: el arranque hace volar la marca hasta ahí.
@MainActor @Observable final class LaunchAnchor {
    var brandFrame: CGRect?
    /// Dónde está la marca del bloqueo (y de la tapa del selector de apps, que usa el mismo diseño): de ahí sale
    /// volando al desbloquear. No se borra al quitarse el bloqueo: se lee justo después.
    var lockMarkFrame: CGRect?
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
    /// Marcos de las tarjetas de origen que están en pantalla (los apunta `.cardFlightSource`).
    var sources: [Source: CGRect] = [:]

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
@MainActor @Observable final class DetailAmountFrames {
    var frames: [UUID: CGRect] = [:]
}

extension EnvironmentValues {
    @Entry var launchAnchor: LaunchAnchor? = nil
    @Entry var cardFlight: CardFlight? = nil
    @Entry var tabEntrance = TabEntrance()
    @Entry var detailAmountFrames: DetailAmountFrames? = nil
}

extension View {
    /// Apunta el marco de la ranura de la marca en `LaunchAnchor.brandFrame`.
    func launchBrandSlot() -> some View {
        modifier(LaunchBrandSlot())
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
    @Environment(\.launchAnchor) private var anchor

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor?.brandFrame = $0 }
            .onDisappear { anchor?.brandFrame = nil }
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
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { store?.frames[id] = $0 }
            .onDisappear { store?.frames[id] = nil }
    }
}
