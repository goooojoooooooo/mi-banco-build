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
