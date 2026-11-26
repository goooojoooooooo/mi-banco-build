#if DEBUG
import Foundation
import SwiftUI

// Banderas de demo de movimiento del marco y las hojas (arranque, pestañas, detalle, resumen, aviso dentro de la app).
// Dueño: la línea C «Marco y hojas» (fase B). Nadie más edita este fichero.
// Cada bandera usa `DemoMode.arguments` o `DemoMode.value(after:)` (`DemoMode.swift` no se toca).
extension DemoMode {
    /// `-MiBancoDemoLaunchHold <s>`: el arranque (o las piezas del bloqueo) espera estos segundos reales, en negro, antes
    /// de empezar. Es para grabarlo desde su primer fotograma: una prueba tarda varios segundos en poder hacer la primera
    /// captura, y así sabe cuándo empieza (`LaunchProbe.startsAt`). Solo retrasa el dibujo; como mucho 60 s.
    static var launchHoldSeconds: Double {
        guard isActive, let seconds = value(after: "-MiBancoDemoLaunchHold").flatMap(Double.init), seconds.isFinite else {
            return 0
        }
        return min(max(seconds, 0), 60)
    }

    /// `-MiBancoDrawnText`: cada importe del kit pone como valor de accesibilidad lo que tiene DIBUJADO (cifra, dígitos
    /// al azar del barajado o máscara), para las pruebas de privacidad. Sin la bandera no cambia nada.
    static var exposesDrawnText: Bool { isActive && arguments.contains("-MiBancoDrawnText") }

    /// `-MiBancoDemoAutoCloseDetail <s>`: la hoja del movimiento se cierra sola a los `s` segundos reales de abrirse
    /// (para grabar su cierre desde antes; m-4). Como mucho 60 s.
    static var autoCloseDetailSeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoAutoCloseDetail").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoRouteChange <s>`: a los `s` segundos de empezar a leer el resumen, se simula que se desconectan los
    /// auriculares (I-6: la voz se para). Como mucho 60 s.
    static var routeChangeSeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoRouteChange").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoCloseEyeAfter <s>`: a los `s` segundos de arrancar, el ojo se cierra solo (para grabar el cierre
    /// sobre una cifra que rueda). Como mucho 60 s.
    static var closeEyeAfterSeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoCloseEyeAfter").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoLockFadeWithoutDelay`: el defecto de antes de la ronda 1 (el bloqueo se funde a la vez que se apagan
    /// sus textos), solo para que la prueba demuestre que lo ve (ronda 2, N-1).
    static var lockFadeWithoutDelay: Bool { isActive && arguments.contains("-MiBancoDemoLockFadeWithoutDelay") }

    /// `-MiBancoDemoHideTabsDuringCurtain`: las pestañas desaparecen 0,2 s a mitad del tapado de la barra (N-9).
    static var hidesTabsDuringCurtain: Bool { isActive && arguments.contains("-MiBancoDemoHideTabsDuringCurtain") }

    /// `-MiBancoDemoNotMineFails`: «No es mío» desde el aviso dentro de la app no se guarda (M-2: el aviso se queda y lo
    /// dice).
    static var notMineFails: Bool { isActive && arguments.contains("-MiBancoDemoNotMineFails") }

    /// `-MiBancoDemoBriefingDelay <s>`: el resumen tarda `s` segundos en llegar a la hoja (I-5 / m-13: la entrada empieza
    /// cuando llega). Como mucho 60 s.
    static var briefingDelaySeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoBriefingDelay").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoSharedEyeOpposite`: la copia del ojo en la suite compartida (de la demo) dice lo contrario del ojo
    /// (N-3: los avisos y la Live Activity no deben leerla).
    static var writesOppositeSharedEye: Bool { isActive && arguments.contains("-MiBancoDemoSharedEyeOpposite") }

    /// `-MiBancoDemoTabSwitch <s>`: a los `s` segundos reales de arrancar, la app cambia sola de Inicio a Gasto (para
    /// grabar la entrada de la pestaña desde ANTES del cambio: un toque de la prueba espera a que la app quede quieta).
    static var tabSwitchSeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoTabSwitch").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 120)
    }

    /// `-MiBancoDemoUnlockInactive <s>`: tras el desbloqueo en frío de la demo, la carcasa hace como que la escena sigue
    /// inactiva estos segundos reales y luego vuelve a activa. Es el orden de Face ID en el iPhone (el éxito llega con la
    /// escena aún inactiva), que el simulador no reproduce. nil = sin simular.
    static var unlockInactiveSeconds: Double? {
        guard isActive, let seconds = value(after: "-MiBancoDemoUnlockInactive").flatMap(Double.init), seconds.isFinite,
              seconds > 0 else { return nil }
        return min(seconds, 60)
    }
}

/// Solo DEBUG: lo que ha hecho el arranque, para que las pruebas de toque lo lean (no hay otra forma fiable de saber, desde
/// fuera, cuánto tardó la capa en dejar pasar los toques o si volvió a montarse al volver de segundo plano). Solo cuenta
/// y apunta tiempos: no decide nada y en Release no existe.
@MainActor @Observable final class LaunchProbe {
    static let shared = LaunchProbe()

