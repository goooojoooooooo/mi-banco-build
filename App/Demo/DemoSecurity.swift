#if DEBUG
import Foundation

// Banderas de demo para pruebas y ráfagas de Seguridad Fase 2 (solo DEBUG, no existen en Release).
extension DemoMode {
    /// `-MiBancoDemoNoPasscode`: simula un iPhone sin código ni Face ID en `LockView` (`SEC-08`).
    /// Mantiene el bloqueo delante sin desbloquear en silencio hasta que el usuario pulsa desactivar a conciencia.
    static var simulatesNoPasscode: Bool { isActive && arguments.contains("-MiBancoDemoNoPasscode") }

    /// `-MiBancoDemoCloseEyeWhenSpeaking <s>`: cierra el ojo `s` segundos después de empezar a hablar `BriefingSpeaker`
    /// (`SEC-13`), para verificar en pruebas de interfaz que la voz se para de inmediato.
    static var closeEyeWhenSpeakingSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoCloseEyeWhenSpeaking"),
              let seconds = Double(raw), seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoCloseEyeWhenFocused <s>`: cierra el ojo `s` segundos después de enfocar un campo de importe en
    /// `PositionDetailSheet` o `AccountsView` (`SEC-05`), para comprobar que suelta el foco sin animación y oculta la cifra.
    static var closeEyeWhenFocusedSeconds: Double? {
        guard isActive, let raw = value(after: "-MiBancoDemoCloseEyeWhenFocused"),
              let seconds = Double(raw), seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, 60)
    }

    /// `-MiBancoDemoResetLogoDefault`: borra la clave `logoDownloads` al arrancar la app en pruebas de interfaz
    /// para comprobar el valor por defecto en instalación limpia (`SEC-07`).
    static var resetsLogoDownloadsDefault: Bool { isActive && arguments.contains("-MiBancoDemoResetLogoDefault") }
}
#endif
