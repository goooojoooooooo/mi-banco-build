import Foundation

/// Mes al que se refiere una pregunta del asistente.
public enum AssistantMonth: Equatable, Hashable, Sendable {
    case current
    case previous
    case specific(year: Int, month: Int)

    /// Inicio del mes en el calendario dado; nil si el mes específico no es válido (fuera de 1...12).
    public func resolvedStart(now: Date, calendar: Calendar) -> Date? {
        guard let currentStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        switch self {
        case .current:
            return currentStart
        case .previous:
            return calendar.date(byAdding: .month, value: -1, to: currentStart)
        case let .specific(year, month):
            guard (1...12).contains(month), (2000...2100).contains(year) else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }
    }
}

/// Intención a la que se traduce una pregunta del dueño. El modelo del dispositivo (si existe) solo elige una de estas con sus
/// parámetros; el Core calcula siempre las cifras y escribe las frases (J21(d)).
public enum AssistantIntent: Equatable, Hashable, Sendable {
    case balances(bank: BankID?)
    case spending(month: AssistantMonth, category: SpendingCategory?, merchant: String?)
    case biggestPayments(month: AssistantMonth)
    case subscriptions
    case upcomingCharges(bank: BankID?)
    case budgets(category: SpendingCategory?)
    case income(month: AssistantMonth)
    case ownTransfers(month: AssistantMonth)
    case freeMoney
    case investments(positionQuery: String?, moversOnly: Bool)
    case briefingRecap
    case adviceRequest(positionQuery: String?)
    case unknown
}

/// Pregunta sugerida que aparece como ficha debajo del campo de consulta.
public struct AssistantChip: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let question: String

    public init(id: String, label: String, question: String? = nil) {
        self.id = id
        self.label = label
        self.question = question ?? label
    }
}

/// Fichas sugeridas según lo que el dueño ya tiene en la app (saldos, presupuestos, inversiones...).
public func suggestedAssistantChips(state: LedgerState, portfolio: Portfolio?, now: Date,
                                    calendar: Calendar) -> [AssistantChip] {
    var chips: [AssistantChip] = [
        AssistantChip(id: "balances", label: "¿Cuánto tengo?"),
        AssistantChip(id: "spending", label: "¿Cuánto llevo este mes?"),
        AssistantChip(id: "upcoming", label: "¿Qué cobros vienen?"),
        AssistantChip(id: "free-money", label: "¿Cuánto dinero libre tengo?"),
    ]
    if state.budgets.monthlyCents != nil || !state.budgets.byCategory.isEmpty {
        chips.append(AssistantChip(id: "budgets", label: "¿Cómo van mis presupuestos?"))
    }
    if let portfolio, !positions(from: portfolio.transactions).isEmpty {
        chips.append(AssistantChip(id: "investments", label: "¿Cómo van mis inversiones?"))
    }
    if chips.count < 6 {
        let exclusions = spendingExclusions(in: state, now: now)
        if !activeSubscriptions(in: state, now: now, calendar: calendar, notSpending: exclusions).isEmpty {
            chips.append(AssistantChip(id: "subscriptions", label: "¿Qué suscripciones tengo?"))
        } else {
            chips.append(AssistantChip(id: "recap", label: "¿Qué ha pasado desde ayer?"))
        }
    }
    return Array(chips.prefix(6))
}

// MARK: Normalización y confusables

private func foldedQuery(_ text: String) -> String {
    withoutFormatCharacters(text)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .lowercased()
}

/// Cambia letras parecidas de otros alfabetos o latín extendido (cirílico «е»/«а», «đ», «ø», «ł»...) por su letra ASCII para
/// detectar trucos de escritura en peticiones de consejo (J22).
private let confusableMap: [Character: String] = [
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ї": "i", "ј": "j", "ѕ": "s", "ԁ": "d",
    "к": "k", "м": "m", "т": "t", "н": "h", "в": "b",
    "α": "a", "ε": "e", "ο": "o", "ρ": "p", "ν": "v", "υ": "u", "ι": "i", "κ": "k", "τ": "t", "χ": "x",
    "đ": "d", "ð": "d", "ø": "o", "ł": "l", "ı": "i", "ß": "ss", "þ": "p",
]

private func foldConfusables(_ text: String) -> String {
    var out = ""
    for ch in withoutFormatCharacters(text).lowercased() {
        if let mapped = confusableMap[ch] {
            out += mapped
        } else {
            out.append(ch)
        }
    }
    return out
}

/// Lecturas del texto original más las lecturas tras doblar caracteres confusables.
private func allQuestionReadings(_ text: String) -> [[String]] {
    var readings = wordReadings(text)
    let conf = foldConfusables(text)
    for r in wordReadings(conf) where !readings.contains(r) { readings.append(r) }
    return readings
}