    /// Veces que se ha montado la capa del arranque (la de sin bloqueo).
    var launches = 0
    /// «piezas» o «fundido», el estilo del último arranque.
    var style = "-"
    /// Veces que un toque la ha saltado.
    var skips = 0
    /// Milisegundos reales desde que empezó hasta que dejó pasar los toques a Inicio, y hasta que se quitó.
    var freeAfterMs: Int?
    var finishedAfterMs: Int?
    /// Veces que el bloqueo ha montado las piezas (arranque en frío) y veces que ha salido con la marca quieta.
    var lockPlays = 0
    var lockStatic = 0
    /// Veces que la marca ha volado a su ranura tras desbloquear.
    var exits = 0
    /// Veces que Inicio ha recibido la orden de montarse por capas (`ShellState.revealToken`).
    var reveals = 0
    /// Cómo estaba la marca del bloqueo en el instante del último desbloqueo, ANTES de que el bloqueo la dejara
    /// terminada: «piezas» (aún se montaba), «completa» o «fija» (re-bloqueo).
    var lockMarkBeforeLeaving = "-"
    /// Cómo dejó el bloqueo su marca al irse en el último desbloqueo (lo que recoge la marca que vuela): tiene que ser
    /// siempre «completa».
    var lockMarkLeaving = "-"
    /// El bloqueo, ya desbloqueado, se está fundiendo (`ShellState.lockFading`): Inicio aún no recibe toques.
    var lockFading = false
    /// Hay un bloqueo fundiéndose que sigue dibujando su marca (no la entregó a la que vuela).
    var lockFadesWithItsMark = false
    /// Veces que la marca ha echado a volar con un bloqueo aún fundiéndose y dibujando la suya: dos marcas a la vista.
    var doubleMarks = 0
    /// Cuándo empieza (o empezó) el último arranque o montaje del bloqueo: segundos desde 1970, para que una prueba que
    /// lo graba sepa cuándo hacer la primera captura.
    var startsAt: Double?
    /// Qué parte de la marca de la barra de Inicio NO se dibuja ahora porque la lleva la que vuela
    /// (`LaunchAnchor.flying`): «-», «marca» o «marcaYNombre».
    var brandFlying = "-"
    /// Veces que un desbloqueo ha llegado con la app en segundo plano y no se ha aceptado (`ShellState.acceptsUnlock`).
    var refusedUnlocks = 0
    /// Veces que la marca que vuela tras desbloquear ha aterrizado en la ranura de Inicio (entera, hasta el final).
    var landings = 0
    /// Cuándo se creó la app (segundos desde 1970) y cuántos milisegundos pasaron hasta montarse la capa del arranque:
    /// lo que el arranque tarda en EMPEZAR, que la propia capa no puede medir.
    var appInitAt: Double?
    var mountedAfterMs: Int?
    /// Veces que la app ha visto su escena pasar a segundo plano, y la fase de ahora («activa», «inactiva», «fondo»):
    /// una prueba que manda la app atrás sabe así si de verdad llegó (la vista desde fuera no basta: con dos simuladores
    /// en paralelo el gesto de Inicio puede llegar tarde o no llegar).
    var backgrounds = 0
    var scene = "-"
    /// Si el bloqueo que se está quitando sigue a la vista de VoiceOver: «oculto» desde el instante del desbloqueo
    /// (es el mismo valor que recibe su `accessibilityHidden`), «visible» mientras está puesto, «-» sin bloqueo aún.
    var lockVoiceOver = "-"
    /// La ranura de la marca de Inicio está escondida porque el bloqueo se funde con la suya (solo fundidos).
    var slotHiddenByLock = false
    /// I-2: lo que dice la suite compartida del ojo tras la última escritura de la app («cerrado», «abierto», «-»).
    var sharedEye = "-"
    /// B2: la línea del resumen que suena ahora («-» si ninguna).
    var spokenLine = "-"
    /// Lote final: la línea del resumen que DIBUJA su resalte ahora («-» si ninguna).
    var drawnLine = "-"
    /// N-3: el ojo con el que se compondría ahora un aviso (texto y carga) y la Live Activity («cerrado»/«abierto»).
    var alertEye = "-"
    var activityEye = "-"
    /// N-2: los botones del aviso dentro de la app reciben toques («1») o no («0»).
    var bannerActions = "0"
    /// Lote final: cuándo se tapó y cuándo empezó a destaparse la barra de pestañas en el último montaje (s desde 1970).
    var tabBarCoveredAt: Double?
    var tabBarUncoveredAt: Double?
    /// C8: cuántas tarjetas han aterrizado en la cabecera de su banco.
    var cardLandings = 0
    /// Ronda 1: «No es mío» desde el aviso que no se ha podido guardar (M-2) y cuándo se han ido los textos del bloqueo
    /// y empezó su fundido (I-1).
    var notMineFailures = 0
    /// Ronda 1: cuándo se cerrará solo el ojo (`-MiBancoDemoCloseEyeAfter`).
    var eyeClosesAt: Double?
    /// I-4 (ronda 1): cuándo se cerrará sola la hoja del movimiento (`-MiBancoDemoAutoCloseDetail`).
    var detailCloseAt: Double?
    /// Ronda 2 (N-1): primer fotograma dibujado con el nombre del bloqueo apagado y primer fotograma en que el bloqueo
    /// empieza a irse. No observados: los escribe el dibujo; salen en la sonda en su siguiente lectura.
    @ObservationIgnored var lockTextsGoneAt: Double?
    @ObservationIgnored var lockFadeBeganAt: Double?
    /// Solo se apuntan tras un desbloqueo (no en el montaje del bloqueo).
    @ObservationIgnored var lockFadeArmed = false
    /// Lote final: pagos llegados (`model.arrival`) y cuántos con el bloqueo delante.
    var arrivals = 0
    var arrivalsUnderLock = 0
    /// N-2: el aviso se está desplegando (empezó y aún no ha terminado).
    var bannerUnfolding = false
    /// Cuándo cambia sola de pestaña la demo (`-MiBancoDemoTabSwitch`), en segundos desde 1970.
    var tabSwitchAt: Double?

