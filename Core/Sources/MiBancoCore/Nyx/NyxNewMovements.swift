import Foundation

/// Identificadores de los movimientos que la app ha conocido desde `since` (o en las últimas 24 h si `since` es nil),
/// excluyendo históricos, ordenados de más antiguo a más reciente por el instante en que la app los supo.
public func nyxNewMovementIDs(in state: LedgerState, since: Date?, now: Date) -> [UUID] {
    let effectiveSince = since ?? now.addingTimeInterval(-86_400)
    return movementsKnown(in: state, since: effectiveSince, now: now)
        .filter { !$0.isHistorical }
        .sorted { a, b in
            let ka = movementKnownAt(a), kb = movementKnownAt(b)
            return ka != kb ? ka < kb : a.id.uuidString < b.id.uuidString
        }
        .map(\.id)
}
