import Foundation

/// Respuesta del asistente: líneas construidas con `BriefingPart` (para el modo privado y las acciones) y fichas sugeridas.
public struct AssistantAnswer: Equatable, Sendable {
    public let intent: AssistantIntent
    public let lines: [BriefingLine]
    public let chips: [AssistantChip]
    /// true cuando la pregunta pedía un consejo de inversión y la primera línea es `investmentAdviceRefusal`.
    public let isAdviceRefusal: Bool

    public init(intent: AssistantIntent, lines: [BriefingLine], chips: [AssistantChip] = [], isAdviceRefusal: Bool = false) {
        self.intent = intent
        self.lines = lines
        self.chips = chips
        self.isAdviceRefusal = isAdviceRefusal
    }
}

/// Texto fijo cuando no se entiende la pregunta (A3, A5).
public let assistantUnknownMessage =
    "No he entendido esa pregunta. Puedo contarte tus saldos, gastos del mes o de un comercio, mayores pagos, ingresos, traspasos, suscripciones, próximos cobros, presupuestos, dinero libre y cómo van tus inversiones."

// MARK: Entrada principal

/// Responde a una pregunta del dueño con hechos calculados por el Core.
/// Si `modelIntent` viene del modelo del dispositivo y es concreta, se usa; si no, manda el enrutador determinista.
/// Cualquier petición de consejo devuelve siempre `investmentAdviceRefusal` diga lo que diga `modelIntent`.
public func answerQuestion(_ question: String, state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                           briefingInput precomputedBriefing: BriefingInput? = nil,
                           modelIntent: AssistantIntent? = nil, now: Date, calendar: Calendar) -> AssistantAnswer {
    if isAdviceRequest(question, portfolio: portfolio) {
        let folded = withoutFormatCharacters(question)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let tokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let pos = extractPositionQuery(tokens: tokens, joined: " " + tokens.joined(separator: " ") + " ", portfolio: portfolio)
        return answerIntent(.adviceRequest(positionQuery: pos), state: state, portfolio: portfolio, book: book,
                            briefingInput: precomputedBriefing, now: now, calendar: calendar)
    }
    let resolved: AssistantIntent
    if let modelIntent, modelIntent != .unknown {
        resolved = modelIntent
    } else {
        resolved = routeAssistantQuestion(question, state: state, portfolio: portfolio, now: now, calendar: calendar)
    }
    return answerIntent(resolved, state: state, portfolio: portfolio, book: book,
                        briefingInput: precomputedBriefing, now: now, calendar: calendar)
}

/// Responde a una intención ya resuelta con hechos del libro, la cartera y el cuaderno de cuentas.
public func answerIntent(_ intent: AssistantIntent, state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                         briefingInput precomputedBriefing: BriefingInput? = nil,
                         now: Date, calendar: Calendar) -> AssistantAnswer {
    switch intent {
    case .balances(let bank):
        return AssistantAnswer(intent: intent, lines: balancesAnswer(bank: bank, state: state))
    case let .spending(month, category, merchant):
        return AssistantAnswer(intent: intent,
                               lines: spendingAnswer(month: month, category: category, merchant: merchant,
                                                     state: state, now: now, calendar: calendar))
    case .biggestPayments(let month):
        return AssistantAnswer(intent: intent,
                               lines: biggestPaymentsAnswer(month: month, state: state, now: now, calendar: calendar))
    case .subscriptions:
        return AssistantAnswer(intent: intent,
                               lines: subscriptionsAnswer(state: state, now: now, calendar: calendar))
    case .upcomingCharges(let bank):
        return AssistantAnswer(intent: intent,
                               lines: upcomingChargesAnswer(bank: bank, state: state, book: book, now: now, calendar: calendar))
    case .budgets(let category):
        return AssistantAnswer(intent: intent,
                               lines: budgetsAnswer(category: category, state: state, now: now, calendar: calendar))
    case .income(let month):
        return AssistantAnswer(intent: intent,
                               lines: incomeAnswer(month: month, state: state, now: now, calendar: calendar))
    case .ownTransfers(let month):
        return AssistantAnswer(intent: intent,
                               lines: ownTransfersAnswer(month: month, state: state, now: now, calendar: calendar))
    case .freeMoney:
        return AssistantAnswer(intent: intent,
                               lines: freeMoneyAnswer(state: state, book: book, now: now, calendar: calendar))
    case let .investments(positionQuery, moversOnly):
        return AssistantAnswer(intent: intent,
                               lines: investmentsAnswer(positionQuery: positionQuery, moversOnly: moversOnly,
                                                        portfolio: portfolio, now: now, calendar: calendar))
    case .briefingRecap:
        return AssistantAnswer(intent: intent,
                               lines: briefingRecapAnswer(state: state, portfolio: portfolio, book: book,
                                                          precomputed: precomputedBriefing, now: now, calendar: calendar))
    case .adviceRequest(let positionQuery):
        var lines = [BriefingLine(id: "advice-refusal", parts: [.text(investmentAdviceRefusal)])]
        if let portfolio, let summary = portfolioSummary(portfolio, now: now, calendar: calendar) {
            if let q = positionQuery, let matched = matchPosition(query: q, in: summary.positions) {
                lines += positionLines(matched, now: now, calendar: calendar)
            } else {
                lines += portfolioOverviewLines(summary, now: now, calendar: calendar)
            }
        }
        let chips = [
            AssistantChip(id: "investments", label: "¿Cómo van mis inversiones?"),
            AssistantChip(id: "balances", label: "¿Cuánto tengo?"),
            AssistantChip(id: "upcoming", label: "¿Qué cobros vienen?"),
        ]
        return AssistantAnswer(intent: intent, lines: lines, chips: chips, isAdviceRefusal: true)
    case .unknown:
        let chips = suggestedAssistantChips(state: state, portfolio: portfolio, now: now, calendar: calendar)
        return AssistantAnswer(intent: intent,
                               lines: [BriefingLine(id: "unknown", parts: [.text(assistantUnknownMessage)])],
                               chips: chips)
    }
}

