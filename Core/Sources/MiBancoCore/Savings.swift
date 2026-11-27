import Foundation

/// La cuenta remunerada de Revolut (Plan 12). Enable Banking solo da las cuentas de pago, así que el dueño pone su saldo
/// una vez (y, si quiere, el interés anual que le enseña Revolut) y desde ahí la app lo sigue: cada traspaso de la cuenta
/// de Revolut a la remunerada suma y cada uno de vuelta resta. Con interés, se suma una estimación día a día. Corregir el
/// saldo es poner una base nueva (importe y momento): lo de después cuenta desde ahí.
public struct SavingsAccount: Codable, Equatable, Sendable {
    /// Saldo que puso el dueño (base).
    public var baselineCents: Int
    /// Cuándo lo puso: los traspasos de antes ya están dentro.
    public var baselineAt: Date
    /// Interés anual en puntos básicos (200 = 2,00 %). nil = sin interés (no se escribe).
    public var annualRateBasisPoints: Int?
    /// Hora de la consulta de Revolut que siguió a poner la base (`Ledger.noteSavingsRefresh`): las filas de solo día del
    /// día de la base que llegaron en ella o antes ya estaban dentro del saldo que puso el dueño. nil = no hubo esa consulta
    /// (no se escribe): cuenta la hora de la base.
    public var coveredThrough: Date?

    public init(baselineCents: Int, baselineAt: Date, annualRateBasisPoints: Int? = nil, coveredThrough: Date? = nil) {
        self.baselineCents = baselineCents
        self.baselineAt = baselineAt
        self.annualRateBasisPoints = annualRateBasisPoints
        self.coveredThrough = coveredThrough
    }
}

/// Lo que vale ahora la cuenta remunerada: base + traspasos + intereses. Siempre es una estimación.
public struct SavingsBalance: Equatable, Sendable {
    public let cents: Int
    /// Traspasos netos desde la base (positivo = entró dinero en la remunerada).
    public let transfersCents: Int
    /// Intereses estimados desde la base.
    public let interestCents: Int
    public let annualRateBasisPoints: Int?
    public let baselineAt: Date
}

/// Un cambio del saldo de la remunerada: cuándo y cuánto (positivo = entra).
public struct SavingsFlow: Equatable, Sendable {
    public let date: Date
    public let cents: Int

    public init(date: Date, cents: Int) {
        self.date = date
        self.cents = cents
    }
}

/// Palabras (sin mayúsculas ni tildes) de un traspaso con la cuenta remunerada: «To EUR Savings», «From EUR Savings»,
/// «A cuenta remunerada», «Ahorros». Más estrecha que `ownAccountWords`: los bolsillos y huchas sin interés («pocket»,
/// «vault», «hucha») son otras cuentas y no mueven este saldo.
private let savingsWords: Set<String> = ["savings", "ahorro", "ahorros", "remunerada"]

private func mentionsSavings(_ text: String?) -> Bool {
    guard let text else { return false }
    return foldedWords(text).contains { savingsWords.contains($0) }
}

/// true si el movimiento es un traspaso entre la cuenta de Revolut y su cuenta remunerada (por el texto del aviso, del
/// banco o del extracto). Nunca una compra en tienda.
public func isSavingsTransfer(_ m: Movement) -> Bool {
    m.bank == .rev && !m.isShop && (mentionsSavings(m.merchant) || mentionsSavings(m.bankMerchant))
}

/// Interés simple estimado, día a día: por cada día de `calendar` ya TERMINADO desde el día de la base (el de la base
/// incluido), el saldo al final de ese día (base + flujos de hasta ese día, nunca negativo) × interés anual / 365. No se
/// capitaliza: los intereses no generan intereses. Se suma en enteros y se redondea una vez al céntimo (mitad hacia arriba).
public func savingsInterestCents(baselineCents: Int, baselineAt: Date, flows: [SavingsFlow], annualRateBasisPoints: Int,
                                 now: Date, calendar: Calendar) -> Int {
    guard annualRateBasisPoints > 0 else { return 0 }
    let firstDay = calendar.startOfDay(for: baselineAt)
    let days = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0
    guard days > 0 else { return 0 }
    let sorted = flows.sorted { $0.date < $1.date }
    var next = 0
    var principal = baselineCents
    var accrued = 0
    for k in 0..<days {
        guard let dayEnd = calendar.date(byAdding: .day, value: k + 1, to: firstDay) else { break }
        while next < sorted.count, sorted[next].date < dayEnd {
            principal += sorted[next].cents
            next += 1
        }
        accrued += max(0, principal) * annualRateBasisPoints
    }
    let divisor = 10_000 * 365
    return (accrued + divisor / 2) / divisor
}

