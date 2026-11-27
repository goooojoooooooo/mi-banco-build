import Foundation

/// Clave de día «YYYY-MM-DD» en el calendario indicado (compartida con N3 y N4).
func nyxDayKey(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    let y = c.year ?? 0
    let m = c.month ?? 0
    let d = c.day ?? 0
    return "\(y)-\(m < 10 ? "0\(m)" : "\(m)")-\(d < 10 ? "0\(d)" : "\(d)")"
}

/// Clave de mes «YYYY-MM» en el calendario indicado (compartida con N3 y N4).
func nyxMonthKey(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month], from: date)
    let y = c.year ?? 0
    let m = c.month ?? 0
    return "\(y)-\(m < 10 ? "0\(m)" : "\(m)")"
}

/// Ventana de días de «presupuesto fuera de ritmo» (diseño §6.3): del día 8 al antepenúltimo del mes (`daysInMonth - 2`).
func nyxIsBudgetOffPaceDay(_ dayOfMonth: Int, daysInMonth: Int) -> Bool {
    dayOfMonth >= 8 && dayOfMonth <= daysInMonth - 2
}

private func nyxMedian(_ values: [Int]) -> Int {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

private func nyxBudgetScopeLabel(_ scope: BudgetScope) -> String {
    switch scope {
    case .month: "del mes"
    case .category(let category): "de \(category.displayName)"
    }
}

/// «Tu gasto normal»: mediana por comercio (últimos 180 días, ≥ 3 pagos) y media mensual por categoría (3 últimos meses completos).
/// Se calcula cada vez desde el libro; nunca se guarda aparte.
public struct NyxBaselines: Equatable, Sendable {
    public let merchantUsualCents: [String: Int]
    public let categoryAverageCents: [SpendingCategory: Int]
    public let fullMonths: Int

    public init(merchantUsualCents: [String: Int], categoryAverageCents: [SpendingCategory: Int], fullMonths: Int) {
        self.merchantUsualCents = merchantUsualCents
        self.categoryAverageCents = categoryAverageCents
        self.fullMonths = fullMonths
    }
}

public func nyxBaselines(in state: LedgerState, now: Date, calendar: Calendar) -> NyxBaselines {
    let exclusions = spendingExclusions(in: state, now: now)
    let subKeys = subscriptionKeys(in: state, now: now, calendar: calendar, notSpending: exclusions)
    return computeNyxBaselines(in: state, now: now, calendar: calendar, exclusions: exclusions, subKeys: subKeys)
}

private func computeNyxBaselines(in state: LedgerState, now: Date, calendar: Calendar,
                                 exclusions: Set<UUID>, subKeys: Set<String>) -> NyxBaselines {
    let cutoff180 = now.addingTimeInterval(-180 * 86_400)
    var byMerchant: [String: [Int]] = [:]
    for m in spendingMovements(in: state.movements, notSpending: exclusions)
    where m.date >= cutoff180 && movementCounts(m, upTo: now, calendar: calendar) {
        let key = normalizeMerchant(m.merchant ?? "")
        guard !key.isEmpty else { continue }
        byMerchant[key, default: []].append(abs(m.amountCents))
    }
    var merchantUsual: [String: Int] = [:]
    for (key, amounts) in byMerchant where amounts.count >= 3 {
        merchantUsual[key] = nyxMedian(amounts)
    }

    let fullMonths: Int
    if let first = state.movements.map(\.date).min(),
       let firstMonth = calendar.dateInterval(of: .month, for: first)?.start,
       let monthStart = calendar.dateInterval(of: .month, for: now)?.start {
        // Solo cuenta el mes inicial como completo si el primer movimiento cayó el día 1; si no, empieza en el siguiente.
        let firstFullMonth: Date
        if calendar.component(.day, from: first) == 1 {
            firstFullMonth = firstMonth
        } else {
            firstFullMonth = calendar.date(byAdding: .month, value: 1, to: firstMonth) ?? monthStart
        }
        if firstFullMonth < monthStart {
            fullMonths = max(0, calendar.dateComponents([.month], from: firstFullMonth, to: monthStart).month ?? 0)
        } else {
            fullMonths = 0
        }
    } else {
        fullMonths = 0
    }

    // La media usa solo meses completos: el primer mes a medias no la diluye.
    let averages = averageMonthlySpendingByCategory(in: state, before: now, months: min(3, fullMonths), calendar: calendar,
                                                    notSpending: exclusions, subscriptionKeys: subKeys)?.byCategory ?? [:]

    return NyxBaselines(merchantUsualCents: merchantUsual, categoryAverageCents: averages, fullMonths: fullMonths)
}

/// Observaciones de dinero: espejos de `immediateAlerts` sobre `newMovementIDs` y vigilantes de estado (cobros que no caben,
/// presupuestos y gasto por categoría por encima de lo habitual). Sin duplicados, ordenadas por prioridad y fecha.
public func nyxMoneyObservations(state: LedgerState, book: AccountBook, newMovementIDs: [UUID],
                                 moment: NyxMoment, now: Date, calendar: Calendar) -> [NyxObservation] {
    let exclusions = spendingExclusions(in: state, now: now)
    let subs = activeSubscriptions(in: state, now: now, calendar: calendar, notSpending: exclusions)
    let subKeys = Set(subs.map(\.id))
    let index = MerchantIndex(state.movements, notSpending: exclusions)
    let movementsByID = Dictionary(state.movements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let ledger = Ledger(state: state)
    let statuses = budgetStatuses(in: state, month: now, now: now, calendar: calendar,
                                  notSpending: exclusions, subscriptionKeys: subKeys)
    let viaInstant = (moment == .notice)

    var raw: [NyxObservation] = []

    // 1. Espejos de `immediateAlerts` para cada movimiento nuevo.
    for id in newMovementIDs {
        guard let m = movementsByID[id] else { continue }
        let alerts = immediateAlerts(afterStoring: m, in: state, now: now, calendar: calendar, notSpending: exclusions)
        let merchantName = m.displayMerchant ?? m.merchant
        let merchantKey = normalizeMerchant(m.merchant ?? "")

        for alert in alerts {
            switch alert.kind {
            case .unusualPayment:
                let previous = index.payments(for: merchantKey)
                    .filter { $0.id != m.id && $0.date <= m.date }
                    .map { abs($0.amountCents) }
                let usual = previous.isEmpty ? nil : nyxMedian(previous)
                raw.append(NyxObservation(
                    situation: .unusualPayment,
                    subject: m.id.uuidString,
                    priority: .normal,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: merchantName, bank: m.bank, movementID: m.id,
                                    cents: abs(m.amountCents), usualCents: usual),
                    viaInstantAlert: viaInstant))

            case .largePayment:
                raw.append(NyxObservation(
                    situation: .largePayment,
                    subject: m.id.uuidString,
                    priority: .normal,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: merchantName, bank: m.bank, movementID: m.id,
                                    cents: abs(m.amountCents)),
                    viaInstantAlert: viaInstant))

            case .duplicateCharge:
                raw.append(NyxObservation(
                    situation: .duplicateCharge,
                    subject: m.id.uuidString,
                    priority: .urgent,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: merchantName, bank: m.bank, movementID: m.id,
                                    cents: abs(m.amountCents)),
                    viaInstantAlert: viaInstant))

            case .subscriptionPriceChange:
                let up = alert.facts.up ?? false
                let sub = subs.first { $0.id == merchantKey && $0.bank == m.bank && $0.lastDate == m.date }
                let lastDate = sub?.lastDate ?? m.date
                let subKey = sub?.id ?? merchantKey
                let diff = sub.flatMap { s in s.previousAmountCents.map { abs(s.amountCents - $0) } }
                raw.append(NyxObservation(
                    situation: up ? .subscriptionUp : .subscriptionDown,
                    subject: "\(m.bank.rawValue)|\(subKey)|\(nyxDayKey(lastDate, calendar))",
                    priority: up ? .normal : .quiet,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: sub?.merchant ?? merchantName, bank: m.bank, movementID: m.id,
                                    cents: sub?.amountCents ?? abs(m.amountCents), differenceCents: diff, day: lastDate),
                    viaInstantAlert: viaInstant))

            case .salary:
                raw.append(NyxObservation(
                    situation: .salary,
                    subject: m.id.uuidString,
                    priority: .normal,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: merchantName, bank: m.bank, movementID: m.id,
                                    cents: abs(m.amountCents)),
                    viaInstantAlert: viaInstant))

            case .largeIncome:
                raw.append(NyxObservation(
                    situation: .largeIncome,
                    subject: m.id.uuidString,
                    priority: .normal,
                    observedAt: m.date,
                    facts: NyxFacts(merchant: merchantName, bank: m.bank, movementID: m.id,
                                    cents: abs(m.amountCents)),
                    viaInstantAlert: viaInstant))

            case .lowBalance:
                raw.append(NyxObservation(
                    situation: .lowBalance,
                    subject: "\(m.bank.rawValue)|\(nyxDayKey(now, calendar))",
                    priority: .normal,
                    observedAt: m.date,
                    facts: NyxFacts(bank: m.bank, movementID: m.id, balanceCents: ledger.balance(m.bank)?.cents),
                    viaInstantAlert: viaInstant))

            case .budgetWarning, .budgetExceeded:
                let parts = alert.id.split(separator: "|")
                let targetID = parts.count > 1 ? String(parts[1]) : nil
                let matched = statuses.first { status in
                    if let targetID { return status.id == targetID }
                    return nyxBudgetScopeLabel(status.scope) == alert.facts.budgetScope
                }
                if let status = matched {
                    let cat: SpendingCategory? = switch status.scope {
                    case .month: nil
                    case .category(let c): c
                    }
                    raw.append(NyxObservation(
                        situation: alert.kind == .budgetExceeded ? .budgetExceeded : .budgetNear,
                        subject: "\(status.id)|\(nyxMonthKey(m.date, calendar))",
                        priority: .normal,
                        observedAt: m.date,
                        facts: NyxFacts(bank: m.bank, movementID: m.id, spentCents: status.spentCents,
                                        limitCents: status.limitCents, remainingCents: status.remainingCents,
                                        percent: status.percent, budgetScope: nyxBudgetScopeLabel(status.scope),
                                        category: cat),
                        viaInstantAlert: viaInstant))
                }

            case .weeklyDigest, .subscriptionUpcoming, .spendingPace:
                break
            }
        }
    }

    // 2. Cobros que no caben (mismas reglas y saldos que el resumen diario).
    let input = briefingInput(state: state, portfolio: nil, book: book,
                              record: BriefingRecord(shownAt: now, since: now),
                              isFirst: false, now: now, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    for shortfall in input.shortfalls {
        let chargeDay = calendar.startOfDay(for: shortfall.charge.date)
        let daysUntil = calendar.dateComponents([.day], from: today, to: chargeDay).day ?? 3
        let priority: NyxPriority = daysUntil <= 1 ? .urgent : .normal
        let subject = "\(shortfall.bank.rawValue)|\(normalizeMerchant(shortfall.charge.name))|\(nyxDayKey(chargeDay, calendar))"
        raw.append(NyxObservation(
            situation: .shortfall,
            subject: subject,
            priority: priority,
            observedAt: now,
            facts: NyxFacts(merchant: shortfall.charge.name, bank: shortfall.bank, otherBank: shortfall.suggestedFrom,
                            cents: shortfall.charge.cents, balanceCents: shortfall.balanceCents,
                            suggestedCents: shortfall.suggestedCents, day: chargeDay),
            viaInstantAlert: false))
    }

    // 3. Presupuestos (cerca del límite, superado o fuera de ritmo). Se producen aunque `alertSettings.budgets` esté apagado;
    //    la regla 4 de `nyxDecide` los mantiene solo en la lista.
    let monthKey = nyxMonthKey(now, calendar)
    let dayOfMonth = calendar.component(.day, from: now)
    let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
    for status in statuses {
        let cat: SpendingCategory? = switch status.scope {
        case .month: nil
        case .category(let c): c
        }
        let facts = NyxFacts(spentCents: status.spentCents, limitCents: status.limitCents,
                             remainingCents: status.remainingCents, percent: status.percent,
                             budgetScope: nyxBudgetScopeLabel(status.scope), category: cat)
        let subject = "\(status.id)|\(monthKey)"
        switch status.level {
        case .exceeded:
            raw.append(NyxObservation(situation: .budgetExceeded, subject: subject, priority: .normal,
                                      observedAt: now, facts: facts, viaInstantAlert: false))
        case .warning:
            raw.append(NyxObservation(situation: .budgetNear, subject: subject, priority: .normal,
                                      observedAt: now, facts: facts, viaInstantAlert: false))
        case .ok:
            // Del día 8 al antepenúltimo del mes (diseño §6.3), por debajo del 80 %, gastado ≥ 20 € y proyección ≥ 110 %.
            if nyxIsBudgetOffPaceDay(dayOfMonth, daysInMonth: daysInMonth), status.spentCents >= 2_000,
               status.spentCents * daysInMonth * 100 >= status.limitCents * 110 * dayOfMonth {
                raw.append(NyxObservation(situation: .budgetOffPace, subject: subject, priority: .normal,
                                          observedAt: now, facts: facts, viaInstantAlert: false))
            }
        }
    }

    // 4. Categorías sin presupuesto por encima de su media habitual.
    let baselines = computeNyxBaselines(in: state, now: now, calendar: calendar, exclusions: exclusions, subKeys: subKeys)
    if baselines.fullMonths >= 2 {
        let current = monthSpending(in: state, month: now, now: now, calendar: calendar,
                                    notSpending: exclusions, subscriptionKeys: subKeys)
        for spend in current.byCategory {
            let category = spend.category
            guard (state.budgets.byCategory[category] ?? 0) <= 0 else { continue }
            guard let average = baselines.categoryAverageCents[category], average >= 5_000 else { continue }
            guard spend.cents * 100 > average * 130 else { continue }
            raw.append(NyxObservation(
                situation: .categoryAboveNormal,
                subject: "\(category.rawValue)|\(monthKey)",
                priority: .quiet,
                observedAt: now,
                facts: NyxFacts(usualCents: average, spentCents: spend.cents, category: category),
                viaInstantAlert: false))
        }
    }

    // Sin duplicados por id (gana la primera, preservando `viaInstantAlert: true` en el momento aviso).
    var seen = Set<String>()
    var unique: [NyxObservation] = []
    for obs in raw where seen.insert(obs.id).inserted {
        unique.append(obs)
    }
    return unique.sorted { a, b in
        if a.priority != b.priority { return a.priority < b.priority }
        if a.observedAt != b.observedAt { return a.observedAt < b.observedAt }
        return a.id < b.id
    }
}