// MARK: Ayudas de formato y calendario (igual en Linux y en iOS)

private let assistantWeekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
private let assistantShortMonths = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
private let assistantFullMonths = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                                   "octubre", "noviembre", "diciembre"]

private func assistantWeekday(_ date: Date, _ calendar: Calendar) -> String {
    assistantWeekdayNames[((calendar.component(.weekday, from: date) - 1) % 7 + 7) % 7]
}

private func assistantShortDate(_ date: Date, _ calendar: Calendar) -> String {
    let m = calendar.component(.month, from: date)
    return "\(calendar.component(.day, from: date)) \(assistantShortMonths[(m - 1 + 12) % 12])"
}

private func assistantClock(_ date: Date, _ calendar: Calendar) -> String {
    let h = calendar.component(.hour, from: date), m = calendar.component(.minute, from: date)
    return (h < 10 ? "0" : "") + String(h) + ":" + (m < 10 ? "0" : "") + String(m)
}

private func assistantDayDistance(from a: Date, to b: Date, _ calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
}

private func assistantDayOrShortDate(_ date: Date, now: Date, _ calendar: Calendar) -> String {
    let dist = assistantDayDistance(from: now, to: date, calendar)
    switch dist {
    case ...0: return "Hoy"
    case 1: return "Mañana"
    case 2...6: return "\(assistantCapitalized(assistantWeekday(date, calendar))) \(calendar.component(.day, from: date))"
    default: return assistantShortDate(date, calendar)
    }
}

private func assistantCapitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

private func assistantPlural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

private func assistantJoinList(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    default: return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
    }
}

private struct ResolvedMonth {
    let start: Date
    let upper: Date
    let upperInclusive: Bool
    let isCurrent: Bool
    let isFuture: Bool
    /// «este mes», «el mes pasado», «en octubre», «en octubre de 2025».
    let phrase: String
    /// «octubre», «octubre de 2025» (para «Aún no ha llegado …»).
    let bareName: String

    func contains(_ date: Date) -> Bool {
        date >= start && (upperInclusive ? date <= upper : date < upper)
    }
}

private func resolveMonth(_ month: AssistantMonth, now: Date, calendar: Calendar) -> ResolvedMonth? {
    guard let start = month.resolvedStart(now: now, calendar: calendar),
          let interval = calendar.dateInterval(of: .month, for: start),
          let nowMonthStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
    let year = calendar.component(.year, from: start)
    let monthNum = calendar.component(.month, from: start)
    let nowYear = calendar.component(.year, from: now)
    let name = assistantFullMonths[(monthNum - 1 + 12) % 12]
    let bareName = year == nowYear ? name : "\(name) de \(year)"
    let isCurrent = start == nowMonthStart
    let isFuture = start > nowMonthStart
    let phrase: String
    switch month {
    case .current: phrase = "este mes"
    case .previous: phrase = "el mes pasado"
    case .specific: phrase = isCurrent ? "este mes" : "en \(bareName)"
    }
    let upper = isCurrent ? now : interval.end
    return ResolvedMonth(start: interval.start, upper: upper, upperInclusive: isCurrent,
                         isCurrent: isCurrent, isFuture: isFuture, phrase: phrase, bareName: bareName)
}

private func previousMonthName(before monthStart: Date, calendar: Calendar) -> String {
    let prev = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
    let idx = (calendar.component(.month, from: prev) - 1 + 12) % 12
    return assistantFullMonths[idx]
}

// MARK: 1. Saldos

private func balancesAnswer(bank: BankID?, state: LedgerState) -> [BriefingLine] {
    let ledger = Ledger(state: state)
    if let bank {
        guard let b = ledger.balance(bank) else {
            return [BriefingLine(id: "bal-\(bank.rawValue)", parts: [.text("Aún no tengo el saldo de \(bank.displayName).")])]
        }
        return [BriefingLine(id: "bal-\(bank.rawValue)",
                             parts: [.text("En \(bank.displayName) tienes \(b.estimated ? "unos " : "")"), .amount(b.cents), .text(".")])]
    }

    var known: [(bank: BankID, cents: Int, estimated: Bool)] = []
    var leftOut: [BankID] = []
    for b in BankID.allCases {
        if let reading = ledger.balance(b) {
            known.append((b, reading.cents, reading.estimated))
        } else if state.links[b] != nil || state.movements.contains(where: { $0.bank == b && !$0.flaggedNotMine }) {
            leftOut.append(b)
        }
    }
    guard let total = ledger.total(), !known.isEmpty else {
        return [BriefingLine(id: "bal-empty", parts: [.text("Aún no tengo ningún saldo guardado.")])]
    }
    let approx = known.contains(where: \.estimated)
    let missingSuffix = leftOut.isEmpty ? "" : ", sin contar \(assistantJoinList(leftOut.map(\.displayName)))"
    var lines = [BriefingLine(id: "bal-total",
                              parts: [.text(approx ? "En total tienes unos " : "En total tienes "), .amount(total),
                                      .text("\(missingSuffix).")])]
    for item in known {
        lines.append(BriefingLine(id: "bal-\(item.bank.rawValue)",
                                  parts: [.text("\(item.bank.displayName): \(item.estimated ? "unos " : "")"), .amount(item.cents)]))
    }
    for missing in leftOut {
        lines.append(BriefingLine(id: "bal-\(missing.rawValue)",
                                  parts: [.text("\(missing.displayName): aún sin saldo")]))
    }
    return lines
}

// MARK: 2. Gastos (mes, categoría o comercio)

private func tokenRunContains(_ haystack: [String], _ needle: [String]) -> Bool {
    guard !needle.isEmpty, needle.count <= haystack.count else { return false }
    for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
        return true
    }
    return false
}

