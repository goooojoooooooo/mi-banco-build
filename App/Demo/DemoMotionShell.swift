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
    /// Cómo estaba la marca del bloqueo al empezar a fundirse en el último desbloqueo: «completa» o «piezas».
    var lockMarkAtUnlock = "-"
    /// Cuándo empieza (o empezó) el último arranque o montaje del bloqueo: segundos desde 1970, para que una prueba que
    /// lo graba sepa cuándo hacer la primera captura.
    var startsAt: Double?

    /// «arranques=1;estilo=piezas;saltos=0;libre=963;fin=1344;bloqueoPiezas=0;bloqueoQuieto=0;salidas=0;empieza=1764000000.123»
    var summary: String {
        [
            "arranques=\(launches)", "estilo=\(style)", "saltos=\(skips)",
            "libre=\(freeAfterMs.map { String($0) } ?? "-")", "fin=\(finishedAfterMs.map { String($0) } ?? "-")",
            "bloqueoPiezas=\(lockPlays)", "bloqueoQuieto=\(lockStatic)", "salidas=\(exits)", "montajes=\(reveals)",
            "marcaAlDesbloquear=\(lockMarkAtUnlock)",
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
