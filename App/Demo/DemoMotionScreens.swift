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

    /// `-MiBancoDemoBigSubscriptions`: la cabecera de Suscripciones enseña sus dos importes multiplicados por cien
    /// (solo lo que se dibuja, no el libro), para probar que con importes largos y letra grande salta de línea.
    static var bigSubscriptionTotals: Bool { arguments.contains("-MiBancoDemoBigSubscriptions") }

    /// `-MiBancoDemoEntranceCount`: Gasto dice (en un elemento de accesibilidad invisible) cuántas entradas ha jugado.
    static var exposesEntranceCount: Bool { arguments.contains("-MiBancoDemoEntranceCount") }

    /// `-MiBancoDemoDrawnAmounts`: en Próximos cobros cada fila con importe dice, como valor de accesibilidad, el texto
    /// que DIBUJA («dibujado: −•••,•• €»). Así una prueba puede fallar si con el ojo cerrado se dibuja una cifra.
    static var exposesDrawnAmounts: Bool { arguments.contains("-MiBancoDemoDrawnAmounts") }

    /// `-MiBancoDemoConnectScript`: en la pantalla de un banco, «Conectar» o «Renovar conexión» recorre el trámite entero
    /// sin red (Verificar › Conectar › Importar › conectado, y después la lista llenándose por primera vez). En la demo el
    /// conector de verdad se queda en el primer paso; esto solo hace de banco: la pantalla y su porcentaje son los reales.
    static var scriptsConnect: Bool { isActive && arguments.contains("-MiBancoDemoConnectScript") }

    /// Segundos que el banco de mentira tarda en cada paso del guion (`-MiBancoDemoConnectStep <s>`; por defecto 2,2).
    static var connectScriptStepSeconds: Double {
        guard let raw = value(after: "-MiBancoDemoConnectStep"), let seconds = Double(raw), seconds.isFinite else { return 2.2 }
        return min(20, max(0.2, seconds))
    }

    /// Segundos que la lista tarda en llenarse por primera vez tras conectar en el guion (`-MiBancoDemoConnectFill <s>`;
    /// por defecto 3,4): mientras tanto se ve el esqueleto.
    static var connectScriptFillSeconds: Double {
        guard let raw = value(after: "-MiBancoDemoConnectFill"), let seconds = Double(raw), seconds.isFinite else { return 3.4 }
        return min(30, max(0.2, seconds))
    }

    /// `-MiBancoDemoFlightRequest`: al abrir la pantalla de un banco se hace como si una tarjeta viniera volando desde
    /// Inicio y no llegara nunca (hoy nadie la hace aterrizar). La cabecera tiene que acabar viéndose igual.
    static var requestsFlightOnOpen: Bool { isActive && arguments.contains("-MiBancoDemoFlightRequest") }

    /// `-MiBancoDemoImportSlow`: los pasos de «Importar extracto» duran 2 s cada uno (en vez de 0,35 s), para poder
    /// verlos desde una prueba de toque.
    static var slowsImportSteps: Bool { isActive && arguments.contains("-MiBancoDemoImportSlow") }
}
#endif
