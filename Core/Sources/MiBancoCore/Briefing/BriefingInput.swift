import Foundation

/// El saldo de un banco en el resumen y lo que ha cambiado desde el resumen anterior.
public struct BankLine: Equatable, Sendable {
    public let bank: BankID
    /// nil = aún sin saldo conocido.
    public let cents: Int?
    /// true = el saldo es una estimación (no lo dijo el banco).
    public let estimated: Bool
    public let changeCents: Int

    public init(bank: BankID, cents: Int?, estimated: Bool, changeCents: Int) {
        self.bank = bank
        self.cents = cents
        self.estimated = estimated
        self.changeCents = changeCents
    }
}

/// Un ingreso o un pago del periodo. `cents` siempre positivo.
public struct MovementDigest: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let bank: BankID
    public let name: String
    public let cents: Int
    public let date: Date

    public init(id: UUID, bank: BankID, name: String, cents: Int, date: Date) {
        self.id = id
        self.bank = bank
        self.name = name
        self.cents = cents
        self.date = date
    }
}

/// Dinero que cambió de una cuenta tuya a otra tuya.
public struct TransferDigest: Equatable, Sendable {
    public let from: BankID
    public let to: BankID
    public let cents: Int

    public init(from: BankID, to: BankID, cents: Int) {
        self.from = from
        self.to = to
        self.cents = cents
    }
}

public enum AttentionItem: Equatable, Sendable {
    case bankProblem(BankID, SyncProblem)
    case consentExpiring(BankID, Date)
    case budgetExceeded(name: String, spentCents: Int, limitCents: Int)
    case warning(title: String, detail: String?)
}

public struct MonthDigest: Equatable, Sendable {
    public let spentCents: Int
    public let projectedCents: Int?
    public let paceDifferenceCents: Int?
    /// "octubre": el mes anterior, en minúsculas.
    public let previousMonthName: String

    public init(spentCents: Int, projectedCents: Int?, paceDifferenceCents: Int?, previousMonthName: String) {
        self.spentCents = spentCents
        self.projectedCents = projectedCents
        self.paceDifferenceCents = paceDifferenceCents
        self.previousMonthName = previousMonthName
    }
}

public struct BudgetTip: Equatable, Sendable {
    public let name: String
    public let remainingCents: Int

    public init(name: String, remainingCents: Int) {
        self.name = name
        self.remainingCents = remainingCents
    }
}

/// Todo lo que el resumen puede decir, calculado con funciones del Core sobre el libro. Nada se inventa.
public struct BriefingInput: Equatable, Sendable {
    public var now: Date
    public var since: Date
    public var isFirst: Bool
    public var banks: [BankLine]
    public var totalCents: Int?
    public var totalChangeCents: Int
    public var income: [MovementDigest]
    public var payments: [MovementDigest]
    public var transfers: [TransferDigest]
    public var upcoming: [UpcomingCharge]
    public var expected: ExpectedIncome?
    public var attention: [AttentionItem]
    public var month: MonthDigest?
    public var investments: PortfolioSummary?
    public var shortfalls: [Shortfall]
    public var budgetTip: BudgetTip?
    public var freeMoney: FreeMoney?
    /// Bancos del resumen sin saldo conocido: no entran en el total ni en su cambio, y el texto lo dice.
    public var totalLeftOut: [BankID]

    public init(now: Date, since: Date, isFirst: Bool, banks: [BankLine] = [], totalCents: Int? = nil, totalChangeCents: Int = 0,
                income: [MovementDigest] = [], payments: [MovementDigest] = [], transfers: [TransferDigest] = [],
                upcoming: [UpcomingCharge] = [], expected: ExpectedIncome? = nil, attention: [AttentionItem] = [],
                month: MonthDigest? = nil, investments: PortfolioSummary? = nil, shortfalls: [Shortfall] = [],
                budgetTip: BudgetTip? = nil, freeMoney: FreeMoney? = nil, totalLeftOut: [BankID] = []) {
        self.now = now
        self.since = since
        self.isFirst = isFirst
        self.banks = banks
        self.totalCents = totalCents
        self.totalChangeCents = totalChangeCents
        self.income = income
        self.payments = payments
        self.transfers = transfers
        self.upcoming = upcoming
        self.expected = expected
        self.attention = attention
        self.month = month
        self.investments = investments
        self.shortfalls = shortfalls
        self.budgetTip = budgetTip
        self.freeMoney = freeMoney
        self.totalLeftOut = totalLeftOut
    }
}

private let fullMonthNames = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
                              "noviembre", "diciembre"]

/// Cuántos días atrás se da por retrasado (y no por perdido) un cobro fijo que no llegó.
let overdueWindowDays = 14

