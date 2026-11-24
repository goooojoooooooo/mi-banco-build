#if DEBUG
import Foundation

// Banderas de demo de movimiento de las pantallas (Gasto, Avisos, Ajustes, Bancos, guías, bienvenida).
// Dueño: la línea B «Pantallas» (fase B). Nadie más edita este fichero.
// Cada bandera usa `DemoMode.arguments` o `DemoMode.value(after:)` (`DemoMode.swift` no se toca).
extension DemoMode {
    /// `-MiBancoDemoBudgetWarnings`: cada barra de presupuesto dice en su valor de accesibilidad cuántos avisos (cruces
    /// del 90 %) ha dado y si va en ámbar. Una vibración no se ve desde una prueba; esto sí.
    static var exposesBudgetWarnings: Bool { arguments.contains("-MiBancoDemoBudgetWarnings") }

    /// `-MiBancoDemoChargeToday`: la primera suscripción de la demo se cobra HOY (la demo no trae ninguna que caiga hoy
    /// y la etiqueta «HOY» necesita una para verse). Solo cambia la fila de Suscripciones, no el libro.
    static var chargesToday: Bool { arguments.contains("-MiBancoDemoChargeToday") }
}
#endif