private func movementMatchesMerchant(_ m: Movement, queryKey: String) -> Bool {
    let qTokens = queryKey.split(separator: " ").map(String.init)
    guard !qTokens.isEmpty else { return false }
    for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
        let key = normalizeMerchant(raw)
        if key == queryKey { return true }
        let mTokens = key.split(separator: " ").map(String.init)
        if tokenRunContains(mTokens, qTokens) { return true }
    }
    return false
}

private func spendingAnswer(month: AssistantMonth, category: SpendingCategory?, merchant: String?,
                            state: LedgerState, now: Date, calendar: Calendar) -> [BriefingLine] {
    guard let resolved = resolveMonth(month, now: now, calendar: calendar) else {
        return [BriefingLine(id: "spend-invalid", parts: [.text("No reconozco ese mes.")])]
    }
    if resolved.isFuture {
        return [BriefingLine(id: "spend-future", parts: [.text("Aún no ha llegado \(resolved.bareName).")])]
    }
    let exclusions = spendingExclusions(in: state, now: now)

    // Subcaso A: por comercio («¿cuánto llevo en Mercadona?»).
    if let merchant {
        let key = normalizeMerchant(merchant)
        let matched = spendingMovements(in: state.movements, notSpending: exclusions)
            .filter { resolved.contains($0.date) && abs($0.amountCents) > 0 && movementMatchesMerchant($0, queryKey: key) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
        let display = clippedName(matched.first?.displayMerchant ?? matched.first?.merchant ?? merchant)
        guard !matched.isEmpty else {
            let line = resolved.isCurrent
                ? "Este mes no tienes pagos en \(display)."
                : "No tienes pagos en \(display) \(resolved.phrase)."
            return [BriefingLine(id: "spend-merchant-empty", parts: [.text(line)])]
        }
        let total = matched.reduce(0) { $0 + abs($1.amountCents) }
        let countText = "(\(matched.count) \(assistantPlural(matched.count, "pago", "pagos")))"
        let headParts: [BriefingPart] = resolved.isCurrent
            ? [.text("Este mes llevas "), .amount(total), .text(" en \(display) \(countText).")]
            : [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(total), .text(" en \(display) \(countText).")]
        var lines = [BriefingLine(id: "spend-merchant", parts: headParts,
                                  action: matched.count == 1 ? .openMovement(matched[0].id) : nil)]
        if matched.count > 1 {
            for m in matched.prefix(3) {
                lines.append(BriefingLine(id: "spend-merchant-\(m.id.uuidString)",
                                          parts: [.text("\(assistantShortDate(m.date, calendar)): "), .amount(abs(m.amountCents)),
                                                  .text(" con \(m.bank.displayName)")],
                                          action: .openMovement(m.id)))
            }
            if matched.count > 3 {
                lines.append(BriefingLine(id: "spend-merchant-rest",
                                          parts: [.text("Y \(matched.count - 3) \(assistantPlural(matched.count - 3, "pago", "pagos")) más.")]))
            }
        }
        return lines
    }

    let spending = monthSpending(in: state, month: resolved.start, now: now, calendar: calendar, notSpending: exclusions)
    let prevName = previousMonthName(before: resolved.start, calendar: calendar)

    // Subcaso B: por categoría.
    if let category {
        guard let row = spending.byCategory.first(where: { $0.category == category }), row.cents > 0 else {
            return [BriefingLine(id: "spend-cat-empty",
                                 parts: [.text("No tienes gastos en \(category.displayName) \(resolved.phrase).")])]
        }
        let countText = "(\(row.count) \(assistantPlural(row.count, "pago", "pagos")))"
        let firstParts: [BriefingPart] = resolved.isCurrent
            ? [.text("Este mes llevas "), .amount(row.cents), .text(" en \(category.displayName) \(countText).")]
            : [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(row.cents), .text(" en \(category.displayName) \(countText).")]
        var lines = [BriefingLine(id: "spend-cat", parts: firstParts)]
        if row.previousCents > 0 {
            lines.append(monthComparisonLine(id: "spend-cat-cmp", diff: row.cents - row.previousCents,
                                             prevName: prevName, samePoint: resolved.isCurrent))
        }
        return lines
    }

    // Subcaso C: total del mes.
    guard spending.totalCents > 0 else {
        let text = resolved.isCurrent ? "Este mes aún no tienes gastos registrados." : "No tengo gastos registrados \(resolved.phrase)."
        return [BriefingLine(id: "spend-empty", parts: [.text(text)])]
    }
    var lines: [BriefingLine] = []
    if resolved.isCurrent, let forecast = monthForecast(in: state, now: now, calendar: calendar, notSpending: exclusions) {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("Este mes llevas "), .amount(spending.totalCents),
                                          .text(" gastados; a este ritmo acabarás en unos "), .whole(forecast.projectedCents), .text(".")]))
    } else if resolved.isCurrent {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("Este mes llevas "), .amount(spending.totalCents), .text(" gastados.")]))
    } else {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(spending.totalCents), .text(".")]))
    }
    if spending.previousTotalCents > 0 {
        lines.append(monthComparisonLine(id: "spend-cmp", diff: spending.totalCents - spending.previousTotalCents,
                                         prevName: prevName, samePoint: resolved.isCurrent))
    }
    if let top = spending.byCategory.first {
        lines.append(BriefingLine(id: "spend-top-cat",
                                  parts: [.text("Donde más: \(top.category.displayName) ("), .amount(top.cents), .text(").")]))
    }
    return lines
}

private func monthComparisonLine(id: String, diff: Int, prevName: String, samePoint: Bool) -> BriefingLine {
    let tail = samePoint ? " a estas alturas." : "."
    if diff > 0 {
        return BriefingLine(id: id, parts: [.amount(diff), .text(" más que en \(prevName)\(tail)")])
    } else if diff < 0 {
        return BriefingLine(id: id, parts: [.amount(-diff), .text(" menos que en \(prevName)\(tail)")])
    }
    return BriefingLine(id: id, parts: [.text("Igual que en \(prevName)\(tail)")])
}

