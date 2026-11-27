import Foundation

/// Memoria breve de la conversación mientras la hoja de Nyx está abierta (solo en memoria, nunca se guarda en disco).
public struct NyxConversation: Equatable, Sendable {
    public private(set) var lastIntent: AssistantIntent?

    public init() {
        self.lastIntent = nil
    }

    public mutating func remember(_ intent: AssistantIntent) {
        lastIntent = intent
    }

    public mutating func reset() {
        lastIntent = nil
    }
}

/// Tipo de pregunta resuelta por Nyx: una intención del asistente o una de las dos preguntas propias de Nyx.
public enum NyxQuestion: Equatable, Sendable {
    case assistant(AssistantIntent)
    case seen
    case appStatus
}

/// Resultado de responder una pregunta en la hoja de Nyx.
public struct NyxReply: Equatable, Sendable {
    public let question: NyxQuestion
    public let answer: AssistantAnswer

    public init(question: NyxQuestion, answer: AssistantAnswer) {
        self.question = question
        self.answer = answer
    }
}

private let nyxNewQuestionCues: Set<String> = [
    "cuanto", "cuanta", "cuantos", "cuantas", "cual", "cuales", "como", "cuando", "donde", "que", "quien",
    "dime", "cuentame", "ensename", "muestrame",
    "tengo", "llevo", "gaste", "gastado", "pague", "pagado", "cobre", "cobrado",
    "saldo", "saldos", "presupuesto", "presupuestos", "ingresos", "traspasos", "inversiones", "cartera", "resumen",
]

/// Palabras de consulta financiera normal: evitan desviar preguntas de saldos, gasto o presupuesto a preguntas propias de Nyx.
private let nyxFinancialQuestionCues: Set<String> = [
    "cuanto", "cuanta", "cuantos", "cuantas",
    "saldo", "saldos", "dinero",
    "gaste", "gastado", "gasto", "gastos", "gastar",
    "pague", "pagado", "pago", "pagos", "llevo",
    "cobre", "cobrado", "ingreso", "ingresos", "nomina", "sueldo",
    "presupuesto", "presupuestos", "suscripcion", "suscripciones",
    "traspaso", "traspasos", "inversion", "inversiones", "cartera",
    "cobros", "recibos", "sobra", "libre",
]

private func nyxFoldedTokens(_ text: String) -> (rawFolded: String, tokens: [String], joined: String) {
    let rawFolded = foldedQuery(text)
    let tokens = rawFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let joined = " " + tokens.joined(separator: " ") + " "
    return (rawFolded, tokens, joined)
}

/// Frases propias de Nyx que llevan «pago(s)» pero no son una consulta de dinero: la barrera no se aplica a ellas.
private let nyxOwnPaymentPhrases = [" pago raro ", " pagos raros ", " avisos de los pagos ", " avisos de pagos ", " avisos de mis pagos "]

private func nyxOwnQuestion(tokens: [String], joined: String) -> NyxQuestion? {
    let ownPhrase = nyxOwnPaymentPhrases.contains { joined.contains($0) }
    guard ownPhrase || !tokens.contains(where: { nyxFinancialQuestionCues.contains($0) }) else { return nil }
    if joined.contains(" has visto ") || joined.contains(" me he perdido ") || tokens.contains("novedades") {
        return .seen
    }
    let connectedAsModifier = joined.contains(" en la cuenta conectad")
        || joined.contains(" en el banco conectad")
        || joined.contains(" de la cuenta conectad")
        || joined.contains(" del banco conectad")
        || joined.contains(" en las cuentas conectad")
        || joined.contains(" en los bancos conectad")
        || joined.contains(" de las cuentas conectad")
        || joined.contains(" de los bancos conectad")
    if tokens.contains(where: { $0.hasPrefix("funciona") })
        || joined.contains(" va todo bien con la app ")
        || joined.contains(" todo bien con la app ")
        || (!connectedAsModifier && tokens.contains(where: { $0.hasPrefix("conectad") }))
        || joined.contains(" llegan los avisos ")
        || joined.contains(" llegan avisos ") {
        return .appStatus
    }
    return nil
}