/// true si una misma palabra mezcla letras ASCII (a-z) y letras no latinas (ataque de homóglifos como «vеndo» o «bυy»).
private func hasMixedScriptWord(_ text: String) -> Bool {
    let tokens = withoutFormatCharacters(text).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    for token in tokens {
        var hasASCII = false
        var hasNonLatin = false
        for scalar in token.decomposedStringWithCanonicalMapping.unicodeScalars {
            let cat = scalar.properties.generalCategory
            let isLetter = cat == .uppercaseLetter || cat == .lowercaseLetter || cat == .titlecaseLetter
                || cat == .modifierLetter || cat == .otherLetter
            guard isLetter else { continue }
            if scalar.value < 128 { hasASCII = true } else { hasNonLatin = true }
        }
        if hasASCII && hasNonLatin { return true }
    }
    return false
}

// MARK: Detector de peticiones de consejo de inversión (A3, J7, J15, J21(c), J22)

/// Palabras que por sí solas marcan una petición de consejo o de operación (nunca aparecen en preguntas factuales).
private let unconditionalAdviceWords: Set<String> = [
    "conviene", "convienen", "quedate", "quedarme", "tendrias", "should",
    "buy", "buys", "buying", "sell", "sells", "selling", "hold", "holds", "stay",
    "vendo", "vendes", "vende", "vender", "venderia", "venderias", "vendere", "venda", "vendas", "vendamos", "vendan",
    "vendemos", "venden",
    "compro", "comprar", "compraria", "comprarias", "comprare", "compres", "compremos", "compren", "compramos", "compran",
    "invierto", "inviertes", "invierte", "invertir", "invertiria", "invertirias", "invertire", "invierta", "inviertas",
    "inviertan", "invierten", "invertimos",
    "aguanto", "aguantas", "aguanta", "aguantar", "aguantaria", "aguantes", "aguante",
    "mantengo", "mantienes", "mantiene", "mantener", "manten", "mantendria", "mantengas", "mantenga",
]

/// Prefijos que marcan siempre petición de consejo.
private let unconditionalAdvicePrefixes = [
    "recomiend", "recomend", "aconsej", "suger", "sugier", "asesor", "aprovech",
    "diversific", "reequilibr", "rebalanc", "promedi", "deshaz", "convendr", "acumul", "refuerz", "reforz",
    "recommend", "purchase",
]

/// Frases que marcan siempre petición de consejo.
private let unconditionalAdvicePhrases = [
    "buen momento", "es momento de", "el momento de", "es hora de", "buena idea", "vale la pena", "merece la pena",
    "yo que tu", "yo de ti", "habria que", "tendrias que", "toma beneficios", "tomar beneficios", "recoger beneficios",
    "sal de", "salir de bolsa", "entrar en bolsa", "meter dinero en", "mete dinero en", "meto dinero en",
    "pon dinero en", "pongo dinero en", "poner dinero en", "donde meto", "donde meter", "donde pongo mi dinero",
    "donde poner mi dinero", "en que pongo", "en que poner", "donde invierto", "en que invierto", "donde invertir",
    "en que invertir", "sacar rentabilidad", "que hago con", "que haria", "que harias",
    "take profit", "take profits", "get out", "stay put", "should i", "good time to",
    "worth buying", "worth selling", "worth investing", "how much to invest", "what to invest",
    "mejor esperar", "espera a que", "esperar a que", "va a subir", "va a bajar", "van a subir", "van a bajar",
    "seguira subiendo", "seguira bajando",
]

/// Determinantes y palabras de contexto de gasto que convierten «compra»/«compras»/«venta»/«ventas» en sustantivo factual.
private let factualNounPredecessors: Set<String> = [
    "en", "de", "del", "categoria", "presupuesto", "presupuestos", "gasto", "gastos", "gaste", "llevo",
    "tu", "tus", "la", "las", "una", "unas", "esa", "esas", "esta", "estas", "mi", "mis", "su", "sus",
    "cada", "ultima", "ultimas", "primera", "primeras", "mayor", "mayores", "gran", "grandes",
]

/// Marcadores condicionales: piden consejo si acompañan vocabulario de inversión, una posición o una acción de mercado.
private let conditionalAdviceWords: Set<String> = [
    "deberia", "deberias", "deberiamos", "debo", "debes", "debemos", "debiera", "tendria", "podria", "podrias",
    "mejor", "considera", "considerar", "plantea", "plantear", "planteo", "evita", "evitar", "procura", "intenta",
    "opinas", "opinar", "wait", "avoid", "consider", "better",
]

private let conditionalAdvicePhrases = [
    "tengo que", "tienes que", "hay que", "crees que", "piensas que", "que me dices de",
]

private let marketActionPrefixes = [
    "esper", "aguard", "reduc", "toqu", "toc", "entr", "salg", "sali", "met", "retir", "apost", "oper", "dej",
    "subir", "bajar",
]

private let futurePriceWords: Set<String> = [
    "subira", "subiran", "bajara", "bajaran", "subiria", "bajaria",
]

