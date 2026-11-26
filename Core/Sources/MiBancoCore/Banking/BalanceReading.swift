import Foundation

/// Saldo que la app adopta a partir de lo que devolvió el banco para una cuenta.
public struct BalanceReading: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Ya descuenta lo pendiente (ITAV, CLAV, XPCD): el saldo es exacto.
        case available
        /// Solo lo contabilizado: los movimientos pendientes siguen sumando encima y el resultado es estimado.
        case booked
        /// Cuentas de las dos clases a la vez (solo al juntar varias cuentas).
        case mixed
    }

    public let cents: Int
    public let at: Date
    public let kind: Kind
    /// Inicio (en Madrid) del día D si el saldo es el cierre de un día ya pasado (sin hora de cambio y con día de
    /// referencia anterior al de la consulta): lo posterior a D suma encima (R49). nil = lectura normal.
    public let closingDay: Date?

    public init(cents: Int, at: Date, kind: Kind, closingDay: Date? = nil) {
        self.cents = cents
        self.at = at
        self.kind = kind
        self.closingDay = closingDay
    }
}

/// Elige el saldo a adoptar. Solo euros; preferencia ITAV, CLAV, XPCD; luego ITBD, CLBD, OPBD, PRCD;
/// el resto (OTHR, INFO, VALU, FWAV, OPAV y desconocidos) solo si no hay nada más.
/// Entre saldos del mismo tipo gana el de fecha de referencia más reciente.
/// La hora es la del propio saldo si existe y no es futura; si no, la de la consulta. Un saldo sin hora de cambio cuyo día
/// de referencia D ya terminó al consultar es el cierre de D: lleva `closingDay` (R49).
public func chooseBalanceReading(_ balances: [EBBalance], fetchedAt: Date) -> BalanceReading? {
    let order = ["ITAV", "CLAV", "XPCD", "ITBD", "CLBD", "OPBD", "PRCD"]
    var best: (rank: Int, cents: Int, ref: Date?, closingEnd: Date?)?
    for balance in balances {
        guard let cents = balance.balanceAmount.euroCents else { continue }
        let rank = order.firstIndex(of: balance.balanceType) ?? order.count
        let changed = balance.lastChangeDateTime.flatMap(parseEnableBankingDate)
        let closingEnd = changed == nil ? balance.referenceDate.flatMap(endOfReferenceDay) : nil
        let ref = changed ?? closingEnd
        if let current = best {
            if rank > current.rank { continue }
            if rank == current.rank {
                guard let ref, ref > (current.ref ?? .distantPast) else { continue }
            }
        }
        best = (rank, cents, ref, closingEnd)
    }
    guard let best else { return nil }
    let at = best.ref.map { $0 <= fetchedAt ? $0 : fetchedAt } ?? fetchedAt
    // Solo un día ya terminado es un cierre; el de hoy (o futuro) se queda en la hora de la consulta, como lectura normal.
    let closingDay = best.closingEnd.flatMap { end in
        end <= fetchedAt ? madridCalendar.date(byAdding: .day, value: -1, to: end) : nil
    }
    return BalanceReading(cents: best.cents, at: at, kind: best.rank < 3 ? .available : .booked, closingDay: closingDay)
}

/// Un saldo sin hora de cambio pero con día de referencia (cierre contabilizado del día D) es de EL FINAL de ese día en
/// Madrid: lo posterior a D suma encima, y repetir el mismo cierre en otra consulta no es "más nuevo".
private func endOfReferenceDay(_ text: String) -> Date? {
    guard let noon = noonOfDay(text, calendar: madridCalendar)?.date else { return nil }
    return madridCalendar.date(byAdding: .day, value: 1, to: madridCalendar.startOfDay(for: noon))
}
