import Foundation
import CoreGraphics

/// La hoja de detalle abierta para un movimiento.
struct DetailRoute: Identifiable, Hashable {
    let id: UUID
    /// Viene de una fila de Inicio: la hoja sale con zoom desde su logo.
    var zooms = false
    /// Dónde estaba el importe en la fila tocada (pantalla completa): el importe del detalle sale volando desde ahí.
    /// No cuenta para la igualdad: la misma hoja es la misma ruta aunque el marco cambie.
    var amountOrigin: CGRect? = nil

    static func == (lhs: DetailRoute, rhs: DetailRoute) -> Bool {
        lhs.id == rhs.id && lhs.zooms == rhs.zooms
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(zooms)
    }
}
