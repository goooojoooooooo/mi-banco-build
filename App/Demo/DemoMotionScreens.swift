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

    /// `-MiBancoDemoBigSubscriptions`: la cabecera de Suscripciones enseña sus dos importes multiplicados por mil
    /// (solo lo que se dibuja, no el libro), para probar que con importes largos y letra grande salta de línea.
    static var bigSubscriptionTotals: Bool { arguments.contains("-MiBancoDemoBigSubscriptions") }

    /// `-MiBancoDemoEntranceCount`: Gasto dice (en un elemento de accesibilidad invisible) cuántas entradas ha jugado.
    static var exposesEntranceCount: Bool { arguments.contains("-MiBancoDemoEntranceCount") }

    /// `-MiBancoDemoDrawnAmounts`: en Próximos cobros cada fila con importe dice, como valor de accesibilidad, el texto
    /// que DIBUJA («dibujado: −•••,•• €»). Así una prueba puede fallar si con el ojo cerrado se dibuja una cifra.
    static var exposesDrawnAmounts: Bool { arguments.contains("-MiBancoDemoDrawnAmounts") }

    /// `-MiBancoDemoConnectScript`: en la pantalla de un banco, «Conectar» o «Renovar conexión» recorre el trámite entero
    /// sin red (Verificar › Conectar › Importar › conectado, y después la lista llenándose por primera vez). Hace de banco
    /// mandando los eventos de verdad (`start`, `webOpened`, `callback`, `succeeded`/`failed`) a una máquina `ConnectFlow`
    /// de la pantalla; su fase entra por el mismo sitio que la del conector y la traduce `BankConnectProgress` (Core).
    static var scriptsConnect: Bool { isActive && arguments.contains("-MiBancoDemoConnectScript") }

    /// `-MiBancoDemoConnectFails`: el banco del guion falla mientras se le espera (segundo paso) con el mensaje de siempre
    /// («El banco tardó demasiado…»), en vez de conectar.
    static var connectScriptFails: Bool { isActive && arguments.contains("-MiBancoDemoConnectFails") }

    /// `-MiBancoDemoDockProbe`: la pantalla del banco lleva un elemento invisible (`bank-dock-probe`) que dice lo acoplada
    /// que está la hoja, la opacidad del saldo grande y la del título pequeño, el mayor solape visto y el de las curvas.
    static var exposesDockProbe: Bool { isActive && arguments.contains("-MiBancoDemoDockProbe") }

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

    /// `-MiBancoDemoImportOnOpen`: al abrir la pantalla de Revolut (tocando su fila) se empuja la vista previa del
    /// extracto de ejemplo, como hace `-MiBancoDemoImport`, pero sin abrir nada al arrancar: así la importación empieza
    /// cuando la prueba quiere (con el arranque ya terminado), no debajo de él.
    static var importsOnBankOpen: Bool { isActive && arguments.contains("-MiBancoDemoImportOnOpen") }

    /// `-MiBancoDemoImportSlow`: los pasos de «Importar extracto» duran 8 s cada uno (en vez de 0,35 s), para poder
    /// verlos desde una prueba de toque (que tarda unos segundos en empezar a mirar).
    static var slowsImportSteps: Bool { isActive && arguments.contains("-MiBancoDemoImportSlow") }

    /// `-MiBancoDemoRegressMaskedField`: SOLO para demostrar que la prueba de privacidad falla con el defecto de antes: el
    /// campo de importe enmascarado vuelve a llevar la cifra real dentro, pintada en transparente.
    static var regressesMaskedField: Bool { isActive && arguments.contains("-MiBancoDemoRegressMaskedField") }

    /// `-MiBancoDemoRegressEyeFocus`: SOLO para demostrar que la prueba falla con el defecto de antes: cerrar el ojo desde
    /// Ajustes no suelta el foco del saldo en edición.
    static var regressesEyeFocus: Bool { isActive && arguments.contains("-MiBancoDemoRegressEyeFocus") }

    /// `-MiBancoDemoCloseEyeAfter <s>`: Ajustes cierra el ojo solo (como el interruptor) a los segundos dados (reales).
    /// Para grabar desde ANTES del cierre (un fotograma de control con las cifras) y para cerrar el ojo con un saldo en
    /// edición sin tocar nada (el teclado taparía el interruptor).
    static var closesEyeAfterSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoCloseEyeAfter"), let seconds = Double(raw), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 120)
    }

    /// `-MiBancoDemoConnectedDoneAfter <s>`: en la pantalla de un banco, «banco conectado» se cierra solo (como «Listo»)
    /// a los segundos dados (reales) desde que aparece. Para grabar desde ANTES del cierre.
    static var connectedDoneAfterSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoConnectedDoneAfter"), let seconds = Double(raw),
              seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 120)
    }
}
#endif