private func nyxKnownMerchantMatch(_ question: String, joined: String, tokens: [String],
                                   state: LedgerState, knownMerchants: Set<String>) -> String? {
    guard let candidate = extractMerchant(rawQuestion: question, joined: joined, tokens: tokens,
                                          state: state, category: nil, bank: nil) else { return nil }
    let key = normalizeMerchant(candidate)
    guard !key.isEmpty else { return nil }
    if knownMerchants.contains(key) { return candidate }
    if knownMerchants.contains(where: { $0.split(separator: " ").first.map(String.init) == key }) { return candidate }
    if let domain = merchantDomain(for: candidate) {
        let matchesDomain = state.movements.contains { m in
            guard m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending else { return false }
            return [m.merchant, m.bankMerchant].compactMap { $0 }.contains { merchantDomain(for: $0) == domain }
        }
        if matchesDomain { return candidate }
    }
    return nil
}

/// Resuelve una pregunta seguida cambiando solo el parámetro que nombra (mes, banco, «en total», categoría o comercio
/// conocido) sobre la intención anterior; nil si es una pregunta nueva, pide consejo o no encaja con `previous`.
public func nyxFollowUp(_ question: String, after previous: AssistantIntent, state: LedgerState, portfolio: Portfolio?,
                        now: Date, calendar: Calendar) -> AssistantIntent? {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let knownMerchants = ledgerMerchantKeys(in: state)
    if isAdviceRequest(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) { return nil }

    let parsed = nyxFoldedTokens(trimmed)
    guard !parsed.tokens.isEmpty else { return nil }

    let startsWithConjunction = parsed.tokens.first == "y" || parsed.tokens.first == "e"
    if !startsWithConjunction {
        guard parsed.tokens.count <= 3,
              routeAssistantQuestion(trimmed, state: state, portfolio: portfolio, now: now, calendar: calendar) == .unknown else {
            return nil
        }
    }
    if parsed.tokens.contains(where: { nyxNewQuestionCues.contains($0) }) { return nil }

    let explicitMonth: AssistantMonth?
    if parsed.joined.contains(" este mes ") || parsed.joined.contains(" mes actual ") {
        explicitMonth = .current
    } else {
        let m = extractMonth(tokens: parsed.tokens, joined: parsed.joined, rawFolded: parsed.rawFolded,
                             now: now, calendar: calendar)
        explicitMonth = (m == .current) ? nil : m
    }
    let bank = extractBank(tokens: parsed.tokens, joined: parsed.joined)
    let clearBank = parsed.joined.contains(" en total ") || parsed.tokens == ["y", "total"] || parsed.tokens == ["total"]
    let category = extractCategory(joined: parsed.joined)
    let merchant = (category == nil && bank == nil && !clearBank)
        ? nyxKnownMerchantMatch(trimmed, joined: parsed.joined, tokens: parsed.tokens,
                                state: state, knownMerchants: knownMerchants)
        : nil

    switch previous {
    case let .spending(prevMonth, prevCategory, prevMerchant, prevBank):
        var month = prevMonth
        var cat = prevCategory
        var merch = prevMerchant
        var b = prevBank
        var changed = false
        if let explicitMonth {
            month = explicitMonth
            changed = true
        }
        if let bank {
            b = bank
            changed = true
        } else if clearBank {
            b = nil
            changed = true
        }
        if let category {
            cat = category
            merch = nil
            changed = true
        } else if let merchant {
            merch = merchant
            cat = nil
            changed = true
        }
        return changed ? .spending(month: month, category: cat, merchant: merch, bank: b) : nil

    case .balances:
        if let bank { return .balances(bank: bank) }
        if clearBank { return .balances(bank: nil) }
        return nil

    case .upcomingCharges:
        if let bank { return .upcomingCharges(bank: bank) }
        if clearBank { return .upcomingCharges(bank: nil) }
        return nil

    case .budgets:
        if let category { return .budgets(category: category) }
        if clearBank { return .budgets(category: nil) }
        return nil

    case .income:
        return explicitMonth.map { .income(month: $0) }

    case .biggestPayments:
        return explicitMonth.map { .biggestPayments(month: $0) }

    case .ownTransfers:
        return explicitMonth.map { .ownTransfers(month: $0) }

    case .investments:
        if let pos = extractPositionQuery(tokens: parsed.tokens, joined: parsed.joined, portfolio: portfolio) {
            return .investments(positionQuery: pos, moversOnly: false)
        }
        if clearBank { return .investments(positionQuery: nil, moversOnly: false) }
        return nil

    case .subscriptions, .freeMoney, .briefingRecap, .adviceRequest, .unsupportedPeriod, .unknown:
        return nil
    }
}

