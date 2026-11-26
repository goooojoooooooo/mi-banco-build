import Foundation

/// Fase de la conexión de un banco. Es lo que la pantalla de Ajustes muestra.
public enum ConnectPhase: Equatable, Sendable {
    case idle
    case opening(BankID)
    case waitingForBank(BankID)
    case finishing(BankID)
    case connected(BankID)
    case needsResume(BankID)
    case failed(BankID, String)
    case chooseASPSP(BankID, [EBASPSP])

    /// Hay un trámite en marcha: abriendo, esperando al banco o terminando.
    public var isActive: Bool {
        switch self {
        case .opening, .waitingForBank, .finishing: true
        default: false
        }
    }
}

/// Lo que el Llavero dice de la conexión a medias cuando llega una vuelta del banco.
public enum PendingCheck: Equatable, Sendable {
    case none
    case valid(BankID)
    case expired(BankID)
}

public enum ConnectEvent: Equatable, Sendable {
    case start(BankID)
    case needsChoice(BankID, [EBASPSP])
    case webOpened(BankID)
    /// La persona cerró la hoja web del banco (no la cerró la app).
    case webDismissedByUse
    case callback(PendingCheck)
    /// La vuelta ya comprobada contra el `state` guardado. Una vuelta que no se puede verificar (`state` falso o ausente,
    /// forma rara) o sin intento en el Llavero que llega por `onOpenURL` se ignora sin tocar nada (la puede mandar cualquie
    /// app); si llega por el propio cierre de la hoja web (`fromWebSession: true`), la hoja ya se ha cerrado y el flujo
    /// termina en `.failed(bank, foreignLink)` para no dejar `.waitingForBank` colgado (R43).
    case callbackReceived(PendingCheck, AuthCallbackResult, fromWebSession: Bool = false)
    /// La persona desconecta ese banco: el trámite de ese banco, esté donde esté (también terminando), se abandona.
    case disconnected(BankID)
    case succeeded(BankID)
    case failed(BankID, String)
    case sceneBackground(Date)
    case sceneActive(Date)
    /// Cancelación explícita.
    case cancel
    case resume(pending: PendingCheck, hasAuthURL: Bool)
    case reset
    /// «Olvidar clave y conexiones» reinicia el flujo desde cualquier fase (U42).
    case forgetAll
}

/// Lo único que la app ejecuta.
public enum ConnectAction: Equatable, Sendable {
    case cancelWebSession
    case deletePending
    case processCallback(BankID)
    case openWeb(BankID)
    case restart(BankID)
}

/// Qué pasa con la conexión al bloquear, cambiar de escena, agotar el plazo o recibir la vuelta del banco.
/// Función pura de (estado, evento): no toca el Llavero ni la red. Bloquear la app NO es una entrada: el bloqueo
/// no toca la conexión; la hoja web solo enseña la página del banco y una vuelta con la app bloqueada se procesa igual.
public struct ConnectFlow: Equatable, Sendable {
    /// Tiempo fuera de la app a partir del cual se corta la hoja web.
    public static let awayLimit: TimeInterval = 300

    public private(set) var phase: ConnectPhase = .idle
    private var backgroundedAt: Date?

    public init() {}

