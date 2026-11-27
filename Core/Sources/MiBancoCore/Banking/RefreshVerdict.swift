import Foundation

/// Lo que dejó una consulta a mano para un banco (el mismo reparto que el resultado de la consulta en la app:
/// saltado por la política, actualizado o fallido).
public enum BankRefreshOutcome: Equatable, Sendable {
    case skipped(SkipReason)
    case updated
    case failed(SyncProblem)
}

/// Lo que dejó una consulta de un banco en la app (`BankSync`): saltada por la política, actualizada con `added`
/// movimientos nuevos o fallida. Vive en Core para que su reparto a `BankRefreshOutcome` tenga pruebas.
public enum SyncOutcome: Equatable, Sendable {
    case skipped(SkipReason)
    case updated(added: Int)
    case failed(SyncProblem)

    /// El resultado para el veredicto de «Al día» (cuántos movimientos trajo no importa).
    public var refreshOutcome: BankRefreshOutcome {
        switch self {
        case let .skipped(reason): .skipped(reason)
        case .updated: .updated
        case let .failed(problem): .failed(problem)
        }
    }
}

/// ¿Puede Inicio decir «Al día» tras tirar para actualizar? Es una afirmación sobre el dinero del dueño, así que solo
/// es verdad si hay algún banco conectado y CADA banco conectado se actualizó ahora o se saltó porque ya está al día
/// de verdad.
/// - Conectado = tiene conexión guardada (aunque su consentimiento haya caducado: entonces no está al día).
/// - Un banco conectado sin resultado (consulta desactivada, cancelada) no está al día.
/// - Saltado porque ya está reciente, porque se gastó el cupo del día o porque toca esperar: solo cuenta si la última
///   lectura buena es de hace menos de `SyncPolicy.autoSpacing` (lo mismo que la app da por reciente al abrirse) y la
///   conexión no arrastra ningún problema.
/// - Consentimiento caducado, sin conexión o fallo: nunca.
public enum RefreshVerdict {
    public static func isUpToDate(
        outcomes: [BankID: BankRefreshOutcome], links: [BankID: BankLinkInfo], now: Date
    ) -> Bool {
        guard !links.isEmpty else { return false }
        return links.allSatisfy { bank, link in
            guard let outcome = outcomes[bank] else { return false }
            switch outcome {
            case .updated:
                return true
            case .skipped(.fresh), .skipped(.budgetUsed), .skipped(.waiting):
                return isFresh(link, now: now)
            case .skipped(.consentExpired), .skipped(.notConnected), .failed:
                return false
            }
        }
    }

    private static func isFresh(_ link: BankLinkInfo, now: Date) -> Bool {
        guard link.problem == nil, now < link.consentValidUntil, let ok = link.lastSuccessAt else { return false }
        return now.timeIntervalSince(ok) < SyncPolicy.autoSpacing
    }
}
