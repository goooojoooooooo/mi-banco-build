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
    let knownMerchants = ledgerMerchantKeys(in: state)
    if isAdviceRequest(question, portfolio: portfolio, knownMerchants: knownMerchants) {
        let folded = withoutFormatCharacters(question).decomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let tokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let pos = extractPositionQuery(tokens: tokens, joined: " " + tokens.joined(separator: " ") + " ", portfolio: portfolio)
        return answerIntent(.adviceRequest(positionQuery: pos), state: state, portfolio: portfolio, book: book,
                            briefingInput: precomputedBriefing, now: now, calendar: calendar)
    }
    let resolved: AssistantIntent
    if let modelIntent, modelIntent != .unknown, modelIntent != .unsupportedPeriod,
       let sanitized = sanitizeModelIntent(modelIntent, originalQuestion: question, knownMerchants: knownMerchants) {
        let isPeriodSensitive: Bool = switch sanitized {
        case .spending, .biggestPayments, .income, .ownTransfers: true
        default: false
        }
        resolved = (isPeriodSensitive && questionHasUnsupportedPeriod(question)) ? .unsupportedPeriod : sanitized
    } else {
        resolved = routeAssistantQuestion(question, state: state, portfolio: portfolio, now: now, calendar: calendar)
    }
    return answerIntent(resolved, state: state, portfolio: portfolio, book: book,
                        briefingInput: precomputedBriefing, now: now, calendar: calendar)
}

/// Revalida en la frontera pública de `answerQuestion` cualquier `merchant` propuesto en `modelIntent` (C2, J21(d), U2).
private func sanitizeModelIntent(_ intent: AssistantIntent, originalQuestion: String, knownMerchants: Set<String>) -> AssistantIntent? {
    if case let .spending(month, category, merchant, bank) = intent, let merchant {
        guard let safe = validatedSpanFromQuestion(merchant, originalQuestion: originalQuestion, knownMerchants: knownMerchants) else {
            return nil
        }
        return .spending(month: month, category: category, merchant: safe, bank: bank)
    }
    return intent
}

