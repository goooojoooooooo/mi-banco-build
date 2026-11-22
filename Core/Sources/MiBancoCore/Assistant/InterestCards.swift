import Foundation

/// Los seis temas de «Te puede interesar» (A4). Su valor crudo se persiste en el dispositivo para los interruptores de
/// Ajustes → Asistente y para los pesos aprendidos con «Me interesa» / «No me interesa».
public enum AssistantTopic: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case unusualPayment
    case subscriptionPriceChange
    case budgetClose
    case shortfall
    case spendingPace
    case portfolioMover

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unusualPayment: "Pagos poco habituales"
        case .subscriptionPriceChange: "Cambios en suscripciones"
        case .budgetClose: "Presupuestos cerca del límite"
        case .shortfall: "Cobros que dejan una cuenta justa"
        case .spendingPace: "Ritmo de gasto del mes"
        case .portfolioMover: "Movimientos en inversiones"
        }
    }
}

/// Elección del dueño sobre una tarjeta de «Te puede interesar».
public enum CardFeedback: String, Codable, Equatable, Sendable {
    case interested
    case notInterested
}

/// Registro de la respuesta dada a una tarjeta concreta (para ocultar las descartadas y evitar que repetir el toque infle el peso).
public struct RecordedCardFeedback: Codable, Equatable, Sendable {
    public let feedback: CardFeedback
    public let date: Date
    /// Cambio real que aplicó sobre el peso del tema (0 si ya estaba en el tope): permite deshacerlo con exactitud si cambia de opinión.
    public let appliedDelta: Int

    public init(feedback: CardFeedback, date: Date, appliedDelta: Int? = nil) {
        self.feedback = feedback
        self.date = date
        self.appliedDelta = appliedDelta ?? (feedback == .interested ? 1 : -1)
    }

    private enum CodingKeys: String, CodingKey { case feedback, date, appliedDelta }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        feedback = try c.decode(CardFeedback.self, forKey: .feedback)
        date = try c.decode(Date.self, forKey: .date)
        let rawDelta = try c.decodeIfPresent(Int.self, forKey: .appliedDelta)
        appliedDelta = rawDelta.map { min(1, max(-1, $0)) } ?? (feedback == .interested ? 1 : -1)
    }
}

private struct LossyDecodable<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// Preferencias del asistente guardadas solo en el dispositivo: interruptores por tema, pesos y respuestas por tarjeta.
/// Decodificación tolerante: claves nuevas o entradas dañadas se ignoran sin romper lo demás.
public struct AssistantPreferences: Codable, Equatable, Sendable {
    public static let minWeight = -5
    public static let maxWeight = 5
    static let feedbackRetentionDays = 30
    static let maxFeedbackEntries = 200

    /// Temas apagados en Ajustes → Asistente. Guardar los apagados hace que todo tema nuevo empiece activo.
    public var disabledTopics: Set<AssistantTopic>
    /// Peso por tema en `minWeight...maxWeight`, ajustado por «Me interesa» (+1) y «No me interesa» (−1).
    public var topicWeights: [AssistantTopic: Int]
    /// Respuestas ya dadas por identificador de tarjeta.
    public var cardFeedback: [String: RecordedCardFeedback]

    public init(disabledTopics: Set<AssistantTopic> = [], topicWeights: [AssistantTopic: Int] = [:],
                cardFeedback: [String: RecordedCardFeedback] = [:]) {
        self.disabledTopics = disabledTopics
        var cleanWeights: [AssistantTopic: Int] = [:]
        for (topic, w) in topicWeights {
            let clamped = Self.clampedWeight(w)
            if clamped != 0 { cleanWeights[topic] = clamped }
        }
        self.topicWeights = cleanWeights
        self.cardFeedback = Self.cappedFeedback(cardFeedback)
    }

    public func isEnabled(_ topic: AssistantTopic) -> Bool {
        !disabledTopics.contains(topic)
    }