/// Cobros de las suscripciones activas (todas, con su próxima fecha) como `UpcomingCharge`. Una suscripción que ya se cobró
/// hoy no vuelve a contarse hoy (su próxima fecha ya es la del mes que viene) y una cuyo cobro de hoy ya está en el libro
/// tampoco.
func subscriptionCharges(in state: LedgerState, now: Date, calendar: Calendar, notSpending: Set<UUID>? = nil) -> [UpcomingCharge] {
    let today = calendar.startOfDay(for: now)
    var chargedToday = Set<String>()
    for m in state.movements where m.kind == .payment && !m.flaggedNotMine && m.date >= today && m.date <= now {
        chargedToday.insert(m.bank.rawValue + "|" + normalizeMerchant(m.merchant ?? ""))
    }
    let earliestOverdue = calendar.date(byAdding: .day, value: -overdueWindowDays, to: today) ?? today
    return activeSubscriptions(in: state, now: now, calendar: calendar, notSpending: notSpending).compactMap { sub in
        let isToday = calendar.isDate(sub.nextDate, inSameDayAs: now)
        if isToday && chargedToday.contains(sub.bank.rawValue + "|" + sub.id) { return nil }
        // Un cobro cuya fecha cayó en los últimos 14 días y no está en el libro se da por retrasado: cuenta HOY.
        let dueDay = calendar.startOfDay(for: sub.nextDate)
        if dueDay < today, dueDay >= earliestOverdue {
            return UpcomingCharge(name: sub.merchant, bank: sub.bank, cents: sub.amountCents, date: today, overdue: true,
                                  dueDate: sub.nextDate)
        }
        return UpcomingCharge(name: sub.merchant, bank: sub.bank, cents: sub.amountCents, date: sub.nextDate)
    }.sorted { $0.date != $1.date ? $0.date < $1.date : $0.name < $1.name }
}

private let excludedInsightKinds: Set<InsightKind> = [.budgetWarning, .budgetExceeded, .subscriptionUpcoming, .subscriptionPriceChange]

/// Los días sin dato del banco a partir de los cuales se avisa de que los datos están viejos.
private let staleBankSeconds: TimeInterval = 172_800