/// Responde a una intención ya resuelta con hechos del libro, la cartera y el cuaderno de cuentas.
public func answerIntent(_ intent: AssistantIntent, state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                         briefingInput precomputedBriefing: BriefingInput? = nil,
                         now: Date, calendar: Calendar) -> AssistantAnswer {
    switch intent {
    case .balances(let bank):
        return AssistantAnswer(intent: intent, lines: balancesAnswer(bank: bank, state: state, portfolio: portfolio))
    case let .spending(month, category, merchant, bank):
        let res = spendingAnswer(month: month, category: category, merchant: merchant, bank: bank,
                                 state: state, now: now, calendar: calendar)
        return AssistantAnswer(intent: intent, lines: res.lines, chips: res.chips)
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
        let summary = portfolio.flatMap { portfolioSummary($0, now: now, calendar: calendar) }
        if let summary {
            if let q = positionQuery, let matched = matchPosition(query: q, in: summary.positions) {
                lines += positionLines(matched, now: now, calendar: calendar)
            } else {
                lines += portfolioOverviewLines(summary, now: now, calendar: calendar)
            }
        }
        var chips: [AssistantChip] = []
        if summary != nil {
            chips.append(AssistantChip(id: "investments", label: "¿Cómo van mis inversiones?"))
        } else {
            chips.append(AssistantChip(id: "spending", label: "¿Cuánto llevo este mes?"))
        }
        chips.append(AssistantChip(id: "balances", label: "¿Cuánto tengo?"))
        chips.append(AssistantChip(id: "upcoming", label: "¿Qué cobros vienen?"))
        return AssistantAnswer(intent: intent, lines: lines, chips: chips, isAdviceRefusal: true)
    case .unsupportedPeriod:
        let chips = [
            AssistantChip(id: "spending-current", label: "¿Cuánto llevo este mes?"),
            AssistantChip(id: "spending-previous", label: "¿Cuánto gasté el mes pasado?"),
        ]
        return AssistantAnswer(
            intent: intent,
            lines: [BriefingLine(id: "unsupported-period",
                                 parts: [.text("Aún no sé contarte el gasto por días, semanas o años; sí por meses.")])],
            chips: chips
        )
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
    case 0: return "Hoy"
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

    func contains(_ movement: Movement, calendar: Calendar) -> Bool {
        guard movement.date >= start else { return false }
        return upperInclusive ? movementCounts(movement, upTo: upper, calendar: calendar) : movement.date < upper
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

/// Primer día en que cada banco con algún cobro próximo en `days` (hasta ese día incluido) queda por debajo de su mínimo.
/// Un banco SIN cobros próximos que ya estaba por debajo del mínimo no aparece (evita falsos «por los próximos cobros»).
func firstChargeBelowFloorDays(_ days: [UpcomingDay]) -> [BankID: Date] {
    var first: [BankID: Date] = [:]
    var banksWithChargeSoFar = Set<BankID>()
    for day in days {
        for charge in day.charges { banksWithChargeSoFar.insert(charge.bank) }
        for bank in day.belowFloor where first[bank] == nil && banksWithChargeSoFar.contains(bank) {
            first[bank] = day.day
        }
    }
    return first
}

// MARK: 1. Saldos

private func balancesAnswer(bank: BankID?, state: LedgerState, portfolio: Portfolio?) -> [BriefingLine] {
    let ledger = Ledger(state: state)
    if let bank {
        guard let b = ledger.balance(bank) else {
            return [BriefingLine(id: "bal-\(bank.rawValue)", parts: [.text("Aún no tengo el saldo de \(bank.displayName).")])]
        }
        let hasOpenPositions = bank == .tr && (portfolio.map { !positions(from: $0.transactions).isEmpty } ?? false)
        let suffix = hasOpenPositions ? " de efectivo, sin contar tus inversiones." : "."
        return [BriefingLine(id: "bal-\(bank.rawValue)",
                             parts: [.text("En \(bank.displayName) tienes \(b.estimated ? "unos " : "")"), .amount(b.cents), .text(suffix)])]
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

// MARK: 2. Gastos (mes, categoría, comercio o banco)

private func tokenRunContains(_ haystack: [String], _ needle: [String]) -> Bool {
    guard !needle.isEmpty, needle.count <= haystack.count else { return false }
    for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
        return true
    }
    return false
}

private func movementMatchesMerchant(_ m: Movement, queryKey: String, queryDomain: String? = nil) -> Bool {
    let qTokens = queryKey.split(separator: " ").map(String.init)
    guard !qTokens.isEmpty else { return false }
    let targetDomain = queryDomain ?? merchantDomain(for: queryKey)
    for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
        let key = normalizeMerchant(raw)
        if key == queryKey { return true }
        let mTokens = key.split(separator: " ").map(String.init)
        if tokenRunContains(mTokens, qTokens) { return true }
        if let targetDomain, let mDomain = merchantDomain(for: raw), targetDomain == mDomain { return true }
    }
    return false
}

private func spendingAnswer(month: AssistantMonth, category: SpendingCategory?, merchant: String?, bank: BankID?,
                            state: LedgerState, now: Date, calendar: Calendar) -> (lines: [BriefingLine], chips: [AssistantChip]) {
    guard let resolved = resolveMonth(month, now: now, calendar: calendar) else {
        return ([BriefingLine(id: "spend-invalid", parts: [.text("No reconozco ese mes.")])], [])
    }
    if resolved.isFuture {
        return ([BriefingLine(id: "spend-future", parts: [.text("Aún no ha llegado \(resolved.bareName).")])], [])
    }
    // Exclusiones calculadas sobre el libro ENTERO para conservar traspasos entre bancos y capturas dudosas.
    let exclusions = spendingExclusions(in: state, now: now)
    // J13: un pago de 0 € no cuenta como pago en ninguna suma de gasto.
    var scopedState = state
    scopedState.movements = state.movements.filter { m in
        if m.kind == .payment && abs(m.amountCents) == 0 { return false }
        if let bank, m.bank != bank { return false }
        return true
    }

    let bankSuffix = bank.map { " en \($0.displayName)" } ?? ""

    // Subcaso A: por comercio («¿cuánto llevo en Mercadona?»).
    if let merchant {
        let key = normalizeMerchant(merchant)
        let qDomain = merchantDomain(for: merchant)
        let matched = spendingMovements(in: scopedState.movements, notSpending: exclusions)
            .filter { resolved.contains($0, calendar: calendar) && movementMatchesMerchant($0, queryKey: key, queryDomain: qDomain) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
        let distinctNames = Set(matched.compactMap { $0.displayMerchant ?? $0.merchant }.map(normalizeMerchant))
        let rawDisplay: String
        if distinctNames.count == 1, let single = matched.first?.displayMerchant ?? matched.first?.merchant {
            rawDisplay = single
        } else {
            rawDisplay = merchant
        }
        let display = clippedName(rawDisplay)
        guard !matched.isEmpty else {
            // U2: si el comercio no existe en ningún movimiento del libro entero, no afirmar «no tienes pagos en X».
            let existsInLedger = state.movements.contains { m in
                m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending
                    && movementMatchesMerchant(m, queryKey: key, queryDomain: qDomain)
            }
            if !existsInLedger {
                let unknownChips = [
                    AssistantChip(id: "cat-supermercado", label: "¿Cuánto llevo en Supermercado?"),
                    AssistantChip(id: "cat-comerFuera", label: "¿Cuánto llevo en Comer fuera?"),
                ]
                return ([BriefingLine(id: "spend-merchant-not-found",
                                      parts: [.text("No encuentro pagos a nombre de «\(display)».")])], unknownChips)
            }
            let line = resolved.isCurrent
                ? "Este mes no tienes pagos en \(display)\(bankSuffix)."
                : "No tienes pagos en \(display)\(bankSuffix) \(resolved.phrase)."
            return ([BriefingLine(id: "spend-merchant-empty", parts: [.text(line)])], [])
        }
        let total = matched.reduce(0) { $0 + abs($1.amountCents) }
        let countText = "(\(matched.count) \(assistantPlural(matched.count, "pago", "pagos")))"
        let headParts: [BriefingPart] = resolved.isCurrent
            ? [.text("Este mes llevas "), .amount(total), .text(" en \(display)\(bankSuffix) \(countText).")]
            : [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(total), .text(" en \(display)\(bankSuffix) \(countText).")]
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
        return (lines, [])
    }

    let subKeys = subscriptionKeys(in: state, now: now, calendar: calendar, notSpending: exclusions)
    let spending = monthSpending(in: scopedState, month: resolved.start, now: now, calendar: calendar,
                                 notSpending: exclusions, subscriptionKeys: subKeys)
    let prevName = previousMonthName(before: resolved.start, calendar: calendar)

    // Subcaso B: por categoría.
    if let category {
        guard let row = spending.byCategory.first(where: { $0.category == category }), row.cents > 0 else {
            return ([BriefingLine(id: "spend-cat-empty",
                                  parts: [.text("No tienes gastos en \(category.displayName)\(bankSuffix) \(resolved.phrase).")])], [])
        }
        let countText = "(\(row.count) \(assistantPlural(row.count, "pago", "pagos")))"
        let firstParts: [BriefingPart] = resolved.isCurrent
            ? [.text("Este mes llevas "), .amount(row.cents), .text(" en \(category.displayName)\(bankSuffix) \(countText).")]
            : [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(row.cents),
               .text(" en \(category.displayName)\(bankSuffix) \(countText).")]
        var lines = [BriefingLine(id: "spend-cat", parts: firstParts)]
        if row.previousCents > 0 {
            lines.append(monthComparisonLine(id: "spend-cat-cmp", diff: row.cents - row.previousCents,
                                             prevName: prevName, samePoint: resolved.isCurrent))
        }
        return (lines, [])
    }

    // Subcaso C: total del mes (todos los bancos o uno en concreto).
    guard spending.totalCents > 0 else {
        let text = resolved.isCurrent
            ? "Este mes aún no tienes gastos registrados\(bankSuffix)."
            : "No tengo gastos registrados\(bankSuffix) \(resolved.phrase)."
        return ([BriefingLine(id: "spend-empty", parts: [.text(text)])], [])
    }
    var lines: [BriefingLine] = []
    if resolved.isCurrent, bank == nil,
       let forecast = monthForecast(in: state, now: now, calendar: calendar, notSpending: exclusions),
       forecast.projectedCents >= 50 {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("Este mes llevas "), .amount(spending.totalCents),
                                          .text(" gastados; a este ritmo acabarás en unos "), .whole(forecast.projectedCents), .text(".")]))
    } else if resolved.isCurrent {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("Este mes llevas "), .amount(spending.totalCents), .text(" gastados\(bankSuffix).")]))
    } else {
        lines.append(BriefingLine(id: "spend-total",
                                  parts: [.text("\(assistantCapitalized(resolved.phrase)) gastaste "), .amount(spending.totalCents),
                                          .text("\(bankSuffix).")]))
    }
    if spending.previousTotalCents > 0 {
        lines.append(monthComparisonLine(id: "spend-cmp", diff: spending.totalCents - spending.previousTotalCents,
                                         prevName: prevName, samePoint: resolved.isCurrent))
    }
    if let top = spending.byCategory.first {
        lines.append(BriefingLine(id: "spend-top-cat",
                                  parts: [.text("Donde más: \(top.category.displayName) ("), .amount(top.cents), .text(").")]))
    }
    return (lines, [])
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
        .filter { resolved.contains($0, calendar: calendar) && abs($0.amountCents) > 0 }
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
    var chargeByKey: [String: UpcomingCharge] = [:]
    for c in charges {
        let k = "\(c.bank.rawValue)|\(normalizeMerchant(c.name))"
        if chargeByKey[k] == nil { chargeByKey[k] = c }
    }
    let today = calendar.startOfDay(for: now)
    var chargedTodayKeys = Set<String>()
    for m in state.movements where m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending
        && m.date >= today && movementCounts(m, upTo: now, calendar: calendar) {
        chargedTodayKeys.insert("\(m.bank.rawValue)|\(normalizeMerchant(m.merchant ?? ""))")
    }

    var lines = [BriefingLine(id: "subs-total",
                              parts: [.text("Tienes \(subs.count) \(assistantPlural(subs.count, "suscripción activa", "suscripciones activas")): "),
                                      .amount(totals.monthlyCents), .text(" al mes ("), .amount(totals.yearlyCents), .text(" al año).")])]
    for sub in subs.prefix(5) {
        let key = "\(sub.bank.rawValue)|\(sub.id)"
        let whenText: String
        if let charge = chargeByKey[key] {
            let note = overdueNote(charge, calendar: calendar).map { " (\($0))" } ?? ""
            if charge.date < today && !charge.overdue {
                whenText = "pendiente desde el \(assistantShortDate(charge.date, calendar))"
            } else {
                whenText = "\(assistantDayOrShortDate(charge.date, now: now, calendar))\(note)"
            }
        } else if calendar.isDate(sub.nextDate, inSameDayAs: now) && chargedTodayKeys.contains(key) {
            whenText = "cobrado hoy"
        } else if calendar.startOfDay(for: sub.nextDate) < today {
            whenText = "pendiente desde el \(assistantShortDate(sub.nextDate, calendar))"
        } else {
            whenText = "próximo el \(assistantShortDate(sub.nextDate, calendar))"
        }
        lines.append(BriefingLine(id: "sub-\(sub.bank.rawValue)-\(sub.id)",
                                  parts: [.text("\(clippedName(sub.merchant)): "), .amount(sub.amountCents),
                                          .text(" en \(sub.bank.displayName) · \(whenText)")]))
    }
    if subs.count > 5 {
        lines.append(BriefingLine(id: "sub-rest", parts: [.text("Y \(subs.count - 5) más.")]))
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
        return [BriefingLine(id: "up-empty", parts: [.text("No veo cobros\(scope) para los próximos \(upcomingCalendarDays) días.")])]
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

    // Comprobación de faltas de saldo: pasamos los cobros de TODOS los bancos (C3) en el horizonte de 7 días
    // para que `whereToPay` no recomiende traspasar dinero comprometido en otro banco.
    let ledger = Ledger(state: state)
    var balances: [BankID: Int] = [:]
    var estimated = Set<BankID>()
    for b in BankID.allCases {
        guard let reading = ledger.balance(b) else { continue }
        balances[b] = reading.cents
        if reading.estimated { estimated.insert(b) }
    }
    let startOfToday = calendar.startOfDay(for: now)
    let sevenDayHorizon = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now
    let allSevenDayCharges = days.flatMap(\.charges).filter { $0.date >= startOfToday && $0.date < sevenDayHorizon }
    let allUrgent = shortfalls(balances: balances, floors: book.floors, upcoming: allSevenDayCharges, now: now,
                               calendar: calendar, estimated: estimated)
    let urgent = allUrgent.filter { bank == nil || $0.bank == bank }
    let urgentBanks = Set(urgent.map(\.bank))

    // Caída por debajo del mínimo en 14 días solo en bancos que tienen cobros próximos (I5) y no están ya en `urgent`.
    let belowFloor = firstChargeBelowFloorDays(days).filter { (bank == nil || $0.key == bank) && !urgentBanks.contains($0.key) }
    let chargeBanks = BankID.allCases.filter { b in charges.contains { $0.bank == b } }
    let unknownBanks = chargeBanks.filter { balances[$0] == nil }
    let knownChargeBanks = chargeBanks.filter { balances[$0] != nil }

    for (i, s) in urgent.enumerated() {
        lines.append(shortfallLine(id: "up-shortfall-\(i)", shortfall: s, now: now, calendar: calendar))
    }
    for b in BankID.allCases {
        guard let firstDay = belowFloor[b] else { continue }
        let hasFloor = (book.floors[b] ?? 0) > 0
        let msg = hasFloor
            ? "Ojo: con los próximos cobros, \(b.displayName) quedaría por debajo de su mínimo el \(assistantShortDate(firstDay, calendar))."
            : "Ojo: con los próximos cobros, \(b.displayName) se quedaría en negativo el \(assistantShortDate(firstDay, calendar))."
        lines.append(BriefingLine(id: "up-below-\(b.rawValue)",
                                  parts: [.text(msg)],
                                  action: .moveMoney(from: nil, to: b, cents: nil)))
    }
    if urgent.isEmpty && belowFloor.isEmpty && !knownChargeBanks.isEmpty && unknownBanks.isEmpty {
        // Comprueba si el saldo ACTUAL (sin depender de ingresos previstos) cubre los cobros y mínimos.
        let coveredWithoutExpected = knownChargeBanks.allSatisfy { b in
            let bankSum = charges.filter { $0.bank == b }.reduce(0) { $0 + $1.cents }
            return (balances[b] ?? 0) - bankSum >= (book.floors[b] ?? 0)
        }
        let anyEstimated = knownChargeBanks.contains { estimated.contains($0) }
        if coveredWithoutExpected {
            let text = anyEstimated
                ? "Con el saldo aproximado actual, llega para estos cobros (sin contar otros gastos)."
                : "Con el saldo actual, llega para estos cobros (sin contar otros gastos)."
            lines.append(BriefingLine(id: "up-ok", parts: [.text(text)]))
        } else {
            lines.append(BriefingLine(id: "up-needs-income",
                                      parts: [.text("Con el saldo actual no llega sin el ingreso previsto (y sin contar otros gastos).")]))
        }
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
    if s.charge.overdue {
        if let note = overdueNote(s.charge, calendar: calendar) {
            when = "Tienes pendiente (\(note))"
        } else {
            when = "Tienes pendiente"
        }
    } else {
        switch assistantDayDistance(from: now, to: s.charge.date, calendar) {
        case ...0: when = "Hoy te cobran"
        case 1: when = "Mañana te cobran"
        default: when = "El \(assistantWeekday(s.charge.date, calendar)) \(calendar.component(.day, from: s.charge.date)) te cobran"
        }
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
            && $0.amountCents > 0 && resolved.contains($0, calendar: calendar)
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
    let unconfirmed = unconfirmedCaptureIDs(in: state, now: now)
    let twins = probableTwinCaptureIDs(in: state.movements, skipping: unconfirmed)
    let pairs = ownTransferPairs(in: state.movements)
    var pairedIDs = Set<UUID>()

    struct TransferRow {
        let id: UUID
        let date: Date
        let cents: Int
        let line: BriefingLine
    }
    var rows: [TransferRow] = []
    for pair in pairs {
        guard let payment = byID[pair.paymentID], let income = byID[pair.incomeID],
              !payment.flaggedNotMine, !income.flaggedNotMine,
              !unconfirmed.contains(payment.id), !unconfirmed.contains(income.id),
              abs(payment.amountCents) > 0 else { continue }
        pairedIDs.insert(payment.id)
        pairedIDs.insert(income.id)
        guard resolved.contains(payment, calendar: calendar) else { continue }
        let cents = abs(payment.amountCents)
        let line = BriefingLine(id: "tr-\(payment.id.uuidString)",
                                parts: [.amount(cents), .text(" de \(payment.bank.displayName) a \(income.bank.displayName) (\(assistantShortDate(payment.date, calendar)))")],
                                action: .openMovement(payment.id))
        rows.append(TransferRow(id: payment.id, date: payment.date, cents: cents, line: line))
    }

    // Movimientos marcados manualmente (`ownTransfer == true`) fuera de `ownTransferPairs` (p. ej. recarga con tarjeta o >3 días):
    // emparejamos salida+entrada del mismo importe en bancos distintos dentro de 7 días para no duplicar el importe (I7).
    let manualUnpaired = state.movements.filter {
        $0.ownTransfer == true && !pairedIDs.contains($0.id) && !$0.flaggedNotMine && !$0.excludedFromSpending
            && !unconfirmed.contains($0.id) && !twins.contains($0.id) && abs($0.amountCents) > 0
    }.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }
    let manualPayments = manualUnpaired.filter { $0.kind == .payment }
    let manualIncomes = manualUnpaired.filter { $0.kind == .income }
    var matchedManualIDs = Set<UUID>()
    for p in manualPayments {
        let cents = abs(p.amountCents)
        if let inc = manualIncomes.first(where: {
            !matchedManualIDs.contains($0.id) && $0.bank != p.bank && abs($0.amountCents) == cents
                && abs($0.date.timeIntervalSince(p.date)) <= 7 * 86_400
        }) {
            matchedManualIDs.insert(p.id)
            matchedManualIDs.insert(inc.id)
            if resolved.contains(p, calendar: calendar) {
                let line = BriefingLine(id: "tr-\(p.id.uuidString)",
                                        parts: [.amount(cents), .text(" de \(p.bank.displayName) a \(inc.bank.displayName) (\(assistantShortDate(p.date, calendar)))")],
                                        action: .openMovement(p.id))
                rows.append(TransferRow(id: p.id, date: p.date, cents: cents, line: line))
            }
        }
    }
    var unpairedRows: [TransferRow] = []
    for m in manualUnpaired where !matchedManualIDs.contains(m.id) && resolved.contains(m, calendar: calendar) {
        let cents = abs(m.amountCents)
        let line = BriefingLine(id: "tr-\(m.id.uuidString)",
                                parts: [.amount(cents), .text(" en \(m.bank.displayName) (\(assistantShortDate(m.date, calendar)), marcado como traspaso)")],
                                action: .openMovement(m.id))
        unpairedRows.append(TransferRow(id: m.id, date: m.date, cents: cents, line: line))
    }

    rows.sort { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    unpairedRows.sort { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }

    guard !rows.isEmpty || !unpairedRows.isEmpty else {
        return [BriefingLine(id: "tr-empty", parts: [.text("No tienes traspasos entre tus cuentas \(resolved.phrase).")])]
    }
    // U6: la cabecera suma SOLO los traspasos emparejados; las patas sin pareja van aparte sin entrar en el total.
    if rows.isEmpty {
        let countText = "\(unpairedRows.count) \(assistantPlural(unpairedRows.count, "movimiento marcado como traspaso", "movimientos marcados como traspaso")) sin pareja:"
        let head = resolved.isCurrent
            ? "Este mes tienes \(countText)"
            : "\(assistantCapitalized(resolved.phrase)) tuviste \(countText)"
        var lines = [BriefingLine(id: "tr-unpaired-only", parts: [.text(head)])]
        lines += unpairedRows.prefix(5).map(\.line)
        if unpairedRows.count > 5 {
            lines.append(BriefingLine(id: "tr-unpaired-rest", parts: [.text("Y \(unpairedRows.count - 5) más.")]))
        }
        return lines
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
    if !unpairedRows.isEmpty {
        let extraHead = "Además, \(unpairedRows.count) \(assistantPlural(unpairedRows.count, "movimiento marcado como traspaso no tiene pareja", "movimientos marcados como traspaso no tienen pareja")):"
        lines.append(BriefingLine(id: "tr-unpaired-head", parts: [.text(extraHead)]))
        lines += unpairedRows.prefix(5).map(\.line)
        if unpairedRows.count > 5 {
            lines.append(BriefingLine(id: "tr-unpaired-rest", parts: [.text("Y \(unpairedRows.count - 5) más.")]))
        }
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
    let missingDaily = [BankID.rev, .ima].filter { balances[$0] == nil }
    if balances[.rev] == nil && balances[.ima] == nil {
        return [BriefingLine(id: "free-no-bal",
                             parts: [.text("Aún no tengo el saldo de Revolut ni de imagin para calcular el dinero libre.")])]
    }
    let exclusions = spendingExclusions(in: state, now: now)
    let charges = subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions)
    guard let free = freeMoney(balances: balances, floors: book.floors, banks: dailyBanks, pending: charges,
                               now: now, calendar: calendar),
          free.cents >= 50 else {
        let trNote = balances[.tr] != nil ? " (sin contar Trade Republic)" : ""
        var lines = [BriefingLine(id: "free-none",
                                  parts: [.text("Con tus saldos, mínimos y cobros pendientes de este mes no te queda margen libre\(trNote).")])]
        if !missingDaily.isEmpty {
            let names = assistantJoinList(missingDaily.map(\.displayName))
            lines.append(BriefingLine(id: "free-missing", parts: [.text("Sin contar \(names): no tengo su saldo.")]))
        }
        return lines
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
    var first: [BriefingPart] = [.text(partial ? "Tus inversiones valen al menos " : "Tus inversiones valen "), .amount(value)]
    if partial { first.append(.text(" de las que tienen precio")) }
    if let today = s.todayChangeCents, let day = s.changeDay {
        let when = assistantDayDistance(from: day, to: now, calendar) <= 0
            ? "hoy"
            : "en la última sesión (\(assistantWeekday(day, calendar)))"
        first += [.text(": "), .signed(today), .text(" \(when)")]
        if let tenths = s.todayChangeTenths { first += [.text(" ("), .percentTenths(tenths), .text(")")] }
    }
    first.append(.text("."))
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
    guard let portfolio, !portfolio.transactions.isEmpty else {
        return [BriefingLine(id: "inv-empty", parts: [.text("Aún no tienes inversiones importadas.")], action: .openInvestments)]
    }
    guard let summary = portfolioSummary(portfolio, now: now, calendar: calendar) else {
        return [BriefingLine(id: "inv-closed", parts: [.text("No tienes posiciones abiertas en tu cartera.")], action: .openInvestments)]
    }
    if let positionQuery {
        if let matched = matchPosition(query: positionQuery, in: summary.positions) {
            return positionLines(matched, now: now, calendar: calendar)
        }
        var lines = [BriefingLine(id: "inv-not-found",
                                  parts: [.text("No encuentro esa posición en tu cartera.")], action: .openInvestments)]
        if let value = summary.valueCents {
            let partial = summary.missingPrices > 0
            lines.append(BriefingLine(id: "inv-fallback-total",
                                      parts: [.text(partial ? "Tu cartera vale al menos " : "Tu cartera vale "),
                                              .amount(value),
                                              .text(partial ? " de las que tienen precio." : ".")],
                                      action: .openInvestments))
        }
        return lines
    }
    if moversOnly {
        if let movers = moversLine(summary, now: now, calendar: calendar) { return [movers] }
        let comparableCount: Int = {
            guard let day = summary.changeDay else { return 0 }
            return summary.positions.filter { p in
                guard case .market(let at) = p.origin, calendar.startOfDay(for: at) == day,
                      let value = p.valueCents, let change = p.todayChangeCents, value - change > 0 else { return false }
                return true
            }.count
        }()
        let text = comparableCount >= 2
            ? "En la última sesión no hubo diferencias apreciables entre tus posiciones."
            : "No hay suficientes posiciones con precio de mercado y cierre anterior para comparar subidas y bajadas."
        return [BriefingLine(id: "inv-no-movers", parts: [.text(text)], action: .openInvestments)]
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
        if attention.lines.count > 2 {
            let extra = attention.lines.count - 2
            lines.append(BriefingLine(id: "recap-attention-rest",
                                      parts: [.text("Y \(extra) \(assistantPlural(extra, "aviso", "avisos")) más.")]))
        }
    }
    if let tip = briefing.tip {
        lines.append(tip)
    }
    return lines
}

// MARK: Lectura en voz alta (con privacidad)

private let embeddedSensitivePattern = #"(?i)[€%]|\b(?:euros?|eur)\b|[0-9]+[.,][0-9]{2}(?![0-9])"#

private func hasSensitiveFigure(_ line: BriefingLine) -> Bool {
    for part in line.parts {
        switch part {
        case .amount, .signed, .whole, .percentTenths: return true
        case .text(let s):
            if s.range(of: embeddedSensitivePattern, options: .regularExpression) != nil { return true }
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

private func isNumericPart(_ part: BriefingPart) -> Bool {
    switch part {
    case .text: return false
    case .amount, .signed, .whole, .percentTenths: return true
    }
}

private func spokenParts(_ line: BriefingLine) -> String {
    let parts = line.parts
    let isAttentionWarning = line.id.hasPrefix("attention-")
    var out = ""
    for (i, part) in parts.enumerated() {
        switch part {
        case .text(var s):
            s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: " · ", with: ". ")
            // Solo suaviza paréntesis que envuelven una parte numérica; conserva «iShares Core MSCI World (Acc)» intacto (I8).
            let nextIsNumeric = (i + 1 < parts.count) && isNumericPart(parts[i + 1])
            let prevIsNumeric = (i > 0) && isNumericPart(parts[i - 1])
            if nextIsNumeric && s.hasSuffix(" (") {
                s = String(s.dropLast(2)) + ", "
            }
            if prevIsNumeric && s.hasPrefix(")") {
                s = String(s.dropFirst())
            }
            // Las líneas de aviso del resumen (`attention-*`) llevan importes dentro de `.text`: solo convierte importes
            // reconocibles (`12,50 €`, `+10 %`), sin reescribir signos dentro de nombres de comercios (J13).
            if isAttentionWarning {
                s = s.replacingOccurrences(of: "(?<=^|[ (])\\+(?=[0-9]+(?:[.,][0-9]+)? ?[€%])",
                                           with: "más ", options: .regularExpression)
                s = s.replacingOccurrences(of: "(?<=^|[ (])[-−](?=[0-9]+(?:[.,][0-9]+)? ?[€%])",
                                           with: "menos ", options: .regularExpression)
                s = s.replacingOccurrences(of: "(?<=[0-9]) ?%", with: " por ciento", options: .regularExpression)
                s = s.replacingOccurrences(of: "(?<=[0-9]) ?€", with: " euros", options: .regularExpression)
            }
            out += s
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
    return answer.lines.map { ensureSentenceEnd(spokenParts($0)) }.joined(separator: " ")
}
