import Foundation

public enum SyncTrigger: Sendable { case afterConnect, appOpen, background, manual }

public enum SkipReason: Equatable, Sendable {
    case notConnected, consentExpired, waiting(until: Date), budgetUsed(nextAt: Date), fresh
}

public enum SyncDecision: Equatable, Sendable {
    case fetch(dateFrom: Date, strategy: TransactionStrategy)
    case skip(SkipReason)
}

/// Cuándo se puede consultar cada banco. La app solo ejecuta lo que decide esto.
public enum SyncPolicy {
    /// Consultas automáticas máximas por cada 24 h (el banco permite 4 al día sin que el dueño esté delante).
    public static let perDay = 4
    public static let autoSpacing: TimeInterval = 10_800
    public static let manualSpacing: TimeInterval = 120
    /// Espera tras «demasiadas peticiones».
    public static let backoff: TimeInterval = 21_600
    public static let overlapDays = 7
    public static let firstHistoryDays = 365

    public static func decide(
        _ link: BankLinkInfo?, trigger: SyncTrigger, now: Date, calendar: Calendar, oldestPending: Date? = nil
    ) -> SyncDecision {
        guard let link else { return .skip(.notConnected) }
        if now >= link.consentValidUntil || link.problem == .consentExpired || link.problem == .keyRejected {
            return .skip(.consentExpired)
        }
        if let until = link.backoffUntil, until > now { return .skip(.waiting(until: until)) }
        if trigger == .afterConnect {
            return .fetch(dateFrom: dayStart(daysBefore: firstHistoryDays, of: now, calendar), strategy: .longest)
        }
        let recent = link.fetchLog.filter { now.timeIntervalSince($0) < 24 * 3600 }
        if recent.count >= perDay, let oldest = recent.min() {
            return .skip(.budgetUsed(nextAt: oldest.addingTimeInterval(24 * 3600)))
        }
        switch trigger {
        case .appOpen, .background:
            if let ok = link.lastSuccessAt, now.timeIntervalSince(ok) < autoSpacing { return .skip(.fresh) }
        case .manual:
            if let last = link.lastAttemptAt, now.timeIntervalSince(last) < manualSpacing { return .skip(.fresh) }
        case .afterConnect:
            break
        }
        let base = link.lastSuccessAt.map { calendar.startOfDay(for: $0) }
            ?? dayStart(daysBefore: firstHistoryDays, of: now, calendar)
        var from = calendar.date(byAdding: .day, value: -overlapDays, to: base) ?? base
        // La consulta llega siempre hasta el pendiente más antiguo (sin pasar del máximo): así su registro apuntado
        // vuelve en el lote y un pendiente no se da por desaparecido solo porque la ventana avanzó.
        if let oldestPending {
            let floor = dayStart(daysBefore: firstHistoryDays, of: now, calendar)
            let reach = max(calendar.startOfDay(for: oldestPending), floor)
            if reach < from { from = reach }
        }
        return .fetch(dateFrom: from, strategy: link.historyLoaded ? .standard : .longest)
    }

    private static func dayStart(daysBefore days: Int, of date: Date, _ calendar: Calendar) -> Date {
        let back = calendar.date(byAdding: .day, value: -days, to: date) ?? date
        return calendar.startOfDay(for: back)
    }
}

extension BankLinkInfo {
    public func recordingAttempt(at: Date) -> BankLinkInfo {
        var copy = self
        copy.fetchLog = (fetchLog + [at]).filter { at.timeIntervalSince($0) < 24 * 3600 }
        copy.lastAttemptAt = at
        return copy
    }

    public func recordingSuccess(at: Date) -> BankLinkInfo {
        var copy = self
        copy.lastSuccessAt = at
        copy.problem = nil
        copy.backoffUntil = nil
        copy.historyLoaded = true
        return copy
    }

    /// `.rateLimited` espera 6 h; `.unknown` espera lo que una consulta automática (no se reintenta a toda prisa).
    public func recordingFailure(_ problem: SyncProblem, at: Date) -> BankLinkInfo {
        var copy = self
        copy.problem = problem
        switch problem {
        case .rateLimited: copy.backoffUntil = at.addingTimeInterval(SyncPolicy.backoff)
        case .unknown: copy.backoffUntil = at.addingTimeInterval(SyncPolicy.autoSpacing)
        default: break
        }
        return copy
    }
}

/// Aviso 10 días antes de que caduque el consentimiento, a las 10:00 en el calendario dado (Madrid en la app).
/// `nil` si ese momento ya pasó.
public func consentReminderDate(validUntil: Date, now: Date, calendar: Calendar) -> Date? {
    guard let day = calendar.date(byAdding: .day, value: -10, to: validUntil) else { return nil }
    var parts = calendar.dateComponents([.year, .month, .day], from: day)
    parts.hour = 10
    parts.minute = 0
    parts.second = 0
    guard let at = calendar.date(from: parts), at > now else { return nil }
    return at
}

