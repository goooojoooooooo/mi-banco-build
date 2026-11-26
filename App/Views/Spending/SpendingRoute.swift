import Foundation
import MiBancoCore

/// Las pantallas que se empujan dentro de la pila de Gasto (nunca hojas: la única hoja de la app es de `RootView`).
enum SpendingRoute: Hashable {
    /// Los movimientos de una categoría en un mes (inicio del mes).
    case category(SpendingCategory, Date)
    case budgets
    case transfers
    case subscriptions
    case hiddenSubscriptions
    case upcoming
}
