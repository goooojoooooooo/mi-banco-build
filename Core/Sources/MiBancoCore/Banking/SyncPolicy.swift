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
        _ link: BankLinkInfo?, trigger: SyncTrigger, now: Date, calendar: Calendar
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
        let from = calendar.date(byAdding: .day, value: -overlapDays, to: base) ?? base
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