// MARK: 3. Mayores pagos

private func biggestPaymentsAnswer(month: AssistantMonth, state: LedgerState, now: Date,
                                   calendar: Calendar) -> [BriefingLine] {
    guard let resolved = resolveMonth(month, now: now, calendar: calendar) else {
        return [BriefingLine(id: "big-invalid", parts: [.text("No reconozco ese mes.")])]
    }
    if resolved.isFuture {
        return [BriefingLine(id: "big-future", parts: [.text("Aún no ha llegado \(resolved.bareName).")])]
    }
    let exclusions = spendingExclusions(in: state, now: now)
    let payments = spendingMovements(in: state.movements, notSpending: exclusions)
        .filter { resolved.contains($0.date) && abs($0.amountCents) > 0 }
        .sorted { a, b in
            let aa = abs(a.amountCents), bb = abs(b.amountCents)
            if aa != bb { return aa > bb }
            if a.date != b.date { return a.date > b.date }
            return a.id.uuidString < b.id.uuidString
        }
    guard !payments.isEmpty else {
        return [BriefingLine(id: "big-empty", parts: [.text("No tienes pagos registrados \(resolved.phrase).")])]
    }
    let header = payments.count == 1 ? "Tu mayor pago \(resolved.phrase):" : "Tus mayores pagos \(resolved.phrase):"
    var lines = [BriefingLine(id: "big-head", parts: [.text(header)])]
    for m in payments.prefix(5) {
        let name = clippedName(m.displayMerchant ?? m.merchant ?? m.bank.displayName)
        lines.append(BriefingLine(id: "big-\(m.id.uuidString)",
                                  parts: [.text("\(name): "), .amount(abs(m.amountCents)),
                                          .text(" (\(assistantShortDate(m.date, calendar)) · \(m.bank.displayName))")],
                                  action: .openMovement(m.id)))
    }
    return lines
}

// MARK: 4. Suscripciones

private func subscriptionsAnswer(state: LedgerState, now: Date, calendar: Calendar) -> [BriefingLine] {
    let exclusions = spendingExclusions(in: state, now: now)
    let subs = activeSubscriptions(in: state, now: now, calendar: calendar, notSpending: exclusions)
    guard !subs.isEmpty else {
        return [BriefingLine(id: "subs-empty", parts: [.text("No tengo suscripciones activas detectadas.")])]
    }
    let totals = subscriptionTotals(subs)
    let charges = subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions)
    var lines = [BriefingLine(id: "subs-total",
                              parts: [.text("Tienes \(subs.count) \(assistantPlural(subs.count, "suscripción activa", "suscripciones activas")): "),
                                      .amount(totals.monthlyCents), .text(" al mes ("), .amount(totals.yearlyCents), .text(" al año).")])]
    if charges.isEmpty {
        for sub in subs.prefix(5) {
            lines.append(BriefingLine(id: "sub-\(sub.bank.rawValue)-\(sub.id)",
                                      parts: [.text("\(clippedName(sub.merchant)): "), .amount(sub.amountCents),
                                              .text(" en \(sub.bank.displayName) · próximo el \(assistantShortDate(sub.nextDate, calendar))")]))
        }
    } else {
        for (i, charge) in charges.prefix(5).enumerated() {
            let note = overdueNote(charge, calendar: calendar).map { " (\($0))" } ?? ""
            lines.append(BriefingLine(id: "sub-charge-\(i)",
                                      parts: [.text("\(clippedName(charge.name)): "), .amount(charge.cents),
                                              .text(" en \(charge.bank.displayName) · \(assistantDayOrShortDate(charge.date, now: now, calendar))\(note)")]))
        }
        if charges.count > 5 {
            lines.append(BriefingLine(id: "sub-rest", parts: [.text("Y \(charges.count - 5) más.")]))
        }
    }
    return lines
}

// MARK: 5. Próximos cobros y faltas de saldo

private func upcomingChargesAnswer(bank: BankID?, state: LedgerState, book: AccountBook, now: Date,
                                   calendar: Calendar) -> [BriefingLine] {
    let days = upcomingCalendar(state: state, book: book, now: now, calendar: calendar)
    let charges = days.flatMap(\.charges).filter { bank == nil || $0.bank == bank }
    let expected = days.flatMap(\.expectedIncome).filter { bank == nil || $0.bank == bank }
    guard !charges.isEmpty || !expected.isEmpty else {
        let scope = bank.map { " en \($0.displayName)" } ?? ""
        return [BriefingLine(id: "up-empty", parts: [.text("No veo cobros próximos\(scope) para los próximos \(upcomingCalendarDays) días.")])]
    }

    var lines: [BriefingLine] = []
    for (i, charge) in charges.prefix(5).enumerated() {
        let note = overdueNote(charge, calendar: calendar).map { " (\($0))" } ?? ""
        lines.append(BriefingLine(id: "up-charge-\(i)",
                                  parts: [.text("\(assistantDayOrShortDate(charge.date, now: now, calendar)): \(clippedName(charge.name)), "),
                                          .amount(charge.cents), .text(" en \(charge.bank.displayName)\(note)")]))
    }
    if charges.count > 5 {
        let rem = charges.count - 5
        lines.append(BriefingLine(id: "up-rest",
                                  parts: [.text("Y \(rem) \(assistantPlural(rem, "cobro", "cobros")) más en los próximos \(upcomingCalendarDays) días.")]))
    }
    for (i, inc) in expected.enumerated() {
        lines.append(BriefingLine(id: "up-expected-\(i)",
                                  parts: [.text("Hacia el \(assistantShortDate(inc.date, calendar)): \(clippedName(inc.name)), unos "),
                                          .amount(inc.cents), .text(" en \(inc.bank.displayName)")]))
    }

    // Comprobación de si algún banco se queda corto.
    let ledger = Ledger(state: state)
    var balances: [BankID: Int] = [:]
    var estimated = Set<BankID>()
    for b in BankID.allCases {
        guard let reading = ledger.balance(b) else { continue }
        balances[b] = reading.cents
        if reading.estimated { estimated.insert(b) }
    }
    let urgent = shortfalls(balances: balances, floors: book.floors, upcoming: charges, now: now, calendar: calendar,
                            estimated: estimated).filter { bank == nil || $0.bank == bank }
    let belowFloor = firstBelowFloorDays(days).filter { bank == nil || $0.key == bank }
    let chargeBanks = BankID.allCases.filter { b in charges.contains { $0.bank == b } }
    let unknownBanks = chargeBanks.filter { balances[$0] == nil }

    if !urgent.isEmpty {
        for (i, s) in urgent.enumerated() {
            lines.append(shortfallLine(id: "up-shortfall-\(i)", shortfall: s, now: now, calendar: calendar))
        }
    } else if !belowFloor.isEmpty {
        for b in BankID.allCases {
            guard let firstDay = belowFloor[b] else { continue }
            lines.append(BriefingLine(id: "up-below-\(b.rawValue)",
                                      parts: [.text("Ojo: \(b.displayName) bajaría de su mínimo el \(assistantShortDate(firstDay, calendar)).")],
                                      action: .moveMoney(from: nil, to: b, cents: nil)))
        }
    } else if !charges.isEmpty && unknownBanks.isEmpty {
        lines.append(BriefingLine(id: "up-ok",
                                  parts: [.text("Con el saldo actual, llega para estos cobros (sin contar otros gastos).")]))
    }
    if !unknownBanks.isEmpty {
        let names = assistantJoinList(unknownBanks.map(\.displayName))
        lines.append(BriefingLine(id: "up-unknown-bal",
                                  parts: [.text("No tengo el saldo de \(names), así que no puedo comprobar si llega.")]))
    }
    return lines
}

