import Foundation

/// Decisión pura del bloqueo al comprobar si el iPhone tiene código o biometría (`SEC-08`).
/// Jamás desbloquea en silencio cuando no hay código ni Face ID configurado.
public enum LockAvailabilityDecision: Equatable, Sendable {
    /// El sistema puede autenticar al dueño (Face ID, Touch ID o código del iPhone).
    case evaluateDeviceAuth
    /// El iPhone no tiene código ni biometría: mantener bloqueado con aviso claro y opción consciente de desactivar.
    case requirePasscodeSetup
    /// `canEvaluatePolicy` falló por otro motivo (no es «sin código»): se queda el botón «Desbloquear» para reintentar.
    /// Jamás se ofrece desactivar el bloqueo por un fallo pasajero.
    case retryAuthentication
}

/// Lo que contesta el sistema al preguntar si puede autenticar al dueño (`LAContext.canEvaluatePolicy`), sin importar
/// `LocalAuthentication` aquí.
public enum DeviceAuthAvailability: Equatable, Sendable {
    /// Face ID, Touch ID o código del iPhone disponibles.
    case available
    /// El error fue exactamente `LAError.passcodeNotSet`: el iPhone no tiene código.
    case passcodeNotSet
    /// Cualquier otro motivo por el que no se pudo evaluar (error pasajero o inesperado).
    case unavailable
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

    /// Texto de la confirmación al desactivar el bloqueo.
    public static var disableConfirmationTitle: String { "¿Desactivar el bloqueo de \(appDisplayName)?" }
    public static var disableConfirmationMessage: String {
        "\(appDisplayName) se abrirá sin protección: cualquiera que tenga tu iPhone podrá ver tu dinero."
    }
    public static var disableConfirmationButtonTitle: String { "Desactivar y abrir sin protección" }

    /// Decide la acción según lo que contestó el sistema. Solo `passcodeNotSet` lleva a la pantalla «sin código».
    public static func decision(for availability: DeviceAuthAvailability) -> LockAvailabilityDecision {
        switch availability {
        case .available: .evaluateDeviceAuth
        case .passcodeNotSet: .requirePasscodeSetup
        case .unavailable: .retryAuthentication
        }
    }

    /// Solo con `evaluateDeviceAuth` se pide Face ID/código; con cualquier otra decisión no se sigue ni se desbloquea.
    public static func proceedsToEvaluate(_ decision: LockAvailabilityDecision) -> Bool {
        decision == .evaluateDeviceAuth
    }

    /// Traduce la decisión al estado visual del bloqueo.
    public static func screenMode(for decision: LockAvailabilityDecision) -> LockScreenMode {
        switch decision {
        case .evaluateDeviceAuth: .authenticate
        case .requirePasscodeSetup: .noPasscode
        case .retryAuthentication: .authenticate
        }
    }

    /// Nunca se permite desbloquear en silencio.
    public static func allowsSilentUnlock(canEvaluateDeviceAuth: Bool) -> Bool {
        false
    }
}

/// Dominio de error de `LocalAuthentication` (`LAError.errorDomain`).
public let lockAuthErrorDomain = "com.apple.LocalAuthentication"

/// Valor numérico de `LAError.passcodeNotSet` (-5). Se fija aquí para clasificar sin importar `LocalAuthentication`;
/// la app lo compara con el sistema real en `LockView.systemDeviceAuth`.
public let lockPasscodeNotSetErrorCode = -5

/// Clasifica el fallo de `canEvaluatePolicy` (SEC-08): solo el dominio de `LocalAuthentication` con `passcodeNotSet`
/// es «sin código»; cualquier otro error, dominio o ausencia de datos es un fallo recuperable (reintentar).
public func lockAvailability(errorDomain: String?, errorCode: Int?) -> DeviceAuthAvailability {
    if errorDomain == lockAuthErrorDomain, errorCode == lockPasscodeNotSetErrorCode { return .passcodeNotSet }
    return .unavailable
}
