import Foundation

/// Calendario de los días de la consulta al banco y de los avisos: gregoriano, Madrid.
public let bankingCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    return c
}()

/// `yyyy-MM-dd` en el calendario dado (el `date_from` de la API), sin formateadores de la plataforma.
public func bankDateParameter(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    func two(_ n: Int?) -> String { let v = n ?? 0; return v < 10 ? "0\(v)" : "\(v)" }
    let year = c.year ?? 1970
    let yearText = year < 10 ? "000\(year)" : year < 100 ? "00\(year)" : year < 1000 ? "0\(year)" : "\(year)"
    return "\(yearText)-\(two(c.month))-\(two(c.day))"
}

/// Saldo del banco a partir de la lectura de cada cuenta. Una cuenta sin lectura en euros (nil) hace que no se adopte
/// nada: una suma parcial enseñaría un saldo falso. La hora es la de la lectura más antigua. Todas disponibles:
/// disponible; todas contabilizadas: contabilizado; de las dos clases: `.mixed` (se suma y es estimado).
/// Un saldo `.mixed` de una sola cuenta no existe.
public func combineBalanceReadings(_ readings: [BalanceReading?]) -> BalanceReading? {
    guard !readings.isEmpty else { return nil }
    var cents = 0
    var at: Date?
    var kinds = Set<Int>()
    for reading in readings {
        guard let reading else { return nil }
        cents += reading.cents
        at = min(at ?? reading.at, reading.at)
        kinds.insert(reading.kind == .booked ? 1 : 0)
    }
    guard let at else { return nil }
    let kind: BalanceReading.Kind = kinds.count > 1 ? .mixed : (kinds.contains(1) ? .booked : .available)
    return BalanceReading(cents: cents, at: at, kind: kind)
}

/// Qué pasó al aplicar una consulta al libro.
public struct BankFetchApplied: Equatable, Sendable {
    public let report: ReconcileReport
    public let balanceAdopted: Bool
}

extension Ledger {
    /// Aplica de una vez, en una sola escritura, lo que trajo una consulta: movimientos, saldo y el éxito anotado en la
    /// conexión. `fetchedAt` es el instante de la consulta: hora de importación de las filas y de la lectura.
    /// `complete == false` (el banco cortó el listado): se conserva lo recibido, pero no se da por desaparecido nada
    /// pendiente (`coverage` nil) porque no se vio todo el periodo.
    /// Si la conexión ya no existe (se desconectó durante la consulta) no se escribe nada y devuelve nil.
    public mutating func applyBankFetch(
        bank: BankID, records: [BankRecord], balance: BalanceReading?, dateFrom: Date, complete: Bool,
        fetchedAt: Date, calendar: Calendar
    ) -> BankFetchApplied? {
        guard let link = state.links[bank] else { return nil }
        // Sin lectura adoptable (no hay, o es más vieja que la actual) y con una base que suma pendientes, los pendientes
        // no pasan a apuntados en esta escritura (dejarían de sumar sin que el saldo los incluya) ni se dan por
        // desaparecidos: lo aplica la siguiente consulta que sí adopte lectura.
        let current = state.balances[bank]
        let adoptable = balance.map { b in !(current.map { $0.origin != .manual && b.at < $0.setAt } ?? false) } ?? false
        let hold = !adoptable && (current?.countsPending ?? false)
        // Consulta completa: el banco devuelve TODOS sus pendientes actuales; uno que falta ha desaparecido, sea de la
        // fecha que sea. `dateFrom` solo acota lo apuntado que se pidió.
        let coverage = (complete && !hold) ? DateInterval(start: .distantPast, end: .distantFuture) : nil
        let report = reconcile(records, bank: bank, channel: .bank, coverage: coverage, now: fetchedAt, calendar: calendar,
                               holdPendingFlips: hold)
        var adopted = false
        if let balance {
            adopted = adoptBalance(bank, cents: balance.cents, at: balance.at, origin: .bank, fetchedAt: fetchedAt,
                                   countsPending: balance.kind == .booked, forcedEstimate: balance.kind == .mixed)
        }
        setLink(bank, link.recordingSuccess(at: fetchedAt))
        return BankFetchApplied(report: report, balanceAdopted: adopted)
    }
}

/// Un aviso de caducidad del consentimiento de un banco.
public struct BankReminder: Equatable, Sendable {
    public enum Kind: Sendable { case renew, expired }
    public let id: String
    public let bank: BankID
    public let kind: Kind
    public let fireAt: Date
    public let title: String
    public let body: String
}

public func bankReminderIDs(for bank: BankID) -> [String] {
    ["bank-consent-\(bank.rawValue)", "bank-expired-\(bank.rawValue)"]
}

/// Los avisos que toca tener programados: diez días antes de que caduque y al caducar. Solo de conexiones vivas (sin
/// problema de consentimiento ni de clave) y solo en el futuro. El texto sale de aquí.
public func bankReminders(links: [BankID: BankLinkInfo], now: Date, calendar: Calendar) -> [BankReminder] {
    var out: [BankReminder] = []
    for bank in BankID.allCases {
        guard let link = links[bank], link.problem != .consentExpired, link.problem != .keyRejected,
              link.consentValidUntil > now else { continue }
        let ids = bankReminderIDs(for: bank)
        if let at = consentReminderDate(validUntil: link.consentValidUntil, now: now, calendar: calendar) {
            let date = shortSpanishDate(link.consentValidUntil, calendar: calendar, withYear: false)
            out.append(BankReminder(
                id: ids[0], bank: bank, kind: .renew, fireAt: at,
                title: "Renueva la conexión con \(bank.displayName)",
                body: "Caduca el \(date). Tócalo y apruébalo en tu banco: es un minuto."))
        }
        out.append(BankReminder(
            id: ids[1], bank: bank, kind: .expired, fireAt: link.consentValidUntil,
            title: "La conexión con \(bank.displayName) ha caducado",
            body: "Renuévala para volver a ver sus movimientos y su saldo exacto."))
    }
    return out
}