    public mutating func setEnabled(_ enabled: Bool, for topic: AssistantTopic) {
        if enabled { disabledTopics.remove(topic) } else { disabledTopics.insert(topic) }
    }

    public func weight(for topic: AssistantTopic) -> Int {
        Self.clampedWeight(topicWeights[topic] ?? 0)
    }

    public func feedback(for cardID: String) -> CardFeedback? {
        cardFeedback[cardID]?.feedback
    }

    /// Registra «Me interesa» o «No me interesa» sobre una tarjeta y ajusta el peso del tema de forma acotada e idempotente.
    public mutating func recordFeedback(_ feedback: CardFeedback, cardID: String, topic: AssistantTopic, now: Date) {
        let existing = cardFeedback[cardID]
        if let existing, existing.feedback == feedback {
            cardFeedback[cardID] = RecordedCardFeedback(feedback: feedback, date: now, appliedDelta: existing.appliedDelta)
            pruneFeedback(now: now)
            return
        }
        // Deshace primero el cambio real anterior (0 si estuvo en el tope) y aplica el nuevo (±1), acotado.
        let baseWeight = Self.clampedWeight(weight(for: topic) - (existing?.appliedDelta ?? 0))
        let desired = feedback == .interested ? 1 : -1
        let updated = Self.clampedWeight(baseWeight + desired)
        let actualDelta = updated - baseWeight
        if updated == 0 { topicWeights.removeValue(forKey: topic) } else { topicWeights[topic] = updated }
        cardFeedback[cardID] = RecordedCardFeedback(feedback: feedback, date: now, appliedDelta: actualDelta)
        pruneFeedback(now: now)
    }

    public mutating func recordFeedback(_ feedback: CardFeedback, for card: InterestCard, now: Date) {
        recordFeedback(feedback, cardID: card.id, topic: card.topic, now: now)
    }