/// Los movimientos que mueven la remunerada, ya sin duplicados: los del libro tal como quedan tras fusionar las fuentes
/// (un aviso enlazado con su registro es UN movimiento; lo borrado ya no está), sin los «no es mío» ni los que el dueño dice
/// que no son la remunerada (`ownTransfer == false`), y sin las copias que la app ya reconoce como el mismo dinero: el
/// pendiente que tiene su apuntado (`twinnedPending`), el capturado sin confirmar (`unconfirmedCaptureIDs`) y la fila del
/// banco o del extracto de un capturado sin enlazar (mismo importe con signo, a un día de Madrid o menos; uno a uno): el par
/// lo representa el capturado, que trae la hora exacta. Primero se quitan las copias, sobre TODOS los traspasos, y solo
/// después se mira la base (`isAfterSavingsBaseline`): un aviso de antes de la base se lleva su fila con él.
public func countedSavingsTransfers(in state: LedgerState, account: SavingsAccount, now: Date) -> [Movement] {
    let candidates = state.movements.filter { isSavingsTransfer($0) && !$0.flaggedNotMine && $0.ownTransfer != false }
    guard !candidates.isEmpty else { return [] }
    // Lectura neutra: todo apuntado del banco cuenta como visto, así cada pendiente con su apuntado se empareja.
    let neutral = ManualBalance(cents: 0, setAt: .distantFuture, origin: .bank)
    var skip = Ledger.twinnedPending(state.movements, bank: .rev, base: neutral)
    skip.formUnion(unconfirmedCaptureIDs(in: state, now: now))
    let rows = candidates.filter { $0.source.isBankSourced && !skip.contains($0.id) }
    var usedRows = Set<UUID>()
    let captures = candidates
        .filter { !$0.source.isBankSourced && $0.bankRef == nil && $0.statementRef == nil && !skip.contains($0.id) }
        .sorted { $0.date < $1.date }
    for capture in captures {
        let day = madridCalendar.startOfDay(for: capture.date)
        let twin = rows.filter { row in
            guard !usedRows.contains(row.id), row.amountCents == capture.amountCents else { return false }
            let apart = madridCalendar.dateComponents([.day], from: day, to: madridCalendar.startOfDay(for: row.date)).day ?? Int.max
            return abs(apart) <= 1
        }.min { abs($0.date.timeIntervalSince(capture.date)) < abs($1.date.timeIntervalSince(capture.date)) }
        if let twin {
            usedRows.insert(twin.id)
            skip.insert(twin.id)
        }
    }
    return candidates.filter { !skip.contains($0.id) && isAfterSavingsBaseline($0, account) }
}

/// ¿Es este traspaso posterior a la base (no estaba ya en el saldo que puso el dueño)?
/// - Con hora (aviso, Cartera, extracto, o fila del banco enlazada a un aviso): si su hora es posterior a la de la base.
/// - Fila de solo día (Enable Banking, a mediodía de Madrid): por días de Madrid. Un día anterior al de la base ya estaba
///   dentro; uno posterior, no. Del MISMO día solo cuenta si se vio por primera vez (`importedAt`, o `linkedAt` de un
///   capturado) después de lo que la base ya incluye: la hora de la base o, si la hubo, la consulta de Revolut que siguió a
///   ponerla (`coveredThrough`), que trae lo que se hizo antes de la base. Sin esa consulta, una fila del día de la base que
///   llega después se toma por posterior.
func isAfterSavingsBaseline(_ m: Movement, _ account: SavingsAccount) -> Bool {
    guard m.dayOnly else { return m.date > account.baselineAt }
    let day = madridCalendar.startOfDay(for: m.date)
    let baseDay = madridCalendar.startOfDay(for: account.baselineAt)
    if day != baseDay { return day > baseDay }
    let firstSeen = m.source.isBankSourced ? m.importedAt : (m.linkedAt ?? m.importedAt)
    guard let firstSeen else { return false }
    return firstSeen > max(account.baselineAt, account.coveredThrough ?? account.baselineAt)
}