/// Palabras de contexto de inversión para evaluar marcadores condicionales (sin bloquear preguntas factuales solas).
private let investmentContextPrefixes = [
    "invers", "invert", "inviert", "invirt", "accion", "cartera", "fondo", "bolsa", "posicion", "exposicion",
    "beneficio", "dividendo", "etf", "cripto", "bitcoin", "ethereum", "broker", "stock", "share", "fund",
    "portfolio", "crypto", "asset", "bono", "bond", "renta", "rentabil", "ibex", "nasdaq", "deposito", "tesoro",
]

private let investmentContextWords: Set<String> = [
    "mercado", "mercados", "oro", "gold", "btc", "eth", "msci", "sp500", "valores",
]

private func hasInvestmentContext(_ list: [String], portfolio: Portfolio?) -> Bool {
    if list.contains(where: { word in
        investmentContextWords.contains(word) || investmentContextPrefixes.contains(where: { word.hasPrefix($0) })
    }) { return true }
    if let portfolio {
        let joined = " " + list.joined(separator: " ") + " "
        for pos in positions(from: portfolio.transactions) {
            if positionMatchesInFolded(pos, foldedJoined: joined, tokens: list) { return true }
        }
    }
    return false
}

/// true si la pregunta del dueño pide un consejo de inversión (qué comprar, vender, mantener, cuánto invertir o predicciones).
/// A diferencia de `containsAdvice` (pensado para texto libre del modelo), NO rechaza preguntas factuales neutras como
/// «¿Cómo van mis inversiones?», «¿Cuánto vale mi cartera?» o «¿Cuánto gasté en compras?».
public func isAdviceRequest(_ question: String, portfolio: Portfolio? = nil) -> Bool {
    let trimmed = withoutFormatCharacters(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if hasMixedScriptWord(trimmed) { return true }

    for list in allQuestionReadings(trimmed) {
        let joined = " " + list.joined(separator: " ") + " "
        let invContext = hasInvestmentContext(list, portfolio: portfolio)

        // 1. Palabras y prefijos que siempre piden consejo.
        for word in list {
            if unconditionalAdviceWords.contains(word) { return true }
            if unconditionalAdvicePrefixes.contains(where: { word.hasPrefix($0) }) { return true }
            if futurePriceWords.contains(word) && invContext { return true }
        }
        // 2. Frases incondicionales.
        if unconditionalAdvicePhrases.contains(where: { joined.contains(" " + $0 + " ") }) { return true }

        // 3. «compra»/«compras»/«venta»/«ventas» como verbo (imperativo o indicativo), no como categoría o sustantivo factual.
        for (i, word) in list.enumerated() where word == "compra" || word == "compras" || word == "venta" || word == "ventas" {
            if i > 0, factualNounPredecessors.contains(list[i - 1]) { continue }
            if i == 0, (word == "venta" || word == "ventas"), i + 1 < list.count, list[i + 1] == "de" { continue }
            if word == "compras", i > 0, list[i - 1] == "que",
               i + 1 < list.count, ["hice", "he", "hubo", "fueron"].contains(list[i + 1]) { continue }
            return true
        }

        // 4. «compre» (sin tilde puede ser pasado «compré» en una tienda o subjuntivo de consejo).
        if list.contains("compre") {
            let pastShop = list.contains("cuanto") && list.contains("en") && !invContext
            if !pastShop { return true }
        }

        // 5. «entra en» / «no toques» con vocabulario de inversión.
        if invContext, joined.contains(" entra en ") || joined.contains(" entrar en ") || joined.contains(" no toques ") {
            return true
        }

        // 6. Marcadores condicionales + contexto de inversión o verbo de espera/reducción de cartera.
        let hasConditional = list.contains { conditionalAdviceWords.contains($0) }
            || conditionalAdvicePhrases.contains { joined.contains(" " + $0 + " ") }
        if hasConditional {
            if invContext { return true }
            let hasMarketAction = list.contains { w in
                marketActionPrefixes.contains { w.hasPrefix($0) }
            }
            // «¿qué tengo que pagar?» es cobros pendientes, no consejo; «¿debería esperar?» sí es consejo.
            let isBillQuestion = list.contains("pagar") || list.contains("cobro") || list.contains("cobros")
                || list.contains("recibo") || list.contains("recibos") || list.contains("factura") || list.contains("facturas")
            if hasMarketAction && !isBillQuestion { return true }
        }

        // 7. Verbos de cartera/reducción sin marcador cuando acompañan vocabulario de inversión («reduce exposición»).
        if invContext, list.contains(where: { $0.hasPrefix("reduc") || $0.hasPrefix("esper") || $0.hasPrefix("aguard") }) {
            return true
        }
    }
    return false
}

// MARK: Extracción de parámetros

private let spanishMonthNames: [(name: String, month: Int)] = [
    ("enero", 1), ("febrero", 2), ("marzo", 3), ("abril", 4), ("mayo", 5), ("junio", 6),
    ("julio", 7), ("agosto", 8), ("septiembre", 9), ("setiembre", 9), ("octubre", 10),
    ("noviembre", 11), ("diciembre", 12),
]

private func extractMonth(tokens: [String], joined: String, rawFolded: String, now: Date, calendar: Calendar) -> AssistantMonth {
    if joined.contains(" mes pasado ") || joined.contains(" mes anterior ") || joined.contains(" ultimo mes ") {
        return .previous
    }
    let currentYear = calendar.component(.year, from: now)
    let currentMonth = calendar.component(.month, from: now)
    // Buscar año explícito de 4 cifras (2020...2099).
    let digits = rawFolded.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { $0.count == 4 }
    let explicitYear = digits.compactMap(Int.init).first { (2020...2099).contains($0) }
    for entry in spanishMonthNames where tokens.contains(entry.name) {
        let year = explicitYear ?? (entry.month > currentMonth ? currentYear - 1 : currentYear)
        return .specific(year: year, month: entry.month)
    }
    return .current
}

private func extractBank(tokens: [String], joined: String) -> BankID? {
    if tokens.contains("revolut") { return .rev }
    if tokens.contains("imagin") || tokens.contains("caixabank") || tokens.contains("caixa") { return .ima }
    if joined.contains(" trade republic ") || tokens.contains("traderepublic") { return .tr }
    return nil
}

private let categoryMatchers: [(category: SpendingCategory, phrases: [String])] = [
    (.casa, ["casa y facturas", "casa", "facturas", "hogar", "alquiler", "luz", "agua", "fibra"]),
    (.comerFuera, ["comer fuera", "comida fuera", "restaurantes", "restaurante", "bares", "cenar fuera"]),
    (.supermercado, ["supermercado", "supermercados", "super", "alimentacion"]),
    (.transporte, ["transporte", "gasolina", "combustible", "taxi", "metro", "autobus"]),
    (.compras, ["compras", "ropa", "tiendas"]),
    (.suscripciones, ["suscripciones", "suscripcion"]),
    (.ocio, ["ocio", "entretenimiento", "cine", "gimnasio"]),
    (.viajes, ["viajes", "viaje", "hoteles", "vuelos"]),
    (.salud, ["salud", "farmacia", "medico", "dentista"]),
    (.personas, ["personas", "bizum", "amigos"]),
    (.efectivo, ["efectivo", "cajero", "metalico"]),
    (.sinCategoria, ["sin categoria"]),
]

private func extractCategory(joined: String) -> SpendingCategory? {
    for entry in categoryMatchers {
        for phrase in entry.phrases where joined.contains(" " + phrase + " ") {
            return entry.category
        }
    }
    return nil
}

/// Palabras demasiado cortas o genéricas que no identifican por sí solas una posición de cartera.
private let positionStopWords: Set<String> = [
    "core", "fund", "etf", "ucits", "acc", "eur", "usd", "inc", "corp", "plc", "ltd", "the", "and", "class",
    "de", "la", "el", "los", "las", "en", "con", "por", "para", "del", "mis", "tus", "sus",
]

private func positionMatchesInFolded(_ position: Position, foldedJoined: String, tokens: [String]) -> Bool {
    let instrument = normalizeMerchant(position.instrument)
    if !instrument.isEmpty, instrument.count >= 2, tokens.contains(instrument) || foldedJoined.contains(" " + instrument + " ") {
        return true
    }
    let nameKey = normalizeMerchant(position.name)
    if !nameKey.isEmpty, foldedJoined.contains(" " + nameKey + " ") { return true }
    let nameTokens = nameKey.split(separator: " ").map(String.init).filter { $0.count >= 3 && !positionStopWords.contains($0) }
    for token in nameTokens where tokens.contains(token) { return true }
    return false
}

/// Busca qué posición abierta de la cartera se nombra en la pregunta (gana la coincidencia más larga).
func extractPositionQuery(tokens: [String], joined: String, portfolio: Portfolio?) -> String? {
    guard let portfolio else { return nil }
    let open = positions(from: portfolio.transactions)
    var best: (score: Int, instrument: String)?
    for pos in open {
        let instrument = normalizeMerchant(pos.instrument)
        let nameKey = normalizeMerchant(pos.name)
        var score = 0
        if !instrument.isEmpty, tokens.contains(instrument) { score = max(score, 100 + instrument.count) }
        if !nameKey.isEmpty, foldedJoinedContains(joined, nameKey) { score = max(score, 80 + nameKey.count) }
        let nameTokens = nameKey.split(separator: " ").map(String.init).filter { $0.count >= 3 && !positionStopWords.contains($0) }
        let hits = nameTokens.filter { tokens.contains($0) }
        if !hits.isEmpty {
            let hitLen = hits.reduce(0) { $0 + $1.count }
            score = max(score, 20 * hits.count + hitLen)
        }
        if score > (best?.score ?? 0) { best = (score, pos.instrument) }
    }
    return best?.instrument
}

private func foldedJoinedContains(_ joined: String, _ needle: String) -> Bool {
    !needle.isEmpty && joined.contains(" " + needle + " ")
}

/// Palabras que nunca se toman como nombre de comercio cuando van detrás de «en …».
private let nonMerchantTargets: Set<String> = [
    "total", "general", "mes", "este", "pasado", "anterior", "hoy", "ayer", "semana", "ano", "cuenta", "cuentas",
    "banco", "bancos", "revolut", "imagin", "caixabank", "caixa", "trade", "republic", "traderepublic",
    "inversiones", "inversion", "cartera", "bolsa", "acciones", "fondos", "cripto", "presupuesto", "presupuestos",
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "setiembre",
    "octubre", "noviembre", "diciembre",
]

private let trailingTimePhrases = [
    "este mes", "el mes pasado", "el mes anterior", "mes pasado", "mes anterior", "esta semana", "este ano",
    "hoy", "ayer",
    "en enero", "en febrero", "en marzo", "en abril", "en mayo", "en junio", "en julio", "en agosto",
    "en septiembre", "en setiembre", "en octubre", "en noviembre", "en diciembre",
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "setiembre",
    "octubre", "noviembre", "diciembre",
]

/// Busca un comercio conocido del libro o uno nombrado explícitamente tras «en …» en una pregunta de gasto.
private func extractMerchant(rawQuestion: String, joined: String, tokens: [String], state: LedgerState,
                             category: SpendingCategory?, bank: BankID?) -> String? {
    // 1. Coincidencia con un comercio ya existente en los pagos del libro (gana la más larga).
    var seenKeys = Set<String>()
    var known: [(key: String, display: String)] = []
    for m in state.movements where m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending {
        for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
            let key = normalizeMerchant(raw)
            guard key.count >= 3, !nonMerchantTargets.contains(key), seenKeys.insert(key).inserted else { continue }
            known.append((key, raw))
        }
    }
    var bestKnown: (length: Int, display: String)?
    for item in known {
        if joined.contains(" " + item.key + " ") {
            if item.key.count > (bestKnown?.length ?? 0) { bestKnown = (item.key.count, item.display) }
            continue
        }
        // También el primer nombre de marca si tiene 4+ letras («Mercadona» casa con «Mercadona Torrejón»).
        if let first = item.key.split(separator: " ").first.map(String.init),
           first.count >= 4, !nonMerchantTargets.contains(first), tokens.contains(first) {
            if first.count > (bestKnown?.length ?? 0) { bestKnown = (first.count, String(item.display.split(separator: " ").first ?? Substring(item.display))) }
        }
    }
    if let bestKnown { return bestKnown.display }

    // 2. Si no está en el libro (0 pagos todavía), extrae lo que viene tras «en …» (si no es banco, mes ni categoría).
    guard category == nil else { return nil }
    let cleaned = rawQuestion
        .replacingOccurrences(of: "¿", with: " ")
        .replacingOccurrences(of: "?", with: " ")
        .replacingOccurrences(of: "¡", with: " ")
        .replacingOccurrences(of: "!", with: " ")
    let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
    let foldedParts = parts.map { foldedQuery($0).trimmingCharacters(in: CharacterSet.punctuationCharacters) }
    let enIndices = foldedParts.indices.filter { foldedParts[$0] == "en" }.reversed()
    for enIndex in enIndices where enIndex + 1 < parts.count {
        var candidateParts: [String] = []
        for idx in (enIndex + 1)..<parts.count {
            let fp = foldedParts[idx]
            if fp == "en" { break }
            candidateParts.append(parts[idx])
        }
        guard !candidateParts.isEmpty else { continue }
        if let last = candidateParts.last {
            candidateParts[candidateParts.count - 1] = last.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        }
        var candidate = candidateParts.filter { !$0.isEmpty }.joined(separator: " ")
        // Quita años sueltos y coletillas de tiempo al final («Mercadona este mes» -> «Mercadona»).
        var changed = true
        while changed {
            changed = false
            let low = foldedQuery(candidate)
            if low.isEmpty { break }
            // Quita «de 2025» o «2025» al final.
            let words = candidate.split(separator: " ")
            if let lastW = words.last, lastW.count == 4, lastW.allSatisfy({ $0.isASCII && $0.isNumber }) {
                candidate = words.dropLast().joined(separator: " ")
                if foldedQuery(candidate).hasSuffix(" de") {
                    candidate = candidate.split(separator: " ").dropLast().joined(separator: " ")
                }
                changed = true
                continue
            }
            for suffix in trailingTimePhrases {
                if low == suffix { candidate = ""; break }
                if low.hasSuffix(" " + suffix) {
                    let dropCount = suffix.split(separator: " ").count
                    if words.count > dropCount {
                        candidate = words.dropLast(dropCount).joined(separator: " ")
                        changed = true
                        break
                    }
                }
            }
        }
        let key = normalizeMerchant(candidate)
        guard key.count >= 2, key.count <= 40, !nonMerchantTargets.contains(key) else { continue }
        if let bank, key == normalizeMerchant(bank.displayName) { continue }
        if extractCategory(joined: " " + key + " ") != nil { continue }
        let keyTokens = key.split(separator: " ").map(String.init)
        if keyTokens.allSatisfy({ nonMerchantTargets.contains($0) || ["que", "el", "la", "los", "las", "un", "una", "mi", "mis"].contains($0) }) {
            continue
        }
        return candidate
    }
    return nil
}