    private mutating func pruneFeedback(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(Self.feedbackRetentionDays) * 86_400)
        cardFeedback = Self.cappedFeedback(cardFeedback.filter { $0.value.date >= cutoff })
    }

    private static func cappedFeedback(_ entries: [String: RecordedCardFeedback]) -> [String: RecordedCardFeedback] {
        guard entries.count > maxFeedbackEntries else { return entries }
        let newest = entries.sorted {
            $0.value.date != $1.value.date ? $0.value.date > $1.value.date : $0.key < $1.key
        }.prefix(maxFeedbackEntries)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    private static func clampedWeight(_ value: Int) -> Int {
        min(maxWeight, max(minWeight, value))
    }

    private enum CodingKeys: String, CodingKey { case disabledTopics, topicWeights, cardFeedback }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let rawDisabled = try? c.decode([LossyDecodable<String>].self, forKey: .disabledTopics) {
            disabledTopics = Set(rawDisabled.compactMap(\.value).compactMap(AssistantTopic.init(rawValue:)))
        }
        if let rawWeights = try? c.decode([String: LossyDecodable<Int>].self, forKey: .topicWeights) {
            var parsed: [AssistantTopic: Int] = [:]
            for (k, v) in rawWeights {
                guard let topic = AssistantTopic(rawValue: k), let w = v.value else { continue }
                let clamped = Self.clampedWeight(w)
                if clamped != 0 { parsed[topic] = clamped }
            }
            topicWeights = parsed
        }
        if let rawFeedback = try? c.decode([String: LossyDecodable<RecordedCardFeedback>].self, forKey: .cardFeedback) {
            cardFeedback = Self.cappedFeedback(rawFeedback.compactMapValues(\.value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(disabledTopics.map(\.rawValue).sorted(), forKey: .disabledTopics)
        var rawWeights: [String: Int] = [:]
        for (topic, w) in topicWeights where w != 0 { rawWeights[topic.rawValue] = Self.clampedWeight(w) }
        try c.encode(rawWeights, forKey: .topicWeights)
        try c.encode(cardFeedback, forKey: .cardFeedback)
    }
}

/// Una tarjeta de «Te puede interesar». `title` no lleva cifras (seguro en modo privado); cada importe o porcentaje va en `parts`.
public struct InterestCard: Equatable, Sendable, Identifiable {
    public let id: String
    public let topic: AssistantTopic
    public let title: String
    public let parts: [BriefingPart]
    public let action: BriefingAction?

    public init(id: String, topic: AssistantTopic, title: String, parts: [BriefingPart], action: BriefingAction? = nil) {
        self.id = id
        self.topic = topic
        self.title = title
        self.parts = parts
        self.action = action
    }
}

/// Máximo de tarjetas de «Te puede interesar» al día (A4).
public let maxInterestCards = 3

private let cardRecentWindow: TimeInterval = 7 * 86_400
private let weightStep = 15
private let cardMonthNames = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                              "octubre", "noviembre", "diciembre"]
private let cardWeekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
private let cardShortMonths = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

private func cardDayKey(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
}

private func cardMonthKey(_ date: Date, _ calendar: Calendar) -> String {
    let c = calendar.dateComponents([.year, .month], from: date)
    return "\(c.year ?? 0)-\(c.month ?? 0)"
}

private func cardShortDate(_ date: Date, _ calendar: Calendar) -> String {
    let m = calendar.component(.month, from: date)
    return "\(calendar.component(.day, from: date)) \(cardShortMonths[(m - 1 + 12) % 12])"
}

private func cardMedian(_ values: [Int]) -> Int {
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

private func cardIsMuted(_ merchant: String?, in state: LedgerState) -> Bool {
    guard let merchant else { return false }
    let key = normalizeMerchant(merchant)
    return !key.isEmpty && state.mutedMerchants.contains(key)
}

private struct ScoredCard {
    let card: InterestCard
    let basePriority: Int
    /// U4: las tarjetas GRAVES («Falta saldo para un cobro» y «Presupuesto superado») van SIEMPRE por delante de las normales.
    let isSevere: Bool
}

/// Hasta tres tarjetas al día para «Te puede interesar», elegidas por reglas sobre los datos del libro y la cartera,
/// ordenadas primero por gravedad (U4) y dentro de cada nivel por prioridad más el peso de cada tema, respetando temas apagados y descartes.
public func interestCards(state: LedgerState, portfolio: Portfolio?, book: AccountBook, now: Date, calendar: Calendar,
                          preferences: AssistantPreferences = AssistantPreferences()) -> [InterestCard] {
    let exclusions = spendingExclusions(in: state, now: now)
    func isDismissed(_ id: String) -> Bool { preferences.feedback(for: id) == .notInterested }

    var candidates: [ScoredCard] = []

    // 1. Cobro que deja un banco corto (3 días urgentes = GRAVE, o caída por debajo del mínimo en los próximos 14 días = NORMAL).
    if preferences.isEnabled(.shortfall) {
        if let hit = shortfallCard(state: state, book: book, now: now, calendar: calendar,
                                   exclusions: exclusions, isDismissed: isDismissed) {
            candidates.append(hit)
        }
    }

    // 2. Presupuesto superado (GRAVE) o cerca del límite (≥ 80 %, NORMAL).
    if preferences.isEnabled(.budgetClose) {
        if let hit = budgetCard(state: state, now: now, calendar: calendar,
                                exclusions: exclusions, isDismissed: isDismissed) {
            candidates.append(hit)
        }
    }

    // 3. Cambio de precio en una suscripción reciente.
    if preferences.isEnabled(.subscriptionPriceChange) {
        if let card = subscriptionChangeCard(state: state, now: now, calendar: calendar,
                                             exclusions: exclusions, isDismissed: isDismissed) {
            candidates.append(ScoredCard(card: card, basePriority: 65, isSevere: false))
        }
    }

    // 4. Pago poco habitual reciente (al menos 3× la mediana habitual del comercio con ≥ 3 pagos previos).
    if preferences.isEnabled(.unusualPayment) {
        if let card = unusualPaymentCard(state: state, now: now, calendar: calendar,
                                         exclusions: exclusions, isDismissed: isDismissed) {
            candidates.append(ScoredCard(card: card, basePriority: 60, isSevere: false))
        }
    }

    // 5. Ritmo de gasto del mes frente al mes anterior (a partir del día 6 y ≥ 10 € de diferencia).
    if preferences.isEnabled(.spendingPace) {
        if let card = spendingPaceCard(state: state, now: now, calendar: calendar,
                                       exclusions: exclusions, isDismissed: isDismissed) {
            candidates.append(ScoredCard(card: card, basePriority: 50, isSevere: false))
        }
    }

    // 6. Movimiento destacado en la cartera (hechos, nunca consejo).
    if preferences.isEnabled(.portfolioMover), let portfolio {
        if let card = portfolioMoverCard(portfolio: portfolio, now: now, calendar: calendar, isDismissed: isDismissed) {
            candidates.append(ScoredCard(card: card, basePriority: 45, isSevere: false))
        }
    }

    let topicOrder = Dictionary(uniqueKeysWithValues: AssistantTopic.allCases.enumerated().map { ($1, $0) })
    let ranked = candidates.sorted { a, b in
        if a.isSevere != b.isSevere { return a.isSevere }
        let sa = a.basePriority + preferences.weight(for: a.card.topic) * weightStep
        let sb = b.basePriority + preferences.weight(for: b.card.topic) * weightStep
        if sa != sb { return sa > sb }
        if a.basePriority != b.basePriority { return a.basePriority > b.basePriority }
        let oa = topicOrder[a.card.topic] ?? 0, ob = topicOrder[b.card.topic] ?? 0
        if oa != ob { return oa < ob }
        return a.card.id < b.card.id
    }
    return Array(ranked.prefix(maxInterestCards).map(\.card))
}

// MARK: Generadores por tema

private func shortfallCard(state: LedgerState, book: AccountBook, now: Date, calendar: Calendar,
                           exclusions: Set<UUID>, isDismissed: (String) -> Bool) -> ScoredCard? {
    let ledger = Ledger(state: state)
    var balances: [BankID: Int] = [:]
    var estimated = Set<BankID>()
    for b in BankID.allCases {
        guard let reading = ledger.balance(b) else { continue }
        balances[b] = reading.cents
        if reading.estimated { estimated.insert(b) }
    }
    let startOfToday = calendar.startOfDay(for: now)
    let allCharges = subscriptionCharges(in: state, now: now, calendar: calendar, notSpending: exclusions)
    let horizon = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now
    let soonCharges = allCharges.filter { $0.date >= startOfToday && $0.date < horizon }
    let urgent = shortfalls(balances: balances, floors: book.floors, upcoming: soonCharges, now: now, calendar: calendar,
                            estimated: estimated)
    let urgentBanks = Set(urgent.map(\.bank))
    for s in urgent {
        // U4: el id incluye `suggestedCents` para que un caso más grave vuelva a salir aunque se descartara el menor.
        let id = "shortfall|\(s.bank.rawValue)|\(normalizeMerchant(s.charge.name))|\(cardDayKey(s.charge.date, calendar))|\(s.suggestedCents)"
        guard !isDismissed(id) else { continue }
        let line = shortfallLine(id: id, shortfall: s, now: now, calendar: calendar)
        let card = InterestCard(id: id, topic: .shortfall, title: "Falta saldo para un cobro",
                                parts: line.parts, action: line.action)
        return ScoredCard(card: card, basePriority: 100, isSevere: true)
    }

    // Solo para bancos que tienen cobros próximos (I5) y que NO estaban ya cubiertos por `urgent` (I4: descartar no resucita).
    let days = upcomingCalendar(state: state, book: book, now: now, calendar: calendar)
    let firstBelow = firstChargeBelowFloorDays(days)
    for b in BankID.allCases where !urgentBanks.contains(b) {
        guard let day = firstBelow[b] else { continue }
        let id = "shortfall-cal|\(b.rawValue)|\(cardDayKey(day, calendar))"
        guard !isDismissed(id) else { continue }
        let hasFloor = (book.floors[b] ?? 0) > 0
        let detail = hasFloor
            ? "Con los próximos cobros, \(b.displayName) quedaría por debajo de su mínimo el \(cardShortDate(day, calendar))."
            : "Con los próximos cobros, \(b.displayName) se quedaría en negativo el \(cardShortDate(day, calendar))."
        let card = InterestCard(
            id: id, topic: .shortfall, title: "Saldo justo para un cobro",
            parts: [.text(detail)],
            action: .moveMoney(from: nil, to: b, cents: nil))
        return ScoredCard(card: card, basePriority: 100, isSevere: false)
    }
    return nil
}

private func budgetCard(state: LedgerState, now: Date, calendar: Calendar,
                        exclusions: Set<UUID>, isDismissed: (String) -> Bool) -> ScoredCard? {
    let statuses = budgetStatuses(in: state, month: now, now: now, calendar: calendar, notSpending: exclusions)
        .filter { $0.level == .exceeded || $0.level == .warning }
        .sorted { a, b in
            if a.percent != b.percent { return a.percent > b.percent }
            return a.id < b.id
        }
    for status in statuses {
        let id = "budgetClose|\(status.id)|\(status.level.rawValue)|\(cardMonthKey(now, calendar))"
        guard !isDismissed(id) else { continue }
        let label: String
        switch status.scope {
        case .month: label = "tu presupuesto del mes"
        case .category(let c): label = c.displayName
        }
        if status.level == .exceeded {
            let card = InterestCard(
                id: id, topic: .budgetClose, title: "Presupuesto superado",
                parts: [.text("Te has pasado en \(label): llevas "), .amount(status.spentCents),
                        .text(" de "), .amount(status.limitCents), .text(".")],
                action: .openBudgets)
            return ScoredCard(card: card, basePriority: 80, isSevere: true)
        } else {
            let card = InterestCard(
                id: id, topic: .budgetClose, title: "Presupuesto cerca del límite",
                parts: [.text("Llevas "), .amount(status.spentCents), .text(" de "), .amount(status.limitCents),
                        .text(" en \(label): te quedan "), .amount(status.remainingCents), .text(".")],
                action: .openBudgets)
            return ScoredCard(card: card, basePriority: 70, isSevere: false)
        }
    }
    return nil
}

private func subscriptionChangeCard(state: LedgerState, now: Date, calendar: Calendar,
                                    exclusions: Set<UUID>, isDismissed: (String) -> Bool) -> InterestCard? {
    func matchingMovement(for sub: Subscription) -> Movement? {
        state.movements.first {
            $0.kind == .payment && !$0.flaggedNotMine && !$0.excludedFromSpending && !exclusions.contains($0.id)
                && $0.bank == sub.bank && $0.date == sub.lastDate && abs($0.amountCents) == sub.amountCents
                && normalizeMerchant($0.merchant ?? "") == sub.id
        }
    }
    let subs = activeSubscriptions(in: state, now: now, calendar: calendar, notSpending: exclusions)
        .filter { sub in
            guard sub.previousAmountCents != nil,
                  !cardIsMuted(sub.merchant, in: state) else { return false }
            if let matching = matchingMovement(for: sub) {
                guard !matching.isHistorical,
                      movementCounts(matching, upTo: now, calendar: calendar) else { return false }
                let effective = matching.dayOnly ? calendar.startOfDay(for: matching.date) : matching.date
                return now.timeIntervalSince(effective) < cardRecentWindow
            }
            return sub.lastDate <= now && now.timeIntervalSince(sub.lastDate) < cardRecentWindow
        }
        .sorted { a, b in
            let da = abs(a.amountCents - (a.previousAmountCents ?? a.amountCents))
            let db = abs(b.amountCents - (b.previousAmountCents ?? b.amountCents))
            if da != db { return da > db }
            if a.lastDate != b.lastDate { return a.lastDate > b.lastDate }
            return a.id < b.id
        }
    for sub in subs {
        guard let before = sub.previousAmountCents else { continue }
        let id = "subscriptionPriceChange|\(sub.bank.rawValue)|\(sub.id)|\(cardDayKey(sub.lastDate, calendar))"
        guard !isDismissed(id) else { continue }
        let diff = abs(sub.amountCents - before)
        let up = sub.amountCents > before
        let movementID = matchingMovement(for: sub)?.id
        return InterestCard(
            id: id, topic: .subscriptionPriceChange, title: "Cambio en una suscripción",
            parts: [.text("\(clippedName(sub.merchant)) ha \(up ? "subido" : "bajado") "), .amount(diff),
                    .text(": ahora son "), .amount(sub.amountCents), .text(" al mes.")],
            action: movementID.map(BriefingAction.openMovement))
    }
    return nil
}

private func unusualPaymentCard(state: LedgerState, now: Date, calendar: Calendar,
                                exclusions: Set<UUID>, isDismissed: (String) -> Bool) -> InterestCard? {
    let index = MerchantIndex(state.movements, notSpending: exclusions)
    var hits: [(movement: Movement, usual: Int)] = []
    for m in spendingMovements(in: state.movements, notSpending: exclusions) {
        let effective = m.dayOnly ? calendar.startOfDay(for: m.date) : m.date
        guard !m.isHistorical, movementCounts(m, upTo: now, calendar: calendar),
              now.timeIntervalSince(effective) < cardRecentWindow,
              !cardIsMuted(m.merchant, in: state) else { continue }
        let key = normalizeMerchant(m.merchant ?? "")
        guard !key.isEmpty else { continue }
        let previous = index.payments(for: key).filter { $0.id != m.id && $0.date <= m.date }.map { abs($0.amountCents) }
        guard previous.count >= 3 else { continue }
        let usual = cardMedian(previous)
        let cents = abs(m.amountCents)
        guard usual > 0, cents >= usual * 3 else { continue }
        hits.append((m, usual))
    }
    hits.sort { a, b in
        if a.movement.date != b.movement.date { return a.movement.date > b.movement.date }
        let aa = abs(a.movement.amountCents), bb = abs(b.movement.amountCents)
        if aa != bb { return aa > bb }
        return a.movement.id.uuidString < b.movement.id.uuidString
    }
    for hit in hits {
        let m = hit.movement
        let id = "unusualPayment|\(m.id.uuidString)"
        guard !isDismissed(id) else { continue }
        let name = clippedName(m.displayMerchant ?? m.merchant ?? m.bank.displayName)
        return InterestCard(
            id: id, topic: .unusualPayment, title: "Pago poco habitual",
            parts: [.text("\(name): "), .amount(abs(m.amountCents)),
                    .text(". Sueles gastar unos "), .amount(hit.usual), .text(".")],
            action: .openMovement(m.id))
    }
    return nil
}

private func spendingPaceCard(state: LedgerState, now: Date, calendar: Calendar,
                              exclusions: Set<UUID>, isDismissed: (String) -> Bool) -> InterestCard? {
    guard calendar.component(.day, from: now) > 5,
          let pace = spendingPace(movements: state.movements, now: now, calendar: calendar, notSpending: exclusions),
          abs(pace.differenceCents) >= 1_000 else { return nil }
    let id = "spendingPace|\(cardMonthKey(now, calendar))|\(cardDayKey(now, calendar))"
    guard !isDismissed(id) else { return nil }
    let below = pace.differenceCents < 0
    let prevMonthIndex = (calendar.component(.month, from: now) + 10) % 12
    let prevName = cardMonthNames[prevMonthIndex]
    return InterestCard(
        id: id, topic: .spendingPace, title: "Ritmo de gasto del mes",
        parts: [.text("Vas "), .amount(abs(pace.differenceCents)),
                .text(" por \(below ? "debajo" : "encima") de \(prevName) a estas alturas (llevas "),
                .amount(pace.thisMonthCents), .text(").")],
        action: .openBudgets)
}

private func portfolioMoverCard(portfolio: Portfolio, now: Date, calendar: Calendar,
                                isDismissed: (String) -> Bool) -> InterestCard? {
    guard let summary = portfolioSummary(portfolio, now: now, calendar: calendar),
          let day = summary.changeDay else { return nil }
    let id = "portfolioMover|\(cardDayKey(day, calendar))"
    guard !isDismissed(id) else { return nil }

    // Con 2+ posiciones con precio de mercado vigente (≤ 4 días) del día del cambio, usa la línea de movers si alguna se movió ≥ 1,0 %.
    var dayMovers: [(name: String, tenths: Int)] = []
    for p in summary.positions {
        guard case .market(let at) = p.origin, calendar.startOfDay(for: at) == day,
              now.timeIntervalSince(at) <= stalePriceAge,
              let val = p.valueCents, let ch = p.todayChangeCents, val - ch > 0,
              let tenths = roundedQuotient(1000 * ch, val - ch) else { continue }
        dayMovers.append((p.position.name, tenths))
    }
    guard let maxMove = dayMovers.map({ abs($0.tenths) }).max() else { return nil }

    if dayMovers.count >= 2, maxMove >= 10 {
        var best = 0, worst = 0
        for i in dayMovers.indices {
            if dayMovers[i].tenths > dayMovers[best].tenths { best = i }
            if dayMovers[i].tenths < dayMovers[worst].tenths { worst = i }
        }
        let up = dayMovers[best].tenths > 0, down = dayMovers[worst].tenths < 0
        if best != worst, dayMovers[best].tenths != dayMovers[worst].tenths, up || down {
            let isToday = (calendar.dateComponents([.day], from: calendar.startOfDay(for: day),
                                                   to: calendar.startOfDay(for: now)).day ?? 0) <= 0
            var prefix = isToday ? "" : "En la última sesión (\(cardWeekdayNames[((calendar.component(.weekday, from: day) - 1) % 7 + 7) % 7])), "
            var parts: [BriefingPart] = []
            func phrase(_ label: String, _ mover: (name: String, tenths: Int)) {
                let head = prefix.isEmpty ? (label.prefix(1).uppercased() + label.dropFirst()) : prefix + label
                prefix = ""
                parts += [.text((parts.isEmpty ? "" : " ") + "\(head): \(clippedName(mover.name)) ("), .percentTenths(mover.tenths), .text(").")]
            }
            if up { phrase("lo que más subió", dayMovers[best]) }
            if down { phrase("lo que más bajó", dayMovers[worst]) }
            return InterestCard(id: id, topic: .portfolioMover, title: "Movimiento en inversiones",
                                parts: parts, action: .openInvestments)
        }
    }

    // Con una sola posición con precio de mercado del día que se haya movido al menos un 2,0 %, la enseña sin verbos de acción.
    if dayMovers.count == 1, let only = dayMovers.first, abs(only.tenths) >= 20 {
        let isToday = (calendar.dateComponents([.day], from: calendar.startOfDay(for: day),
                                               to: calendar.startOfDay(for: now)).day ?? 0) <= 0
        let when = isToday ? "hoy" : "en la última sesión (\(cardWeekdayNames[((calendar.component(.weekday, from: day) - 1) % 7 + 7) % 7]))"
        return InterestCard(
            id: id, topic: .portfolioMover, title: "Movimiento en inversiones",
            parts: [.text("\(clippedName(only.name)) \(when): "), .percentTenths(only.tenths), .text(".")],
            action: .openInvestments)
    }
    return nil
}