func shortfallLine(id: String, shortfall s: Shortfall, now: Date, calendar: Calendar) -> BriefingLine {
    let when: String
    switch assistantDayDistance(from: now, to: s.charge.date, calendar) {
    case ...0: when = "Hoy te cobran"
    case 1: when = "Mañana te cobran"
    default: when = "El \(assistantWeekday(s.charge.date, calendar)) \(calendar.component(.day, from: s.charge.date)) te cobran"
    }
    var parts: [BriefingPart] = [
        .text("\(when) \(clippedName(s.charge.name)) ("), .amount(s.charge.cents),
        .text(") en \(s.bank.displayName) y tienes \(s.isEstimated ? "unos " : "")"), .amount(s.balanceCents),
    ]
    if let from = s.suggestedFrom {
        parts += [.text(". Pasa "), .amount(s.suggestedCents), .text(" desde \(from.displayName).")]
        if s.suggestedIsEstimated { parts.append(.text(" El saldo de \(from.displayName) es aproximado.")) }
    } else {
        parts += [.text(". Pásale "), .amount(s.suggestedCents), .text(" antes.")]
    }
    return BriefingLine(id: id, parts: parts, action: .moveMoney(from: s.suggestedFrom, to: s.bank, cents: s.suggestedCents))
}

// MARK: 6. Presupuestos

private func budgetsAnswer(category: SpendingCategory?, state: LedgerState, now: Date, calendar: Calendar) -> [BriefingLine] {
    let exclusions = spendingExclusions(in: state, now: now)
    let statuses = budgetStatuses(in: state, month: now, now: now, calendar: calendar, notSpending: exclusions)
    guard !statuses.isEmpty else {
        return [BriefingLine(id: "bud-empty", parts: [.text("Aún no tienes presupuestos configurados.")], action: .openBudgets)]
    }
    if let category {
        guard let status = statuses.first(where: { $0.scope == .category(category) }) else {
            return [BriefingLine(id: "bud-cat-missing",
                                 parts: [.text("No tienes presupuesto configurado para \(category.displayName).")],
                                 action: .openBudgets)]
        }
        return [budgetStatusLine(status)]
    }
    return statuses.map(budgetStatusLine)
}

private func budgetStatusLine(_ status: BudgetStatus) -> BriefingLine {
    let label: String
    switch status.scope {
    case .month: label = "Presupuesto del mes"
    case .category(let c): label = c.displayName
    }
    if status.level == .exceeded {
        return BriefingLine(id: "bud-\(status.id)",
                            parts: [.text("\(label): te has pasado, llevas "), .amount(status.spentCents),
                                    .text(" de "), .amount(status.limitCents), .text(".")],
                            action: .openBudgets)
    }
    return BriefingLine(id: "bud-\(status.id)",
                        parts: [.text("\(label): llevas "), .amount(status.spentCents), .text(" de "),
                                .amount(status.limitCents), .text(" (te quedan "), .amount(status.remainingCents), .text(").")],
                        action: .openBudgets)
}

// MARK: 7. Ingresos