// MARK: Enrutador determinista (sin modelo)

private let spendingCues = [
    "gastado", "gaste", "gastos", "gasto", "gastar", "llevo", "pagado", "pague", "pagos",
]

private let investmentCues = [
    "inversion", "inversiones", "cartera", "accion", "acciones", "bolsa", "etf", "etfs", "fondo", "fondos",
    "cripto", "criptomonedas", "bitcoin", "btc", "ethereum", "eth", "posicion", "posiciones", "cotizacion",
    "invertido", "inverti", "rentabilidad", "ganancia", "ganancias", "dividendos",
]

private let moverPhrases = [
    "mas ha subido", "mas subio", "mas han subido", "subido mas", "mas ha bajado", "mas bajo",
    "mas han bajado", "bajado mas", "mejor ha ido", "peor ha ido",
]

private let recapPhrases = [
    "que ha pasado", "que paso", "desde ayer", "resumen de hoy", "resumen diario", "mi resumen",
    "ponme al dia", "al dia", "novedades", "que hay de nuevo", "cuentame el resumen",
]

private let transferPhrases = [
    "traspaso", "traspasos", "entre mis cuentas", "entre cuentas", "entre tus cuentas",
    "transferencias propias", "transferencia propia", "movido dinero", "dinero movido", "movi dinero",
]