/// Qué ha pasado desde el resumen anterior (`record.since`, `now`]. Los gastos usan las funciones de gasto del Core con su
/// tratamiento por defecto (valores, traspasos propios y capturas dudosas fuera). Nada se registra en ningún sitio.
public func briefingInput(state: LedgerState, portfolio: Portfolio?, book: AccountBook, record: BriefingRecord, isFirst: Bool,
                          now: Date, calendar: Calendar) -> BriefingInput {
    let since = record.since
    // Un movimiento pertenece al periodo por cuándo SE ENTERÓ la app (la fecha del banco puede ser anterior al resumen
    // pasado y haber llegado después): así ninguno se pierde ni sale en dos resúmenes.
    // Límite: solo entra si su propia fecha no es anterior a 7 días antes del «desde» (una importación de meses de historial
    // no inunda el resumen).
    let lateLimit = since.addingTimeInterval(-7 * 86_400)
    func inPeriod(_ m: Movement) -> Bool {
        let knownAt = max(m.date, m.importedAt ?? m.date)
        return knownAt > since && knownAt <= now && m.date > lateLimit && !m.flaggedNotMine
    }
    let ledger = Ledger(state: state)
    // Se calcula una vez y se pasa a todas las sumas de gasto (traspasos, capturados sin confirmar y gemelos).
    let exclusions = spendingExclusions(in: state, now: now)
    // Los capturados que ya cuentan en la fila de su banco (sin confirmar o con gemelo): fuera de ingresos y del cambio de
    // cada banco. Los traspasos propios se quedan en el cambio del banco.
    let ownTransfers = ownTransferIDs(in: state.movements)
    let unconfirmed = unconfirmedCaptureIDs(in: state, now: now)
    let twins = probableTwinCaptureIDs(in: state.movements, skipping: ownTransfers.union(unconfirmed))
    let doubleCounted = unconfirmed.union(twins).subtracting(ownTransfers)
    let period = state.movements.filter(inPeriod)
    func name(_ m: Movement) -> String { m.displayMerchant ?? m.merchant ?? m.bank.displayName }
    func digest(_ m: Movement) -> MovementDigest {
        MovementDigest(id: m.id, bank: m.bank, name: name(m), cents: abs(m.amountCents), date: m.date)
    }
    func byAmount(_ a: MovementDigest, _ b: MovementDigest) -> Bool {
        a.cents != b.cents ? a.cents > b.cents : (a.date != b.date ? a.date > b.date : a.id.uuidString < b.id.uuidString)
    }

    // Traspasos entre tus cuentas
    let transferIDs = ownTransferIDs(in: state.movements)
    let byID = Dictionary(state.movements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let transfers: [TransferDigest] = ownTransferPairs(in: state.movements).compactMap { pair -> (Date, TransferDigest)? in
        guard let payment = byID[pair.paymentID], let income = byID[pair.incomeID], inPeriod(payment) else { return nil }
        return (payment.date, TransferDigest(from: payment.bank, to: income.bank, cents: abs(payment.amountCents)))
    }.sorted { $0.0 < $1.0 }.map { $0.1 }

    let income = period.filter {
        $0.kind == .income && !transferIDs.contains($0.id) && !$0.excludedFromSpending && !doubleCounted.contains($0.id)
    }
        .map(digest).sorted(by: byAmount)
    let periodIDs = Set(period.map(\.id))
    let payments = spendingMovements(in: state.movements, notSpending: exclusions).filter { periodIDs.contains($0.id) }
        .map(digest).filter { $0.cents > 0 }.sorted(by: byAmount)

    // Bancos
    var banks: [BankLine] = []
    for bank in BankID.allCases {
        let balance = ledger.balance(bank)
        let mine = period.filter { $0.bank == bank }
        guard balance != nil || !mine.isEmpty else { continue }
        banks.append(BankLine(bank: bank, cents: balance?.cents, estimated: balance?.estimated ?? false,
                              changeCents: mine.filter { !doubleCounted.contains($0.id) }.reduce(0) { $0 + $1.amountCents }))
    }
    // El cambio total solo suma bancos con saldo conocido; los que quedan fuera se dicen junto al total.
    let totalChange = banks.filter { $0.cents != nil }.reduce(0) { $0 + $1.changeCents }
    let leftOut = banks.filter { $0.cents == nil }.map(\.bank)

    // Lo que viene
    let startOfToday = calendar.startOfDay(for: now)
    let weekEnd = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now
    let allCharges = subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions)
    let upcoming = allCharges.filter { $0.date >= startOfToday && $0.date < weekEnd }
    var expected = expectedIncome(in: state, now: now, calendar: calendar)
    if let date = expected?.date, date > (calendar.date(byAdding: .day, value: 7, to: now) ?? now) { expected = nil }

    // Atención
    var attention: [AttentionItem] = []
    for bank in BankID.allCases {
        guard let link = state.links[bank] else { continue }
        if let problem = link.problem {
            attention.append(.bankProblem(bank, problem))
        } else if link.consentValidUntil <= now {
            attention.append(.bankProblem(bank, .consentExpired))
        } else if let last = link.lastSuccessAt, now.timeIntervalSince(last) > staleBankSeconds {
            attention.append(.warning(title: "Los datos de \(bank.displayName) llevan días sin actualizarse", detail: nil))
        }
    }
    for bank in BankID.allCases {
        guard let link = state.links[bank], link.consentValidUntil > now else { continue }
        // Con la conexión ya dada por caducada o rechazada, una sola línea: la que dice que se renueve.
        if link.problem == .consentExpired || link.problem == .keyRejected { continue }
        let days = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: link.consentValidUntil)).day ?? 99
        if days <= 10 { attention.append(.consentExpiring(bank, link.consentValidUntil)) }
    }
    let statuses = budgetStatuses(in: state, month: now, now: now, calendar: calendar, notSpending: exclusions)
    func budgetName(_ status: BudgetStatus) -> String {
        switch status.scope {
        case .month: "tu presupuesto del mes"
        case .category(let c): c.displayName
        }
    }
    for status in statuses where status.level == .exceeded {
        attention.append(.budgetExceeded(name: budgetName(status), spentCents: status.spentCents, limitCents: status.limitCents))
    }
    for insight in insights(for: state, now: now, calendar: calendar, notSpending: exclusions)
    where insight.severity == .warning && !excludedInsightKinds.contains(insight.kind) && insight.date > since && insight.date <= now {
        attention.append(.warning(title: insight.title, detail: insight.detail))
    }
    let tipStatus = statuses.filter { $0.level == .warning }.max { $0.percent < $1.percent }
    let budgetTip = tipStatus.map { BudgetTip(name: budgetName($0), remainingCents: $0.remainingCents) }

    // El mes
    let forecast = monthForecast(in: state, now: now, calendar: calendar, notSpending: exclusions)
    let pace = spendingPace(movements: state.movements, now: now, calendar: calendar, notSpending: exclusions)
    let spent = forecast?.spentCents ?? monthSpending(in: state, month: now, now: now, calendar: calendar, notSpending: exclusions).totalCents
    var month: MonthDigest?
    if spent > 0 || pace != nil {
        let monthIndex = (calendar.component(.month, from: now) + 10) % 12
        month = MonthDigest(spentCents: spent, projectedCents: forecast?.projectedCents, paceDifferenceCents: pace?.differenceCents,
                            previousMonthName: fullMonthNames[monthIndex])
    }

    // Dinero libre y faltas de saldo
    var balances: [BankID: Int] = [:]
    var estimated = Set<BankID>()
    for bank in BankID.allCases {
        guard let balance = ledger.balance(bank) else { continue }
        balances[bank] = balance.cents
        if balance.estimated { estimated.insert(bank) }
    }
    let short = shortfalls(balances: balances, floors: book.floors, upcoming: upcoming, now: now, calendar: calendar,
                           estimated: estimated)
    let free = freeMoney(balances: balances, floors: book.floors, banks: [.rev, .ima], pending: allCharges, now: now,
                         calendar: calendar)

    return BriefingInput(now: now, since: since, isFirst: isFirst, banks: banks, totalCents: ledger.total(),
                         totalChangeCents: totalChange, income: income, payments: payments, transfers: transfers,
                         upcoming: upcoming, expected: expected, attention: attention, month: month,
                         investments: portfolio.flatMap { portfolioSummary($0, now: now) }, shortfalls: short,
                         budgetTip: budgetTip, freeMoney: free, totalLeftOut: leftOut)
}