private func incomeAnswer(month: AssistantMonth, state: LedgerState, now: Date, calendar: Calendar) -> [BriefingLine] {
    guard let resolved = resolveMonth(month, now: now, calendar: calendar) else {
        return [BriefingLine(id: "inc-invalid", parts: [.text("No reconozco ese mes.")])]
    }
    if resolved.isFuture {
        return [BriefingLine(id: "inc-future", parts: [.text("Aún no ha llegado \(resolved.bareName).")])]
    }
    let transfers = ownTransferIDs(in: state.movements)
    let unconfirmed = unconfirmedCaptureIDs(in: state, now: now)
    let excluded = transfers.union(unconfirmed)
    let entries = state.movements.filter {
        $0.kind == .income && !$0.flaggedNotMine && !$0.excludedFromSpending && !excluded.contains($0.id)
            && $0.amountCents > 0 && resolved.contains($0.date)
    }.sorted { a, b in
        if a.amountCents != b.amountCents { return a.amountCents > b.amountCents }
        if a.date != b.date { return a.date > b.date }
        return a.id.uuidString < b.id.uuidString
    }
    guard !entries.isEmpty else {
        return [BriefingLine(id: "inc-empty", parts: [.text("No tienes ingresos registrados \(resolved.phrase).")])]
    }
    let total = entries.reduce(0) { $0 + $1.amountCents }
    let countText = "en \(entries.count) \(assistantPlural(entries.count, "ingreso", "ingresos"))"
    let headParts: [BriefingPart] = resolved.isCurrent
        ? [.text("Este mes han entrado "), .amount(total), .text(" \(countText).")]
        : [.text("\(assistantCapitalized(resolved.phrase)) entraron "), .amount(total), .text(" \(countText).")]
    var lines = [BriefingLine(id: "inc-total", parts: headParts)]
    for m in entries.prefix(3) {
        let name = clippedName(m.displayMerchant ?? m.merchant ?? m.bank.displayName)
        lines.append(BriefingLine(id: "inc-\(m.id.uuidString)",
                                  parts: [.text("\(name): "), .amount(m.amountCents),
                                          .text(" en \(m.bank.displayName) (\(assistantShortDate(m.date, calendar)))")],
                                  action: .openMovement(m.id)))
    }
    if entries.count > 3 {
        let rest = entries.count - 3
        lines.append(BriefingLine(id: "inc-rest",
                                  parts: [.text("Y \(rest) \(assistantPlural(rest, "ingreso", "ingresos")) más.")]))
    }
    return lines
}

// MARK: 8. Traspasos propios

private func ownTransfersAnswer(month: AssistantMonth, state: LedgerState, now: Date, calendar: Calendar) -> [BriefingLine] {
    guard let resolved = resolveMonth(month, now: now, calendar: calendar) else {
        return [BriefingLine(id: "tr-invalid", parts: [.text("No reconozco ese mes.")])]
    }
    if resolved.isFuture {
        return [BriefingLine(id: "tr-future", parts: [.text("Aún no ha llegado \(resolved.bareName).")])]
    }
    let byID = Dictionary(state.movements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let pairs = ownTransferPairs(in: state.movements)
    var pairedIDs = Set<UUID>()
    for p in pairs {
        pairedIDs.insert(p.paymentID)
        pairedIDs.insert(p.incomeID)
    }

    struct TransferRow {
        let id: UUID
        let date: Date
        let cents: Int
        let line: BriefingLine
    }
    var rows: [TransferRow] = []
    for pair in pairs {
        guard let payment = byID[pair.paymentID], let income = byID[pair.incomeID],
              !payment.flaggedNotMine, !income.flaggedNotMine, resolved.contains(payment.date),
              abs(payment.amountCents) > 0 else { continue }
        let cents = abs(payment.amountCents)
        let line = BriefingLine(id: "tr-\(payment.id.uuidString)",
                                parts: [.amount(cents), .text(" de \(payment.bank.displayName) a \(income.bank.displayName) (\(assistantShortDate(payment.date, calendar)))")],
                                action: .openMovement(payment.id))
        rows.append(TransferRow(id: payment.id, date: payment.date, cents: cents, line: line))
    }
    // También los movimientos marcados manualmente como traspaso sin pareja en otro banco.
    for m in state.movements where m.ownTransfer == true && !pairedIDs.contains(m.id) && !m.flaggedNotMine
        && !m.excludedFromSpending && resolved.contains(m.date) && abs(m.amountCents) > 0 {
        let cents = abs(m.amountCents)
        let line = BriefingLine(id: "tr-\(m.id.uuidString)",
                                parts: [.amount(cents), .text(" en \(m.bank.displayName) (\(assistantShortDate(m.date, calendar)), marcado como traspaso)")],
                                action: .openMovement(m.id))
        rows.append(TransferRow(id: m.id, date: m.date, cents: cents, line: line))
    }
    rows.sort { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }

    guard !rows.isEmpty else {
        return [BriefingLine(id: "tr-empty", parts: [.text("No tienes traspasos entre tus cuentas \(resolved.phrase).")])]
    }
    let total = rows.reduce(0) { $0 + $1.cents }
    let countText = "(\(rows.count) \(assistantPlural(rows.count, "traspaso", "traspasos")))"
    let headParts: [BriefingPart] = resolved.isCurrent
        ? [.text("Este mes has movido "), .amount(total), .text(" entre tus cuentas \(countText).")]
        : [.text("\(assistantCapitalized(resolved.phrase)) moviste "), .amount(total), .text(" entre tus cuentas \(countText).")]
    var lines = [BriefingLine(id: "tr-total", parts: headParts)]
    lines += rows.prefix(5).map(\.line)
    if rows.count > 5 {
        lines.append(BriefingLine(id: "tr-rest", parts: [.text("Y \(rows.count - 5) más.")]))
    }
    return lines
}

// MARK: 9. Dinero libre

private func freeMoneyAnswer(state: LedgerState, book: AccountBook, now: Date, calendar: Calendar) -> [BriefingLine] {
    let ledger = Ledger(state: state)
    var balances: [BankID: Int] = [:]
    for b in BankID.allCases {
        if let reading = ledger.balance(b) { balances[b] = reading.cents }
    }
    let dailyBanks: Set<BankID> = [.rev, .ima]
    if balances[.rev] == nil && balances[.ima] == nil {
        return [BriefingLine(id: "free-no-bal",
                             parts: [.text("Aún no tengo el saldo de Revolut ni de imagin para calcular el dinero libre.")])]
    }
    let exclusions = spendingExclusions(in: state, now: now)
    let charges = subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions)
    guard let free = freeMoney(balances: balances, floors: book.floors, banks: dailyBanks, pending: charges,
                               now: now, calendar: calendar) else {
        return [BriefingLine(id: "free-none",
                             parts: [.text("Con tus saldos, mínimos y cobros pendientes de este mes no te queda margen libre (sin contar Trade Republic).")])]
    }
    var firstParts: [BriefingPart] = [.text("Hasta fin de mes te quedan unos "), .whole(free.cents), .text(" libres")]
    // J13: nunca «unos 0 € al día».
    if free.perDayCents.magnitude >= 50 {
        firstParts += [.text(": unos "), .whole(free.perDayCents), .text(" al día, sin contar el gasto del día a día.")]
    } else {
        firstParts.append(.text(", sin contar el gasto del día a día."))
    }
    var lines = [BriefingLine(id: "free-main", parts: firstParts)]
    if !free.missingBanks.isEmpty {
        let names = assistantJoinList(free.missingBanks.map(\.displayName))
        lines.append(BriefingLine(id: "free-missing",
                                  parts: [.text("Sin contar \(names): no tengo su saldo.")]))
    }
    if balances[.tr] != nil {
        lines.append(BriefingLine(id: "free-no-tr", parts: [.text("No incluye Trade Republic.")]))
    }
    return lines
}

