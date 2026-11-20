import Foundation

public enum InsightKind: String, Codable, Sendable {
    case lowBalance, largePayment, unusualPayment, salary, duplicateCharge
    case subscriptionUpcoming, subscriptionPriceChange, spendingPace, weeklyDigest
    case largeIncome
}

public enum InsightSeverity: String, Codable, Sendable { case info, warning, positive }

public struct Insight: Equatable, Sendable, Identifiable {
    /// Estable: tipo + sujeto + día, para no repetir el mismo aviso.
    public let id: String
    public let kind: InsightKind
    public let severity: InsightSeverity
    public let title: String
    public let detail: String?
    public let date: Date
    public let bank: BankID?
    public let merchant: String?
    public let movementID: UUID?

    public init(id: String, kind: InsightKind, severity: InsightSeverity, title: String, detail: String?, date: Date,
                bank: BankID?, merchant: String?, movementID: UUID?) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.date = date
        self.bank = bank
        self.merchant = merchant
        self.movementID = movementID
    }
}

private let feedLimit = 12
private let recentWindow: TimeInterval = 7 * 86_400
private let duplicateWindow: TimeInterval = 15 * 60
private let weekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

private func dayKey(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
}

private func make(_ kind: InsightKind, _ severity: InsightSeverity, subject: String, title: String, detail: String? = nil,
                  date: Date, bank: BankID? = nil, merchant: String? = nil, movementID: UUID? = nil,
                  calendar: Calendar) -> Insight {
    Insight(id: "\(kind.rawValue)|\(subject)|\(dayKey(date, calendar))", kind: kind, severity: severity, title: title,
            detail: detail, date: date, bank: bank, merchant: merchant, movementID: movementID)
}

private func isMuted(_ merchant: String?, in state: LedgerState) -> Bool {
    guard let merchant else { return false }
    let key = normalizeMerchant(merchant)
    return !key.isEmpty && state.mutedMerchants.contains(key)
}

private func merchantSuffix(_ merchant: String?) -> String {
    merchant.map { " en \($0)" } ?? ""
}