    @discardableResult
    public mutating func handle(_ event: ConnectEvent) -> [ConnectAction] {
        switch event {
        case .start(let bank):
            guard !phase.isActive else { return [] }
            phase = .opening(bank)
            return []

        case .needsChoice(let bank, let list):
            guard phase == .opening(bank) else { return [] }
            phase = .chooseASPSP(bank, list)
            return []

        case .webOpened(let bank):
            guard phase == .opening(bank) else { return [] }
            phase = .waitingForBank(bank)
            return []

        case .webDismissedByUser:
            switch phase {
            case .opening(let bank), .waitingForBank(let bank):
                phase = .failed(bank, ConnectMessage.cancelled)
                return [.deletePending]
            default:
                return []
            }

        case let .callbackReceived(check, result, fromWebSession):
            switch result {
            case .code, .denied:
                if check == .none, fromWebSession {
                    switch phase {
                    case .opening(let bank), .waitingForBank(let bank):
                        phase = .failed(bank, ConnectMessage.foreignLink)
                        return [.deletePending]
                    default:
                        return []
                    }
                }
                return handle(.callback(check))
            case .stateMismatch, .malformed:
                guard fromWebSession else { return [] }
                switch phase {
                case .opening(let bank), .waitingForBank(let bank):
                    phase = .failed(bank, ConnectMessage.foreignLink)
                    return [.deletePending]
                default:
                    return []
                }
            }

        case .disconnected(let bank):
            let mine: Bool
            switch phase {
            case .idle: mine = false
            case .opening(let b), .waitingForBank(let b), .finishing(let b), .connected(let b), .needsResume(let b),
                 .failed(let b, _), .chooseASPSP(let b, _):
                mine = b == bank
            }
            guard mine else { return [] }
            let wasActive = phase.isActive
            phase = .idle
            return wasActive ? [.cancelWebSession, .deletePending] : [.deletePending]

        case .callback(let check):
            // Ya se está terminando: la segunda vuelta no hace nada.
            if case .finishing = phase { return [] }
            switch check {
            case .none:
                return []
            case .valid(let bank):
                phase = .finishing(bank)
                return [.cancelWebSession, .processCallback(bank)]
            case .expired(let bank):
                phase = .failed(bank, ConnectMessage.tooSlow)
                return [.deletePending, .cancelWebSession]
            }

        case .succeeded(let bank):
            guard phase == .finishing(bank) else { return [] }
            phase = .connected(bank)
            return []

        case .failed(let bank, let message):
            switch phase {
            case .opening, .waitingForBank, .finishing, .needsResume:
                phase = .failed(bank, message)
                return [.deletePending, .cancelWebSession]
            default:
                return []
            }

        case .sceneBackground(let at):
            backgroundedAt = backgroundedAt ?? at
            return []

        case .sceneActive(let at):
            let since = backgroundedAt
            backgroundedAt = nil
            guard let since, at.timeIntervalSince(since) >= Self.awayLimit else { return [] }
            switch phase {
            case .opening(let bank), .waitingForBank(let bank):
                phase = .needsResume(bank)
                return [.cancelWebSession]
            default:
                return []
            }

        case .cancel:
            switch phase {
            case .opening:
                // U50: antes de abrir la hoja web no tiene sentido preguntar si ya lo aprobó.
                phase = .idle
                return [.cancelWebSession, .deletePending]
            case .waitingForBank(let bank):
                phase = .needsResume(bank)
                return [.cancelWebSession]
            default:
                return []
            }

        case .resume(let check, let hasAuthURL):
            guard case .needsResume(let bank) = phase else { return [] }
            if check == .valid(bank), hasAuthURL {
                phase = .opening(bank)
                return [.openWeb(bank)]
            }
            return [.restart(bank)]

        case .reset:
            switch phase {
            case .waitingForBank, .finishing:
                return []
            default:
                phase = .idle
                return [.deletePending]
            }

        case .forgetAll:
            // U42: desde cualquier fase vuelve a .idle; cancela la hoja web si estaba abierta o abriéndose.
            let hasWeb: Bool
            switch phase {
            case .opening, .waitingForBank: hasWeb = true
            default: hasWeb = false
            }
            phase = .idle
            return hasWeb ? [.cancelWebSession, .deletePending] : [.deletePending]
        }
    }
}

/// Secuencia de «Olvidar clave y conexiones» (U43): borra lo local antes que la red.
public func forgetEverythingPlan(
    readSessionIDs: @Sendable () async -> [String],
    deleteLocal: @Sendable () async -> Void,
    unlinkLedger: @Sendable () async -> Void,
    deleteRemote: @Sendable (String) async -> Void
) async {
    let ids = await readSessionIDs()
    await deleteLocal()
    await unlinkLedger()
    for id in ids {
        if Task.isCancelled { break }
        await deleteRemote(id)
    }
}

/// Secuencia de «Desconectar» un banco (U78, B-M9): el mismo orden que «Olvidar». Primero lee la sesión, borra la sesión del
/// Llavero y el enlace del libro en el iPhone, y SOLO DESPUÉS avisa al banco (mejor esfuerzo; con la red colgada lo local ya
/// no está).
public func disconnectBankPlan(
    readSessionID: @Sendable () async -> String?,
    deleteLocal: @Sendable () async -> Void,
    unlinkLedger: @Sendable () async -> Void,
    deleteRemote: @Sendable (String) async -> Void
) async {
    let id = await readSessionID()
    await deleteLocal()
    await unlinkLedger()
    if let id, !Task.isCancelled {
        await deleteRemote(id)
    }
}