private let budgetCues = [
    "presupuesto", "presupuestos", "limite", "limites",
]

private let budgetPhrases = [
    "me he pasado", "me paso", "como voy de presupuesto", "cuanto me queda de presupuesto",
]

private let freeMoneyPhrases = [
    "dinero libre", "libre este mes", "libre hasta fin de mes", "cuanto puedo gastar", "puedo gastar",
    "me sobra", "sobra hasta fin de mes", "margen libre", "libre al dia", "gastar al dia",
    "disponible hasta fin de mes", "cuanto me queda para gastar", "me queda libre", "queda libre",
]

private let upcomingPhrases = [
    "proximos cobros", "proximo cobro", "que viene", "lo que viene", "que cobros", "cobros pendientes",
    "cobros esta semana", "cobros este mes", "recibos pendientes", "que recibos", "faltar saldo", "falta saldo",
    "quedo corto", "quedare corto", "me quedo corto", "me llega para", "me da para", "llega el saldo",
    "bajo del minimo", "baja del minimo", "colchon", "cuando me cobran", "que tengo que pagar",
    "tengo que pagar", "van a cobrar", "me cobran", "calendario de cobros",
]

private let subscriptionCues = [
    "suscripcion", "suscripciones", "cuotas",
]

private let subscriptionPhrases = [
    "pagos fijos", "gastos fijos", "servicios fijos", "proximo cobro de suscripcion",
]

