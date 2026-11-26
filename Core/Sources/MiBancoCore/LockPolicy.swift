import Foundation

/// Decisión pura del bloqueo al comprobar si el iPhone tiene código o biometría (`SEC-08`).
/// Jamás desbloquea en silencio cuando no hay código ni Face ID configurado.
public enum LockAvailabilityDecision: Equatable, Sendable {
    /// El sistema puede autenticar al dueño (Face ID, Touch ID o código del iPhone).
    case evaluateDeviceAuth
    /// El iPhone no tiene código ni biometría: mantener bloqueado con aviso claro y opción consciente de desactivar.
    case requirePasscodeSetup
}

/// Estado visual de `LockView` frente a la disponibilidad de autenticación del sistema (`SEC-08`).
public enum LockScreenMode: Equatable, Sendable {
    case authenticate
    case noPasscode
}

/// Política pura de `LockView` (`SEC-08`): decide si autenticar o bloquear con aviso sin desbloquear en silencio.
public enum LockAuthPolicy {
    /// Mensaje exacto cuando el iPhone no tiene código ni Face ID.
    public static var noPasscodeMessage: String {
        "Para proteger \(appDisplayName), pon un código en el iPhone (Ajustes > Face ID y código)"
    }

    /// Título del botón para desactivar el bloqueo a conciencia cuando el iPhone no tiene código.
    public static var disableLockButtonTitle: String {
        "Desactivar bloqueo de \(appDisplayName)"
    }

    /// Decide la acción según si `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication, ...)` devuelve `true`.
    public static func decision(canEvaluateDeviceAuth: Bool) -> LockAvailabilityDecision {
        canEvaluateDeviceAuth ? .evaluateDeviceAuth : .requirePasscodeSetup
    }

    /// Traduce la decisión al estado visual del bloqueo.
    public static func screenMode(for decision: LockAvailabilityDecision) -> LockScreenMode {
        switch decision {
        case .evaluateDeviceAuth: .authenticate
        case .requirePasscodeSetup: .noPasscode
        }
    }

    /// Nunca se permite desbloquear en silencio.
    public static func allowsSilentUnlock(canEvaluateDeviceAuth: Bool) -> Bool {
        false
    }
}