/// Enruta una pregunta para Nyx respetando el orden: barrera de consejo → preguntas propias de Nyx → seguida → enrutador normal.
public func nyxRouteQuestion(_ question: String, conversation: NyxConversation, state: LedgerState,
                             portfolio: Portfolio?, now: Date, calendar: Calendar) -> NyxQuestion {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .assistant(.unknown) }

    let knownMerchants = ledgerMerchantKeys(in: state)
    if isAdviceRequest(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) {
        return .assistant(routeAssistantQuestion(trimmed, state: state, portfolio: portfolio, now: now, calendar: calendar))
    }

    let parsed = nyxFoldedTokens(trimmed)
    if let own = nyxOwnQuestion(tokens: parsed.tokens, joined: parsed.joined) {
        return own
    }

    if let previous = conversation.lastIntent,
       let merged = nyxFollowUp(trimmed, after: previous, state: state, portfolio: portfolio, now: now, calendar: calendar) {
        return .assistant(merged)
    }

    return .assistant(routeAssistantQuestion(trimmed, state: state, portfolio: portfolio, now: now, calendar: calendar))
}

private func nyxShouldRemember(_ intent: AssistantIntent) -> Bool {
    switch intent {
    case .unknown, .unsupportedPeriod, .adviceRequest: false
    default: true
    }
}

private let nyxConversationWeekdays = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

private func nyxSeenSinceLabel(_ since: Date, hidden: Bool, now: Date, calendar: Calendar) -> String {
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since),
                                       to: calendar.startOfDay(for: now)).day ?? 0
    switch days {
    case ...0: return "hoy"
    case 1: return "ayer"
    default:
        guard hidden else {
            return "el " + shortSpanishDate(since, calendar: calendar, withYear: false)
        }
        if days <= 6 {
            let weekday = nyxConversationWeekdays[((calendar.component(.weekday, from: since) - 1) % 7 + 7) % 7]
            return "el \(weekday)"
        }
        return "la semana pasada"
    }
}

private func nyxSeenAnswer(memory: NyxMemory, privateMode: Bool, now: Date, calendar: Calendar) -> AssistantAnswer {
    let cutoff = now.addingTimeInterval(-7 * 86_400)
    let recent = memory.entries.filter { $0.observation.observedAt >= cutoff && $0.observation.observedAt <= now }
    guard !recent.isEmpty else {
        return AssistantAnswer(intent: .unknown,
                               lines: [BriefingLine(id: "seen-empty",
                                                    parts: [.text("No he visto nada nuevo desde la última vez.")])])
    }
    let oldest = recent.map(\.observation.observedAt).min() ?? cutoff
    let sinceLabel = nyxSeenSinceLabel(oldest, hidden: privateMode, now: now, calendar: calendar)
    var lines = [BriefingLine(id: "seen-header", parts: [.text("Esto es lo que he visto desde \(sinceLabel):")])]
    for entry in recent {
        let message = nyxMessage(for: entry.observation, now: now, calendar: calendar)
        let parts: [BriefingPart] = privateMode ? [.text(nyxDisplayText(message, hidden: true))] : message.open
        lines.append(BriefingLine(id: "seen-\(entry.id)", parts: parts))
    }
    return AssistantAnswer(intent: .unknown, lines: lines)
}