private let incomeCues = [
    "ingreso", "ingresos", "ingresado", "nomina", "sueldo", "cobrado", "cobre", "recibido",
]

private let incomePhrases = [
    "ha entrado", "han entrado", "entro", "entraron", "dinero entra", "entra en", "me han pagado", "me pagaron",
]

private let biggestPaymentPhrases = [
    "pago mas grande", "pagos mas grandes", "pagos grandes", "mayor pago", "mayores pagos",
    "gasto mas grande", "gastos mas grandes", "gastos grandes", "mayor gasto", "mayores gastos",
    "mas caro", "mas caros", "mas cara", "mas caras", "en que he gastado mas", "donde he gastado mas",
    "top pagos", "top gastos",
]

private let balanceCues = [
    "saldo", "saldos", "dinero", "cuentas", "cuenta", "total",
]

private let balancePhrases = [
    "cuanto tengo", "cuanto me queda", "cuanto queda", "cuanto hay", "como estan mis cuentas", "como van mis cuentas",
]

/// Traduce la pregunta del dueño a una intención conocida sin usar ningún modelo.
public func routeAssistantQuestion(_ question: String, state: LedgerState, portfolio: Portfolio?,
                                   now: Date, calendar: Calendar) -> AssistantIntent {
    let trimmed = withoutFormatCharacters(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .unknown }

    let rawFolded = foldedQuery(trimmed)
    let tokens = rawFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return .unknown }
    let joined = " " + tokens.joined(separator: " ") + " "

    let positionQuery = extractPositionQuery(tokens: tokens, joined: joined, portfolio: portfolio)

    // 0. Consejo de inversión: SIEMPRE primero (A3).
    if isAdviceRequest(trimmed, portfolio: portfolio) {
        return .adviceRequest(positionQuery: positionQuery)
    }

    let bank = extractBank(tokens: tokens, joined: joined)
    let month = extractMonth(tokens: tokens, joined: joined, rawFolded: rawFolded, now: now, calendar: calendar)
    let category = extractCategory(joined: joined)
    let hasSpendingCue = tokens.contains { spendingCues.contains($0) }

    // 1. Resumen («¿qué ha pasado desde ayer?»).
    if recapPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .briefingRecap
    }

    // 2. Inversiones explícitas (cartera, subidas/bajadas).
    let wantsMovers = moverPhrases.contains { joined.contains(" " + $0 + " ") }
    let hasInvCue = tokens.contains { investmentCues.contains($0) }
    if wantsMovers && (hasInvCue || positionQuery != nil || !hasSpendingCue) {
        return .investments(positionQuery: nil, moversOnly: true)
    }
    if hasInvCue {
        return .investments(positionQuery: positionQuery, moversOnly: false)
    }

    // 3. Traspasos propios.
    if transferPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .ownTransfers(month: month)
    }

    // 4. Presupuestos.
    if tokens.contains(where: { budgetCues.contains($0) }) || budgetPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .budgets(category: category)
    }

    // 5. Dinero libre.
    if freeMoneyPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .freeMoney
    }

    // 6. Próximos cobros y faltas de saldo.
    if upcomingPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .upcomingCharges(bank: bank)
    }

    // 7. Suscripciones (salvo que pregunte explícitamente cuánto gastó en la categoría «Suscripciones»).
    let asksSubSpending = category == .suscripciones && (hasSpendingCue || month != .current)
    if !asksSubSpending,
       tokens.contains(where: { subscriptionCues.contains($0) }) || subscriptionPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .subscriptions
    }

    // 8. Ingresos.
    if tokens.contains(where: { incomeCues.contains($0) }) || incomePhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .income(month: month)
    }

    // 9. Mayores pagos.
    if biggestPaymentPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .biggestPayments(month: month)
    }

    // 10. Gastos (mes, categoría o comercio).
    let merchant = extractMerchant(rawQuestion: trimmed, joined: joined, tokens: tokens, state: state,
                                   category: category, bank: bank)
    if hasSpendingCue {
        // «¿cuánto llevo en Mercadona?» -> comercio; «¿cuánto llevo en Comer fuera?» -> categoría; si no, total del mes.
        return .spending(month: month, category: merchant == nil ? category : nil, merchant: merchant)
    }
    // Posición concreta de la cartera («¿cómo va Apple?», «¿cuánto vale Apple?», «¿cuánto tengo en Apple?»).
    if let positionQuery {
        return .investments(positionQuery: positionQuery, moversOnly: false)
    }
    if let merchant, joined.contains(" cuanto ") || joined.contains(" pagos ") {
        return .spending(month: month, category: nil, merchant: merchant)
    }
    if let category, joined.contains(" cuanto ") || month != .current {
        return .spending(month: month, category: category, merchant: nil)
    }

    // 11. Saldos (todos o un banco).
    if tokens.contains(where: { balanceCues.contains($0) }) || balancePhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .balances(bank: bank)
    }
    if let bank, tokens.count <= 3 {
        return .balances(bank: bank)
    }

    return .unknown
}