extension Ledger {
    /// Pone (o corrige) el saldo de la cuenta remunerada: pasa a ser la base nueva, con este momento.
    public mutating func setSavings(balanceCents: Int, annualRateBasisPoints: Int?, now: Date) {
        let rate = annualRateBasisPoints.flatMap { $0 > 0 ? $0 : nil }
        state.savings = SavingsAccount(baselineCents: balanceCents, baselineAt: now, annualRateBasisPoints: rate)
    }

    /// Deja de seguir la cuenta remunerada: el libro queda como si nunca se hubiera puesto.
    public mutating func removeSavings() {
        state.savings = nil
    }

    /// La consulta de Revolut que se pide al guardar la base terminó bien a la hora `syncedAt`: lo que trajo ya estaba en el
    /// saldo que puso el dueño. Solo vale la primera, y solo si llega en los 15 minutos siguientes a la base (otra consulta
    /// más tarde podría traer traspasos hechos después de la base).
    public mutating func noteSavingsRefresh(syncedAt: Date) {
        guard var account = state.savings, account.coveredThrough == nil, syncedAt >= account.baselineAt,
              syncedAt.timeIntervalSince(account.baselineAt) <= Self.savingsRefreshWindow else { return }
        account.coveredThrough = syncedAt
        state.savings = account
    }

    static let savingsRefreshWindow: TimeInterval = 15 * 60

    /// Lo que vale ahora la cuenta remunerada; nil si el dueño no la ha puesto.
    public func savingsBalance(now: Date) -> SavingsBalance? {
        guard let account = state.savings else { return nil }
        // Un traspaso que SALE de la cuenta de Revolut (pago) ENTRA en la remunerada, y al revés.
        let flows = countedSavingsTransfers(in: state, account: account, now: now)
            .map { SavingsFlow(date: $0.date, cents: -$0.amountCents) }
        let transfers = flows.reduce(0) { $0 + $1.cents }
        let interest = account.annualRateBasisPoints.map {
            savingsInterestCents(baselineCents: account.baselineCents, baselineAt: account.baselineAt, flows: flows,
                                 annualRateBasisPoints: $0, now: now, calendar: madridCalendar)
        } ?? 0
        return SavingsBalance(cents: account.baselineCents + transfers + interest, transfersCents: transfers,
                              interestCents: interest, annualRateBasisPoints: account.annualRateBasisPoints,
                              baselineAt: account.baselineAt)
    }

    /// EL total (la única fuente para Inicio, la Live Activity, el asistente y el resumen): los saldos de los bancos
    /// (`banksTotal()`) más la cuenta remunerada, si la hay. Con solo la remunerada puesta, es ella.
    public func total(now: Date) -> Int? {
        let banks = banksTotal()
        guard let savings = savingsBalance(now: now)?.cents else { return banks }
        return (banks ?? 0) + savings
    }
}

/// Texto de un campo de interés anual -> puntos básicos («2,00» = 200), o nil si no se entiende, pasa del 100 % o lleva
/// «€». Acepta el «%» y 0, 1 o 2 decimales tras `,` o `.`, como los saldos.
public func parseAnnualRateInput(_ text: String) -> Int? {
    guard !text.contains("€") else { return nil }
    let clean = text.filter { $0 != "%" }
    guard let bp = parseBalanceInput(clean), (0...10_000).contains(bp) else { return nil }
    return bp
}

/// «2,00 %» (con espacio fino de no separación, como `formatPercentTenths`).
public func formatAnnualRate(_ basisPoints: Int) -> String {
    let m = basisPoints.magnitude
    let frac = m % 100
    return "\(basisPoints < 0 ? "-" : "")\(m / 100),\(frac < 10 ? "0" : "")\(frac)\u{00A0}%"
}

/// Estado de la fila de la cuenta remunerada: «estimado · 2,00 % anual». Con el ojo cerrado, sin ninguna cifra
/// (tampoco la del interés): «estimado · •,•• % anual».
public func savingsStatusText(annualRateBasisPoints: Int?, hidden: Bool) -> String {
    guard let rate = annualRateBasisPoints, rate > 0 else { return "estimado" }
    return "estimado · \(hidden ? "•,••\u{00A0}%" : formatAnnualRate(rate)) anual"
}