/// Qué hay que consultar ahora de un banco.
public struct BankFetchPlan: Equatable, Sendable {
    public let bank: BankID
    public let dateFrom: Date
    public let strategy: TransactionStrategy

    public init(bank: BankID, dateFrom: Date, strategy: TransactionStrategy) {
        self.bank = bank
        self.dateFrom = dateFrom
        self.strategy = strategy
    }
}

/// Bancos a consultar ahora, en orden estable (el de `BankID.allCases`). La app solo ejecuta esta lista.
public func banksToFetch(
    links: [BankID: BankLinkInfo], trigger: SyncTrigger, now: Date, calendar: Calendar,
    oldestPending: [BankID: Date] = [:]
) -> [BankFetchPlan] {
    BankID.allCases.compactMap { bank in
        guard case let .fetch(dateFrom, strategy) = SyncPolicy.decide(
            links[bank], trigger: trigger, now: now, calendar: calendar, oldestPending: oldestPending[bank])
        else { return nil }
        return BankFetchPlan(bank: bank, dateFrom: dateFrom, strategy: strategy)
    }
}

/// Convierte un error de la consulta en el problema que se muestra y se recuerda.
public func syncProblem(for error: Error) -> SyncProblem {
    if let known = error as? BankingClientError {
        switch known {
        case let .api(problem, _): return problem
        case .offline: return .offline
        case .tooManyPages, .badResponse: return .unknown
        }
    }
    return error is URLError ? .offline : .unknown
}

/// ¿Es un fallo del banco o de la red (se anota, gasta un intento y puede poner espera)? Un fallo local (Llavero sin
/// desbloquear tras reiniciar, credenciales ilegibles, disco) o una cancelación no lo es: no se anota nada.
public func isBankFailure(_ error: Error) -> Bool {
    error is BankingClientError || error is URLError
}

/// Por qué no se pudo leer la sesión guardada del Llavero.
public enum SessionReadFailure: Equatable, Sendable {
    /// El móvil aún no se ha desbloqueado tras reiniciar (`errSecInteractionNotAllowed`): pasa solo, no se anota nada.
    case deviceLocked
    /// Dato ilegible o cualquier otro error del Llavero: no se arregla solo; se trata como sesión que falta.
    case unreadable
}

/// `true` = se anota como fallo de consentimiento (hay que renovar); `false` = sin resultado, se reintenta más tarde.
public func recordsSessionReadFailure(_ failure: SessionReadFailure) -> Bool {
    failure == .unreadable
}

/// Qué hacer con el fallo de una consulta una vez terminada, según si la conexión sigue siendo la misma.
public enum SyncFailureAction: Equatable, Sendable {
    /// Anotar el fallo en la conexión y, si el problema es de consentimiento, borrar la sesión del Llavero.
    case record(deleteSession: Bool)
    /// Una reconexión o renovación ocurrió mientras tanto (otra sesión o conexión más nueva que el intento): el fallo
    /// es de la sesión vieja. No se anota nada ni se toca el Llavero.
    case drop
}

/// `startedSessionID`: la sesión con la que arrancó la consulta (nil si no había). `currentSessionID`: la que hay ahora
/// en el Llavero. `link`: la conexión ahora en el libro. `attemptAt`: cuándo se anotó el intento.
public func syncFailureAction(
    problem: SyncProblem, startedSessionID: String?, currentSessionID: String?, link: BankLinkInfo?, attemptAt: Date
) -> SyncFailureAction {
    guard let link, link.connectedAt <= attemptAt, startedSessionID == currentSessionID else { return .drop }
    return .record(deleteSession: problem == .consentExpired)
}

extension BankLinkInfo {
    /// Aplica el resultado de una consulta: éxito o el fallo clasificado.
    public func applying(_ outcome: Result<Void, Error>, at: Date) -> BankLinkInfo {
        switch outcome {
        case .success: return recordingSuccess(at: at)
        case let .failure(error): return recordingFailure(syncProblem(for: error), at: at)
        }
    }

    /// Tras (re)conectar con éxito: nueva caducidad, sin problema ni espera. Se conservan las consultas anotadas.
    public func renewed(consentValidUntil: Date, at: Date) -> BankLinkInfo {
        var copy = self
        copy.connectedAt = at
        copy.consentValidUntil = consentValidUntil
        copy.problem = nil
        copy.backoffUntil = nil
        return copy
    }
}