// MARK: Contrato con el modelo del dispositivo (A2, A6, J21(d))

/// Instrucciones al modelo del dispositivo: solo clasifica la pregunta en una intención y sus parámetros. Nunca escribe texto
/// que vea el dueño ni recibe datos bancarios.
public let assistantRoutingInstructions =
    "Eres el clasificador de preguntas de Onyx. No respondas al usuario ni escribas explicaciones ni cifras. "
    + "Devuelve una sola línea con una intención exacta y, si aplica, parámetros clave=valor separados por espacios. "
    + "Intenciones: SALDO, GASTO, MAYORES_PAGOS, SUSCRIPCIONES, PROXIMOS_COBROS, PRESUPUESTOS, INGRESOS, TRASPASOS, "
    + "DINERO_LIBRE, INVERSIONES, RESUMEN, CONSEJO, DESCONOCIDO. "
    + "Parámetros opcionales: banco=rev|ima|tr, mes=actual|anterior|AAAA-MM, categoria=supermercado|comerFuera|transporte|"
    + "compras|casa|suscripciones|ocio|viajes|salud|personas|efectivo|sinCategoria, comercio=<texto>, posicion=<texto>, movers=si. "
    + "Si la pregunta pide consejo sobre qué comprar, vender, mantener o cuánto invertir, responde siempre CONSEJO."

/// Mensaje al modelo del dispositivo: lleva solo la pregunta y la fecha actual (sin saldos, importes ni movimientos).
public func assistantRoutingPrompt(question: String, now: Date, calendar: Calendar) -> String {
    let year = calendar.component(.year, from: now)
    let month = calendar.component(.month, from: now)
    let mm = month < 10 ? "0\(month)" : "\(month)"
    let clean = withoutFormatCharacters(question).trimmingCharacters(in: .whitespacesAndNewlines)
    return "Mes actual: \(year)-\(mm)\nPregunta: \(clean)\nIntención:"
}

