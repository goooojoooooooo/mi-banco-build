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

    /// `-MiBancoDemoSettingsCloseEyeAfter <s>`: Ajustes cierra el ojo solo (como el
    /// interruptor) a los segundos dados (reales) desde que aparece «Modo privado». Cuenta desde la pantalla, no
    /// desde el arranque como `-MiBancoDemoCloseEyeOverRoll` de `RootView`.
    static var closesEyeAfterSeconds: Double? {
        guard isActive,
              let raw = value(after: "-MiBancoDemoSettingsCloseEyeAfter"),
              let seconds = Double(raw), seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 120)
    }

    /// `-MiBancoDemoFocusBalanceAfter <s>`: Ajustes enfoca el saldo de Trade Republic solo, a los segundos dados (reales),
    /// como si se tocara. Para grabar desde ANTES del toque lo que enseña el campo al editarlo con el ojo cerrado.
    static var focusesBalanceAfterSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoFocusBalanceAfter"), let seconds = Double(raw),
              seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 120)
    }

    /// `-MiBancoDemoConnectedDoneAfter <s>`: en la pantalla de un banco, «banco conectado» se cierra solo (como «Listo»)
    /// a los segundos dados (reales) desde que aparece. Para grabar desde ANTES del cierre.
    static var connectedDoneAfterSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoConnectedDoneAfter"), let seconds = Double(raw),
              seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 120)
    }

    /// `-MiBancoDemoNoWelcomeMark`: quita el gancho `.launchWelcomeMark()` en la bienvenida para ver en rojo la prueba
    /// del aterrizaje de la marca del primer arranque.
    static var skipsWelcomeMarkHook: Bool { isActive && arguments.contains("-MiBancoDemoNoWelcomeMark") }

    /// `-MiBancoDemoOldSubscriptionRoll`: deja los totales de Suscripciones con `length: nil` (`.brief`) en vez de
    /// `.seconds(0.45)`, para ver en rojo la prueba de 16.2.
    static var oldSubscriptionRoll: Bool { isActive && arguments.contains("-MiBancoDemoOldSubscriptionRoll") }

    /// `-MiBancoDemoRollTiming`: expone la duración real (ms) calculada por `RollingDigits.roll` en Suscripciones.
    static var exposesRollTiming: Bool { isActive && arguments.contains("-MiBancoDemoRollTiming") }

    /// `-MiBancoDemoKeepFocusOnEyeClose`: no suelta el foco al cerrar el ojo en Ajustes, para ver en rojo la
    /// comprobación del teclado de N-1.
    static var keepsFocusOnEyeClose: Bool { isActive && arguments.contains("-MiBancoDemoKeepFocusOnEyeClose") }
}
#endif
