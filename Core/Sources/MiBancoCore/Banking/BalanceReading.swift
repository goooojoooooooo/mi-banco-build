import Foundation

/// Saldo que la app adopta a partir de lo que devolvió el banco para una cuenta.
public struct BalanceReading: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Ya descuenta lo pendiente (ITAV, CLAV, XPCD): el saldo es exacto.
        case available
        /// Solo lo contabilizado: los movimientos pendientes siguen sumando encima y el resultado es estimado.
        case booked
    }

    public let cents: Int
    public let at: Date
    public let kind: Kind

    public init(cents: Int, at: Date, kind: Kind) {
        self.cents = cents
        self.at = at
        self.kind = kind
    }
}

/// Elige el saldo a adoptar. Solo euros; preferencia ITAV, CLAV, XPCD; luego ITBD, CLBD, OPBD, PRCD;
/// el resto (OTHR, INFO, VALU, FWAV, OPAV y desconocidos) solo si no hay nada más.
/// Entre saldos del mismo tipo gana el de fecha de referencia más reciente.
/// La hora es la del propio saldo si existe y no es futura; si no, la de la consulta.
public func chooseBalanceReading(_ balances: [EBBalance], fetchedAt: Date) -> BalanceReading? {
    let order = ["ITAV", "CLAV", "XPCD", "ITBD", "CLBD", "OPBD", "PRCD"]
    var best: (rank: Int, cents: Int, ref: Date?)?
    for balance in balances {
        guard balance.balanceAmount.currency == "EUR",
              let cents = centsFromDecimalString(balance.balanceAmount.amount) else { continue }
        let rank = order.firstIndex(of: balance.balanceType) ?? order.count
        let ref = balance.lastChangeDateTime.flatMap(parseEnableBankingDate)
        if let current = best {
            if rank > current.rank { continue }
            if rank == current.rank {
                guard let ref, ref > (current.ref ?? .distantPast) else { continue }
            }
        }
        best = (rank, cents, ref)
    }
    guard let best else { return nil }
    let at = best.ref.map { $0 <= fetchedAt ? $0 : fetchedAt } ?? fetchedAt
    return BalanceReading(cents: best.cents, at: at, kind: best.rank < 3 ? .available : .booked)
}