// MARK: 10. Inversiones (hechos, nunca consejo)

private func matchPosition(query: String, in list: [PositionValue]) -> PositionValue? {
    let q = normalizeMerchant(query)
    guard !q.isEmpty else { return nil }
    if let exactInstrument = list.first(where: { normalizeMerchant($0.position.instrument) == q }) { return exactInstrument }
    if let exactName = list.first(where: { normalizeMerchant($0.position.name) == q }) { return exactName }
    let qTokens = q.split(separator: " ").map(String.init)
    var best: (score: Int, pv: PositionValue)?
    for pv in list {
        let nameKey = normalizeMerchant(pv.position.name)
        let nameTokens = nameKey.split(separator: " ").map(String.init)
        var score = 0
        if tokenRunContains(nameTokens, qTokens) { score = 50 + q.count }
        else if nameKey.contains(q) && q.count >= 3 { score = 30 + q.count }
        else {
            let hits = qTokens.filter { $0.count >= 3 && nameTokens.contains($0) }
            if !hits.isEmpty { score = 10 * hits.count + hits.reduce(0) { $0 + $1.count } }
        }
        if score > (best?.score ?? 0) { best = (score, pv) }
    }
    return best?.pv
}

private func investmentPriceAge(_ date: Date, now: Date, _ calendar: Calendar, plural: Bool) -> String {
    let word = plural ? "precios" : "precio"
    let time = assistantClock(date, calendar)
    switch assistantDayDistance(from: date, to: now, calendar) {
    case ...0: return "\(word) de las \(time)"
    case 1: return "\(word) de ayer, \(time)"
    default: return "\(word) del \(assistantShortDate(date, calendar)), \(time)"
    }
}

private func positionLines(_ pv: PositionValue, now: Date, calendar: Calendar) -> [BriefingLine] {
    let name = clippedName(pv.position.name)
    guard let val = pv.valueCents else {
        return [BriefingLine(id: "pos-\(pv.id)", parts: [.text("\(name): aún sin precio.")], action: .openInvestments)]
    }
    var first: [BriefingPart] = [.text("\(name): "), .amount(val)]
    if let ch = pv.todayChangeCents, case .market(let at) = pv.origin {
        let when = assistantDayDistance(from: at, to: now, calendar) <= 0
            ? "hoy"
            : "en la última sesión (\(assistantWeekday(at, calendar)))"
        first += [.text(" ("), .signed(ch), .text(" \(when)")]
        if val - ch > 0, let tenths = roundedQuotient(1000 * ch, val - ch) {
            first += [.text(", "), .percentTenths(tenths)]
        }
        first.append(.text(")"))
    }
    first.append(.text("."))
    var lines = [BriefingLine(id: "pos-\(pv.id)", parts: first, action: .openInvestments)]

    var second: [BriefingPart] = []
    if let gain = pv.gainCents {
        second += [.text("Desde la compra: "), .signed(gain)]
        if let tenths = pv.gainTenths { second += [.text(" ("), .percentTenths(tenths), .text(")")] }
    }
    let originText: String?
    switch pv.origin {
    case .market(let at): originText = investmentPriceAge(at, now: now, calendar, plural: false)
    case .manual(let at): originText = "precio puesto a mano el \(assistantShortDate(at, calendar))"
    case .none: originText = nil
    }
    if let originText {
        second.append(.text(second.isEmpty ? assistantCapitalized(originText) : " · " + originText))
    }
    if !second.isEmpty {
        lines.append(BriefingLine(id: "pos-gain-\(pv.id)", parts: second, action: .openInvestments))
    }
    return lines
}

private func portfolioOverviewLines(_ s: PortfolioSummary, now: Date, calendar: Calendar) -> [BriefingLine] {
    guard let value = s.valueCents else {
        return [BriefingLine(id: "inv-value", parts: [.text("Aún no tengo precios de tus inversiones.")], action: .openInvestments)]
    }
    var lines: [BriefingLine] = []
    let partial = s.missingPrices > 0
    var first: [BriefingPart] = [.text(partial ? "Valen al menos " : "Valen "), .amount(value)]
    if partial { first.append(.text(" de las que tienen precio")) }
    if let today = s.todayChangeCents, let day = s.changeDay {
        let when = assistantDayDistance(from: day, to: now, calendar) <= 0
            ? "hoy"
            : "en la última sesión (\(assistantWeekday(day, calendar)))"
        first += [.text(": "), .signed(today), .text(" \(when)")]
        if let tenths = s.todayChangeTenths { first += [.text(" ("), .percentTenths(tenths), .text(")")] }
    } else {
        first.append(.text("."))
    }
    lines.append(BriefingLine(id: "inv-value", parts: first, action: .openInvestments))
    if let movers = moversLine(s, now: now, calendar: calendar) { lines.append(movers) }
    var second: [BriefingPart] = []
    if let gain = s.gainCents {
        second += [.text(partial ? "Desde la compra, de las que tienen precio: " : "Desde la compra: "), .signed(gain)]
        if let tenths = s.gainTenths { second += [.text(" ("), .percentTenths(tenths), .text(")")] }
    }
    if let at = s.pricedAt {
        let age = investmentPriceAge(at, now: now, calendar, plural: true)
        second.append(.text(second.isEmpty ? assistantCapitalized(age) : " · " + age))
    }
    if !second.isEmpty { lines.append(BriefingLine(id: "inv-gain", parts: second, action: .openInvestments)) }
    if s.missingPrices > 0 {
        lines.append(BriefingLine(id: "inv-missing",
                                  parts: [.text("Falta el precio de \(s.missingPrices) \(assistantPlural(s.missingPrices, "posición", "posiciones")).")],
                                  action: .openInvestments))
    }
    if s.hasStalePrice, let oldest = s.oldestPriceAt {
        lines.append(BriefingLine(id: "inv-stale",
                                  parts: [.text("Algún precio es viejo (el más antiguo, del \(assistantShortDate(oldest, calendar))): el valor puede estar desfasado.")],
                                  action: .openInvestments))
    }
    return lines
}