/// Error al guardar las credenciales de Enable Banking (U53).
public enum BankingCredentialErrorKind: Equatable, Sendable {
    case invalidKey, keychain
}

/// Mensaje que ve el dueño al fallar el guardado de la clave de Enable Banking (U53).
public func bankingCredentialMessage(_ kind: BankingCredentialErrorKind) -> String {
    switch kind {
    case .invalidKey: return "No es una clave válida. Elige el archivo .pem de Enable Banking."
    case .keychain: return "No se pudo guardar la clave en este iPhone. Inténtalo de nuevo."
    }
}

/// Textos de error de la conexión, exactos. Nunca texto crudo de la API.
public enum ConnectMessage {
    public static let cancelled = "Has cancelado en el banco. No se ha conectado nada."
    public static let foreignLink = "Este enlace no es de tu conexión. Empieza de nuevo desde Ajustes."
    public static let tooSlow = "El banco tardó demasiado. Vuelve a intentarlo."
    public static let redirectNotAllowed =
        "Enable Banking no reconoce la dirección de vuelta. Revisa el paso 2 de la guía."
    public static let offline = "Sin conexión a internet."
    public static let missingCredentials = "Falta la clave de tu banco. Añádela en Ajustes › Bancos."
    public static let storeFailed = "No se pudo guardar la conexión en este iPhone. Vuelve a intentarlo."

    public static func noEuroAccount(_ bank: BankID) -> String {
        "No hemos encontrado una cuenta en euros en \(bank.displayName)."
    }
}

/// Mensaje de una vuelta que no trae código; `nil` si trae uno.
public func connectMessage(for result: AuthCallbackResult) -> String? {
    switch result {
    case .code: nil
    case .denied: ConnectMessage.cancelled
    case .stateMismatch, .malformed: ConnectMessage.foreignLink
    }
}

/// Mensaje de un fallo al hablar con Enable Banking.
public func connectMessage(for error: Error) -> String {
    switch error as? BankingClientError {
    case .offline: ConnectMessage.offline
    case .api(_, let code) where code == "REDIRECT_URI_NOT_ALLOWED": ConnectMessage.redirectNotAllowed
    default: ConnectMessage.tooSlow
    }
}

/// Solo `mibanco://cb…` es de este flujo; cualquier otra dirección se ignora sin ruido.
public func isBankCallbackURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == BankingConstants.callbackScheme && url.host?.lowercased() == "cb"
}

/// Puerta de entrada para `onOpenURL` (`SEC-11`): solo se acepta `mibanco://cb` si existe un intento pendiente.
/// Sin intento pendiente (`.none`), la URL se ignora de inmediato sin lanzar flujo ni error.
public func shouldHandleIncomingBankCallback(_ url: URL, pending: PendingCheck) -> Bool {
    guard isBankCallbackURL(url) else { return false }
    switch pending {
    case .none: return false
    case .valid, .expired: return true
    }
}

/// Revolut e imagin siempre; Trade Republic solo si una lista en memoria lo encontró.
public func canConnectBank(_ bank: BankID, cachedList: [EBASPSP]?) -> Bool {
    switch bank {
    case .rev, .ima: true
    case .tr: cachedList.flatMap { matchASPSP(for: .tr, in: $0) } != nil
    }
}

/// Qué hacer con la sesión del Llavero cuando falla la escritura del libro tras guardar la nueva (R: éxito atómico).
public enum SessionRollback: Equatable, Sendable {
    /// Había una sesión que funcionaba: se vuelve a poner.
    case restore(StoredSession)
    /// No había ninguna: se borra la nueva.
    case deleteNew
}

public func rollbackAfterLedgerFailure(previous: StoredSession?) -> SessionRollback {
    previous.map(SessionRollback.restore) ?? .deleteNew
}

/// Id de la sesión REMOTA vieja que sobra tras reconectar con éxito (la nueva ya está guardada): `nil` si no había o si
/// es la misma.
public func staleRemoteSessionID(previous: StoredSession?, new: StoredSession) -> String? {
    guard let previous, previous.sessionID != new.sessionID else { return nil }
    return previous.sessionID
}