private func nyxAppStatusAnswer(health: [NyxObservation], privateMode: Bool, now: Date, calendar: Calendar) -> AssistantAnswer {
    guard !health.isEmpty else {
        return AssistantAnswer(intent: .unknown,
                               lines: [BriefingLine(id: "health-ok",
                                                    parts: [.text("No veo ningún problema con tus bancos ni con los avisos.")])])
    }
    let lines = health.map { obs in
        let message = nyxMessage(for: obs, now: now, calendar: calendar)
        let parts: [BriefingPart] = privateMode ? [.text(nyxDisplayText(message, hidden: true))] : message.open
        return BriefingLine(id: "health-\(obs.id)", parts: parts)
    }
    return AssistantAnswer(intent: .unknown, lines: lines)
}

/// Responde a una pregunta para Nyx actualizando la memoria breve de la conversación.
/// La barrera contra consejos de inversión corre siempre primero, también en preguntas seguidas.
public func nyxAnswer(_ question: String, conversation: inout NyxConversation, modelIntent: AssistantIntent?,
                      memory: NyxMemory, health: [NyxObservation], state: LedgerState, portfolio: Portfolio?,
                      book: AccountBook, privateMode: Bool = false, now: Date, calendar: Calendar) -> NyxReply {
    let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let knownMerchants = ledgerMerchantKeys(in: state)
    let modelAsksAdvice: Bool = if case .adviceRequest? = modelIntent { true } else { false }

    // 1. Barrera de consejo SIEMPRE primero.
    if modelAsksAdvice || isAdviceRequest(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) {
        let answer = answerQuestion(trimmed, state: state, portfolio: portfolio, book: book,
                                    modelIntent: modelIntent, now: now, calendar: calendar)
        let underlying = routeAssistantQuestionWithoutAdviceGate(trimmed, state: state, portfolio: portfolio,
                                                                 now: now, calendar: calendar)
        if nyxShouldRemember(underlying) { conversation.remember(underlying) }
        return NyxReply(question: .assistant(answer.intent), answer: answer)
    }

    // 2. Preguntas propias de Nyx («¿qué has visto?», «¿va todo bien con la app?»).
    let parsed = nyxFoldedTokens(trimmed)
    if let own = nyxOwnQuestion(tokens: parsed.tokens, joined: parsed.joined) {
        switch own {
        case .seen:
            return NyxReply(question: .seen,
                            answer: nyxSeenAnswer(memory: memory, privateMode: privateMode, now: now, calendar: calendar))
        case .appStatus:
            return NyxReply(question: .appStatus,
                            answer: nyxAppStatusAnswer(health: health, privateMode: privateMode, now: now, calendar: calendar))
        case .assistant:
            break
        }
    }

    // 3. Pregunta seguida sobre la intención anterior.
    if let previous = conversation.lastIntent,
       let merged = nyxFollowUp(trimmed, after: previous, state: state, portfolio: portfolio, now: now, calendar: calendar) {
        let isInvestments: Bool = if case .investments = merged { true } else { false }
        if !isInvestments, questionNamesInvestmentSubject(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) {
            let answer = answerQuestion(trimmed, state: state, portfolio: portfolio, book: book,
                                        modelIntent: merged, now: now, calendar: calendar)
            if nyxShouldRemember(merged) { conversation.remember(merged) }
            return NyxReply(question: .assistant(answer.intent), answer: answer)
        }
        let answer = answerIntent(merged, state: state, portfolio: portfolio, book: book, now: now, calendar: calendar)
        if nyxShouldRemember(merged) { conversation.remember(merged) }
        return NyxReply(question: .assistant(merged), answer: answer)
    }

    // 4. Camino normal del asistente (con `modelIntent` si lo hubo).
    let answer = answerQuestion(trimmed, state: state, portfolio: portfolio, book: book,
                                modelIntent: modelIntent, now: now, calendar: calendar)
    if nyxShouldRemember(answer.intent) {
        conversation.remember(answer.intent)
    } else if answer.isAdviceRefusal {
        let underlying = routeAssistantQuestionWithoutAdviceGate(trimmed, state: state, portfolio: portfolio,
                                                                 now: now, calendar: calendar)
        if nyxShouldRemember(underlying) { conversation.remember(underlying) }
    }
    return NyxReply(question: .assistant(answer.intent), answer: answer)
}