private func median(_ values: [Int]) -> Int {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

/// Orden estricto entre movimientos: fecha y, a igual fecha, id. Dos cargos con la misma hora no se "ven" mutuamente.
private func precedes(_ a: Movement, _ b: Movement) -> Bool {
    a.date != b.date ? a.date < b.date : a.id.uuidString < b.id.uuidString
}

/// Pagos válidos (ni "no es mío" ni traspasos entre tus cuentas) agrupados por comercio normalizado. Se construye una vez por llamada.
struct MerchantIndex {
    private let groups: [String: [Movement]]

    init(_ movements: [Movement], ownTransferIDs: Set<UUID>? = nil) {
        var groups: [String: [Movement]] = [:]
        for m in spendingMovements(in: movements, excluding: ownTransferIDs) {
            let key = normalizeMerchant(m.merchant ?? "")
            if key.isEmpty { continue }
            groups[key, default: []].append(m)
        }
        self.groups = groups
    }

    func payments(for key: String) -> [Movement] { groups[key] ?? [] }
}

/// Alertas que dependen solo del movimiento y de los anteriores (todas menos el saldo bajo).
private func movementInsights(_ m: Movement, in state: LedgerState, index: MerchantIndex, subscriptions: [Subscription],
                              ownTransfers: Set<UUID>,
                              calendar: Calendar) -> [Insight] {
    if m.flaggedNotMine || ownTransfers.contains(m.id) || isMuted(m.merchant, in: state) { return [] }
    let settings = state.alertSettings
    let cents = abs(m.amountCents)
    let amount = formatEUR(cents)
    let key = normalizeMerchant(m.merchant ?? "")
    var out: [Insight] = []

    switch m.kind {
    case .income:
        guard settings.income else { break }
        if key.contains("nomina"), cents >= 50_000 {
            out.append(make(.salary, .positive, subject: m.id.uuidString, title: "Has recibido tu nómina: \(amount)",
                            date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
        } else if cents >= 80_000 {
            let from = m.merchant.map { " de \($0)" } ?? ""
            out.append(make(.largeIncome, .positive, subject: m.id.uuidString, title: "Ingreso grande: \(amount)\(from)",
                            date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
        }
    case .payment:
        let isLarge = cents >= settings.largePaymentThresholdCents
        if settings.largePayment, isLarge {
            out.append(make(.largePayment, .warning, subject: m.id.uuidString,
                            title: "Pago grande: \(amount)\(merchantSuffix(m.merchant))",
                            date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
        }
        if settings.largePayment, !isLarge, !key.isEmpty {
            let previous = index.payments(for: key).filter { $0.id != m.id && $0.date <= m.date }.map { abs($0.amountCents) }
            if previous.count >= 3 {
                let usual = median(previous)
                if cents >= usual * 3 {
                    out.append(make(.unusualPayment, .info, subject: m.id.uuidString,
                                    title: "Pago poco habitual en \(m.merchant ?? key): \(amount)",
                                    detail: "Sueles gastar unos \(formatEUR(usual))",
                                    date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
                }
            }
        }
        if settings.duplicateCharge, !key.isEmpty {
            let twin = index.payments(for: key).contains {
                $0.id != m.id && $0.bank == m.bank && $0.amountCents == m.amountCents
                    && precedes($0, m) && m.date.timeIntervalSince($0.date) <= duplicateWindow
            }
            if twin {
                out.append(make(.duplicateCharge, .warning, subject: m.id.uuidString,
                                title: "Posible cobro duplicado: \(amount)\(merchantSuffix(m.merchant))",
                                detail: "Dos cargos iguales en pocos minutos",
                                date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
            }
        }
        if settings.subscriptions, !key.isEmpty,
           let sub = subscriptions.first(where: { $0.id == key && $0.bank == m.bank && $0.lastDate == m.date }),
           let before = sub.previousAmountCents {
            let up = sub.amountCents > before
            out.append(make(.subscriptionPriceChange, .info, subject: "\(m.bank.rawValue)|\(key)",
                            title: "\(sub.merchant) ha \(up ? "subido" : "bajado") \(formatEUR(abs(sub.amountCents - before)))",
                            detail: "Ahora \(formatEUR(sub.amountCents)) al mes",
                            date: m.date, bank: m.bank, merchant: m.merchant, movementID: m.id, calendar: calendar))
        }
    }
    return out
}

/// Textos del aviso semanal programado; mismo texto que el resumen del feed.
public func weeklyDigestText(for state: LedgerState, weekContaining date: Date, calendar: Calendar,
                             ownTransferIDs: Set<UUID>? = nil) -> (title: String, body: String) {
    let week = weekSummary(movements: state.movements, weekContaining: date, calendar: calendar,
                           ownTransferIDs: ownTransferIDs)
    let diff = week.spentCents - week.previousWeekSpentCents
    let body: String
    if diff < 0 {
        body = "\(formatEUR(-diff)) menos que la anterior"
    } else if diff > 0 {
        body = "\(formatEUR(diff)) más que la anterior"
    } else {
        body = "Igual que la anterior"
    }
    return ("Esta semana has gastado \(formatEUR(week.spentCents))", body)
}

/// Avisos extra para publicar justo después de guardar `movement` (nunca el aviso básico "Has pagado…").
/// `state` es el libro DESPUÉS de guardarlo.
/// El saldo bajo se avisa aunque el comercio esté silenciado: el saldo ha bajado de verdad.
public func immediateAlerts(afterStoring movement: Movement, in state: LedgerState, now: Date, calendar: Calendar) -> [Insight] {
    if movement.flaggedNotMine { return [] }
    var out: [Insight] = []
    let settings = state.alertSettings
    if movement.kind == .payment, settings.lowBalance,
       let after = Ledger(state: state).balance(movement.bank)?.cents {
        let before = after - movement.amountCents
        if after < settings.lowBalanceThresholdCents, before >= settings.lowBalanceThresholdCents {
            out.append(make(.lowBalance, .warning, subject: movement.bank.rawValue,
                            title: "Saldo bajo en \(movement.bank.displayName)", detail: "Te quedan \(formatEUR(after))",
                            date: movement.date, bank: movement.bank, movementID: movement.id, calendar: calendar))
        }
    }
    if isMuted(movement.merchant, in: state) { return out }
    // El primer tramo de un traspaso real puede avisar antes de que exista su pareja (el segundo aún no ha llegado):
    // ese aviso ya salió y no se puede retirar. Se acepta; una vez emparejados, ningún tramo cuenta.
    let transfers = ownTransferIDs(in: state.movements)
    let subs = detectSubscriptions(in: state.movements, now: now, calendar: calendar, ownTransferIDs: transfers)
    out += movementInsights(movement, in: state, index: MerchantIndex(state.movements, ownTransferIDs: transfers),
                            subscriptions: subs, ownTransfers: transfers, calendar: calendar)
    return out
}

/// El feed de "Avisos": lo que merece saberse ahora, lo más reciente primero, con un máximo de 12.
public func insights(for state: LedgerState, now: Date, calendar: Calendar) -> [Insight] {
    let settings = state.alertSettings
    let ledger = Ledger(state: state)
    let transfers = ownTransferIDs(in: state.movements)
    let subs = detectSubscriptions(in: state.movements, now: now, calendar: calendar, ownTransferIDs: transfers)
    var out: [Insight] = []

    if settings.lowBalance {
        for bank in BankID.allCases {
            guard let cents = ledger.balance(bank)?.cents, cents < settings.lowBalanceThresholdCents else { continue }
            out.append(make(.lowBalance, .warning, subject: bank.rawValue, title: "Saldo bajo en \(bank.displayName)",
                            detail: "Te quedan \(formatEUR(cents))", date: now, bank: bank, calendar: calendar))
        }
    }

    let index = MerchantIndex(state.movements, ownTransferIDs: transfers)
    for m in state.movements where m.date <= now && now.timeIntervalSince(m.date) < recentWindow {
        out += movementInsights(m, in: state, index: index, subscriptions: subs, ownTransfers: transfers, calendar: calendar)
    }

    if settings.subscriptions {
        let today = calendar.startOfDay(for: now)
        for sub in subs where !isMuted(sub.merchant, in: state) {
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: sub.nextDate)).day ?? 99
            guard (0...7).contains(days) else { continue }
            let when: String
            switch days {
            case 0: when = "hoy"
            case 1: when = "mañana"
            default: when = "el " + weekdayNames[(calendar.component(.weekday, from: sub.nextDate) + 6) % 7]
            }
            out.append(make(.subscriptionUpcoming, .info, subject: "\(sub.bank.rawValue)|\(sub.id)",
                            title: "\(sub.merchant) se cobra \(when): \(formatEUR(sub.amountCents))",
                            date: sub.nextDate, bank: sub.bank, merchant: sub.merchant, calendar: calendar))
        }
    }

    if settings.spendingPace, calendar.component(.day, from: now) > 5,
       let pace = spendingPace(movements: state.movements, now: now, calendar: calendar, ownTransferIDs: transfers),
       abs(pace.differenceCents) >= 1_000 {
        let below = pace.differenceCents < 0
        out.append(make(.spendingPace, below ? .positive : .info, subject: "month",
                        title: "Vas \(formatEUR(abs(pace.differenceCents))) por \(below ? "debajo" : "encima") del mes pasado",
                        detail: "Llevas \(formatEUR(pace.thisMonthCents)) este mes", date: now, calendar: calendar))
    }

    let weekday = calendar.component(.weekday, from: now)
    if settings.weeklyDigest, weekday == 1 || weekday == 2 {
        // El lunes la semana en curso acaba de empezar: se resume la que terminó ayer.
        let reference = weekday == 1 ? now : (calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        let week = weekSummary(movements: state.movements, weekContaining: reference, calendar: calendar,
                               ownTransferIDs: transfers)
        if week.spentCents > 0 || week.previousWeekSpentCents > 0 {
            let text = weeklyDigestText(for: state, weekContaining: reference, calendar: calendar, ownTransferIDs: transfers)
            out.append(make(.weeklyDigest, .info, subject: "week", title: text.title, detail: text.body, date: now,
                            calendar: calendar))
        }
    }

    // Más reciente primero (lo futuro cuenta como "ahora"); empate por id para un orden estable.
    out.sort { a, b in
        let da = min(a.date, now), db = min(b.date, now)
        return da != db ? da > db : a.id < b.id
    }
    var seen = Set<String>()
    return Array(out.filter { seen.insert($0.id).inserted }.prefix(feedLimit))
}