/// Lee la línea que devuelve el modelo del dispositivo y valida cada parámetro. Si la pregunta pide consejo, devuelve siempre
/// `.adviceRequest` diga lo que diga el modelo; si la respuesta del modelo no se entiende o inventa texto que no estaba en la
/// pregunta, devuelve nil para usar el enrutador determinista.
public func parseAssistantModelRoute(_ response: String, originalQuestion: String, portfolio: Portfolio?,
                                     now: Date, calendar: Calendar) -> AssistantIntent? {
    let originalFolded = foldedQuery(originalQuestion)
    let originalTokens = originalFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let originalJoined = " " + originalTokens.joined(separator: " ") + " "

    // Barrera incondicional: el modelo nunca puede saltarse la negativa a dar consejos.
    if isAdviceRequest(originalQuestion, portfolio: portfolio) {
        let pos = extractPositionQuery(tokens: originalTokens, joined: originalJoined, portfolio: portfolio)
        return .adviceRequest(positionQuery: pos)
    }

    guard let firstLine = response.split(whereSeparator: \.isNewline)
        .map({ $0.trimmingCharacters(in: .whitespaces) })
        .first(where: { !$0.isEmpty }) else { return nil }

    // Acepta parámetros con comillas («comercio="El Corte Inglés"») o sin ellas.
    let parts = tokenizeModelLine(firstLine)
    guard let rawCommand = parts.first else { return nil }
    let command = rawCommand.uppercased()

    var bank: BankID?
    var month: AssistantMonth = .current
    var category: SpendingCategory?
    var merchant: String?
    var position: String?
    var moversOnly = false

    for token in parts.dropFirst() {
        guard let eq = token.firstIndex(of: "=") else { return nil }
        let key = token[..<eq].lowercased()
        let value = String(token[token.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 60 else { return nil }
        switch key {
        case "banco":
            guard let parsed = BankID(rawValue: value.lowercased()) else { return nil }
            bank = parsed
        case "mes":
            guard let parsed = parseModelMonth(value) else { return nil }
            month = parsed
        case "categoria":
            guard let parsed = SpendingCategory(rawValue: value) else { return nil }
            category = parsed
        case "comercio":
            // Seguridad (J21(d)): ningún texto inventado por el modelo llega a la pantalla; debe aparecer en la pregunta.
            let norm = normalizeMerchant(value)
            guard !norm.isEmpty, foldedQuery(originalQuestion).contains(norm) || originalJoined.contains(" " + norm + " ") else {
                return nil
            }
            merchant = value
        case "posicion":
            let norm = normalizeMerchant(value)
            guard !norm.isEmpty else { return nil }
            let inQuestion = foldedQuery(originalQuestion).contains(norm) || originalJoined.contains(" " + norm + " ")
            let matched = portfolio.flatMap { p in
                positions(from: p.transactions).first {
                    normalizeMerchant($0.instrument) == norm || normalizeMerchant($0.name) == norm
                }?.instrument
            }
            guard inQuestion || matched != nil else { return nil }
            position = matched ?? value
        case "movers":
            let low = foldedQuery(value)
            guard low == "si" || low == "no" else { return nil }
            moversOnly = (low == "si")
        default:
            return nil
        }
    }

    switch command {
    case "SALDO":
        return .balances(bank: bank)
    case "GASTO":
        return .spending(month: month, category: merchant == nil ? category : nil, merchant: merchant)
    case "MAYORES_PAGOS":
        return .biggestPayments(month: month)
    case "SUSCRIPCIONES":
        return .subscriptions
    case "PROXIMOS_COBROS":
        return .upcomingCharges(bank: bank)
    case "PRESUPUESTOS":
        return .budgets(category: category)
    case "INGRESOS":
        return .income(month: month)
    case "TRASPASOS":
        return .ownTransfers(month: month)
    case "DINERO_LIBRE":
        return .freeMoney
    case "INVERSIONES":
        return .investments(positionQuery: position, moversOnly: moversOnly)
    case "RESUMEN":
        return .briefingRecap
    case "CONSEJO":
        return .adviceRequest(positionQuery: position)
    case "DESCONOCIDO":
        return .unknown
    default:
        return nil
    }
}

private func parseModelMonth(_ raw: String) -> AssistantMonth? {
    let low = foldedQuery(raw)
    if low == "actual" { return .current }
    if low == "anterior" { return .previous }
    let pieces = low.split(separator: "-")
    guard pieces.count == 2, pieces[0].count == 4, (1...2).contains(pieces[1].count),
          pieces[0].allSatisfy({ $0.isASCII && $0.isNumber }),
          pieces[1].allSatisfy({ $0.isASCII && $0.isNumber }),
          let y = Int(pieces[0]), let m = Int(pieces[1]),
          (2000...2100).contains(y), (1...12).contains(m) else { return nil }
    return .specific(year: y, month: m)
}

private func tokenizeModelLine(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var inQuotes = false
    for ch in line {
        if ch == "\"" {
            inQuotes.toggle()
        } else if ch.isWhitespace && !inQuotes {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(ch)
        }
    }
    if inQuotes { return [] }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