private func investmentsAnswer(positionQuery: String?, moversOnly: Bool, portfolio: Portfolio?,
                               now: Date, calendar: Calendar) -> [BriefingLine] {
    guard let portfolio, let summary = portfolioSummary(portfolio, now: now, calendar: calendar) else {
        return [BriefingLine(id: "inv-empty", parts: [.text("Aún no tienes inversiones importadas.")], action: .openInvestments)]
    }
    if let positionQuery {
        if let matched = matchPosition(query: positionQuery, in: summary.positions) {
            return positionLines(matched, now: now, calendar: calendar)
        }
        var lines = [BriefingLine(id: "inv-not-found",
                                  parts: [.text("No encuentro esa posición en tu cartera.")], action: .openInvestments)]
        if let value = summary.valueCents {
            lines.append(BriefingLine(id: "inv-fallback-total",
                                      parts: [.text(summary.missingPrices > 0 ? "Tu cartera vale al menos " : "Tu cartera vale "),
                                              .amount(value), .text(".")],
                                      action: .openInvestments))
        }
        return lines
    }
    if moversOnly {
        if let movers = moversLine(summary, now: now, calendar: calendar) { return [movers] }
        return [BriefingLine(id: "inv-no-movers",
                             parts: [.text("No hay suficientes posiciones con precio de mercado y cierre anterior para comparar subidas y bajadas.")],
                             action: .openInvestments)]
    }
    return portfolioOverviewLines(summary, now: now, calendar: calendar)
}

// MARK: 11. «¿Qué ha pasado desde ayer?»

private func briefingRecapAnswer(state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                                 precomputed: BriefingInput?, now: Date, calendar: Calendar) -> [BriefingLine] {
    let input = precomputed ?? briefingInput(
        state: state, portfolio: portfolio, book: book,
        record: BriefingRecord(shownAt: now, since: now.addingTimeInterval(-86_400)),
        isFirst: false, now: now, calendar: calendar)
    let briefing = makeBriefing(input, calendar: calendar)
    var lines = [BriefingLine(id: "recap-headline", parts: briefing.headline)]
    if let happened = briefing.sections.first(where: { $0.kind == .happened }) {
        lines += happened.lines.prefix(4)
    }
    if let attention = briefing.sections.first(where: { $0.kind == .attention }) {
        lines += attention.lines.prefix(2)
    }
    if let tip = briefing.tip {
        lines.append(tip)
    }
    return lines
}

// MARK: Lectura en voz alta (con privacidad)

private func hasSensitiveFigure(_ line: BriefingLine) -> Bool {
    for part in line.parts {
        switch part {
        case .amount, .signed, .whole, .percentTenths: return true
        case .text: continue
        }
    }
    return render(line.parts, .masked) != render(line.parts, .plain)
}

private func spokenNumericPart(_ formatted: String) -> String {
    var s = formatted.replacingOccurrences(of: "\u{00A0}", with: " ")
    if s.hasPrefix("+") {
        s = "más " + s.dropFirst()
    } else if s.hasPrefix("-") || s.hasPrefix("\u{2212}") {
        s = "menos " + s.dropFirst()
    }
    return s.replacingOccurrences(of: "%", with: "por ciento").replacingOccurrences(of: "€", with: "euros")
}

private func spokenParts(_ parts: [BriefingPart]) -> String {
    var out = ""
    for part in parts {
        switch part {
        case .text(let s):
            // Respeta el texto literal de comercios y posiciones (p. ej. «Gym +24 %»); solo limpia separadores de lectura.
            out += s
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: " (", with: ", ")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: " · ", with: ". ")
        case .amount(let c):
            out += spokenNumericPart(formatEUR(c))
        case .signed(let c):
            out += spokenNumericPart(formatSignedEUR(c))
        case .whole(let c):
            out += spokenNumericPart(formatEURWhole(c))
        case .percentTenths(let t):
            out += spokenNumericPart(formatPercentTenths(t, signed: true))
        }
    }
    return out
}

private func ensureSentenceEnd(_ text: String) -> String {
    guard let last = text.last else { return text }
    return ".!?".contains(last) ? text : text + "."
}

/// Lo que lee la voz de una respuesta del asistente. En modo privado nunca lee ningún importe ni porcentaje.
public func spokenAssistantAnswer(_ answer: AssistantAnswer, privateMode: Bool) -> String {
    if privateMode {
        let privacyLine = "Tienes el modo privado activado, así que no leo importes."
        if answer.isAdviceRefusal {
            let hasExtraFigures = answer.lines.dropFirst().contains(where: hasSensitiveFigure)
            return hasExtraFigures ? "\(investmentAdviceRefusal) \(privacyLine)" : investmentAdviceRefusal
        }
        if answer.lines.contains(where: hasSensitiveFigure) {
            return privacyLine
        }
        return answer.lines.map { ensureSentenceEnd(render($0.parts, .masked)) }.joined(separator: " ")
    }
    return answer.lines.map { ensureSentenceEnd(spokenParts($0.parts)) }.joined(separator: " ")
}