    /// I-2: el estado de la Live Activity se lee igual con y sin la clave nueva `hidden` (un estado viejo, de antes,
    /// no la lleva): «ok» si los dos se decodifican y el viejo queda con `hidden` nil (ojo abierto, como siempre).
    static let legacyActivityStateDecodes: String = {
        let old = #"{"bank":"rev","estimated":false,"lastAmountCents":-1250,"kind":"payment","title":"Mercadona"}"#
        let new = #"{"bank":"rev","estimated":false,"lastAmountCents":-1250,"kind":"payment","title":"Mercadona","hidden":true}"#
        let decoder = JSONDecoder()
        typealias State = MovementActivityAttributes.ContentState
        guard let a = try? decoder.decode(State.self, from: Data(old.utf8)),
              let b = try? decoder.decode(State.self, from: Data(new.utf8)) else { return "falla" }
        return a.hidden == nil && b.hidden == true ? "ok" : "mal"
    }()

    /// «arranques=1;estilo=piezas;saltos=0;libre=963;fin=1344;bloqueoPiezas=0;bloqueoQuieto=0;salidas=0;empieza=1764000000.123»
    var summary: String {
        [
            "arranques=\(launches)", "estilo=\(style)", "saltos=\(skips)",
            "libre=\(freeAfterMs.map { String($0) } ?? "-")", "fin=\(finishedAfterMs.map { String($0) } ?? "-")",
            "bloqueoPiezas=\(lockPlays)", "bloqueoQuieto=\(lockStatic)", "salidas=\(exits)", "montajes=\(reveals)",
            "marcaAntes=\(lockMarkBeforeLeaving)", "marcaAlIrse=\(lockMarkLeaving)",
            "fundido=\(lockFading ? 1 : 0)", "marcasDobles=\(doubleMarks)",
            "ranura=\(brandFlying)", "aterrizajes=\(landings)", "rechazados=\(refusedUnlocks)",
            "previo=\(mountedAfterMs.map { String($0) } ?? "-")",
            "fondos=\(backgrounds)", "escena=\(scene)", "vozBloqueo=\(lockVoiceOver)",
            "ranuraBloqueo=\(slotHiddenByLock ? 1 : 0)",
            "ojoCompartido=\(sharedEye)", "estadoViejo=\(Self.legacyActivityStateDecodes)", "lineaLeida=\(spokenLine)", "lineaDibujada=\(drawnLine)", "accionesAviso=\(bannerActions)", "desplegandoAviso=\(bannerUnfolding ? 1 : 0)",
            "llegadas=\(arrivals)", "aterrizajesTarjeta=\(cardLandings)",
            "ojoCierraEn=\(eyeClosesAt.map { String(format: "%.3f", $0) } ?? "-")", "cierreDetalle=\(detailCloseAt.map { String(format: "%.3f", $0) } ?? "-")", "noEsMioFallos=\(notMineFailures)",
            "textosFuera=\(lockTextsGoneAt.map { String(format: "%.3f", $0) } ?? "-")",
            "fundidoBloqueo=\(lockFadeBeganAt.map { String(format: "%.3f", $0) } ?? "-")",
            "barraTapada=\(tabBarCoveredAt.map { String(format: "%.3f", $0) } ?? "-")",
            "barraDestapada=\(tabBarUncoveredAt.map { String(format: "%.3f", $0) } ?? "-")", "llegadasBloqueo=\(arrivalsUnderLock)",
            "ojoAviso=\(alertEye)", "ojoActividad=\(activityEye)",
            "cambioPestana=\(tabSwitchAt.map { String(format: "%.3f", $0) } ?? "-")",
            "empieza=\(startsAt.map { String(format: "%.3f", $0) } ?? "-")",
        ].joined(separator: ";")
    }
}

/// El elemento invisible que publica `LaunchProbe.summary` (identificador `launch-probe`). Va DEBAJO de todo.
struct LaunchProbeView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("launch-probe")
            .accessibilityValue(LaunchProbe.shared.summary)
            .allowsHitTesting(false)
    }
}
#endif
