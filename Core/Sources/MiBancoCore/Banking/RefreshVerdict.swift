import Foundation

/// Lo que dejó una consulta a mano para un banco (el mismo reparto que el resultado de la consulta en la app:
/// saltado por la política, actualizado o fallido).
public enum BankRefreshOutcome: Equatable, Sendable {
    case skipped(SkipReason)
    case updated
    case failed(SyncProblem)
}

/// ¿Puede Inicio decir «Al día» tras tirar para actualizar? Es una afirmación sobre el dinero del dueño, así que solo
/// es verdad si hay algún banco conectado y CADA banco conectado se actualizó ahora o se saltó porque ya está al día
/// de verdad.
public enum RefreshVerdict {
    public static func isUpToDate(
        outcomes: [BankID: BankRefreshOutcome], links: [BankID: BankLinkInfo], now: Date
    ) -> Bool {
        // Regla vieja (provisional, para ver las pruebas en rojo): basta con que ningún banco haya fallado.
        !outcomes.values.contains { outcome in
            if case .failed = outcome { return true }
            return false
        }
    }
}
