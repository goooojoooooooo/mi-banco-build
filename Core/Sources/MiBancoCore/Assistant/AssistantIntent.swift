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
    case spending(month: AssistantMonth, category: SpendingCategory?, merchant: String?, bank: BankID? = nil)
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

// MARK: Normalización, NFKD y confusables

/// Descompone caracteres de compatibilidad (ancho completo «ｖｅｎｄｏ», matemáticos «𝐯𝐞𝐧𝐝𝐨»...) y quita `\p{Cf}`.
private func compatNormalized(_ text: String) -> String {
    withoutFormatCharacters(text).decomposedStringWithCompatibilityMapping
}

private func foldedQuery(_ text: String) -> String {
    compatNormalized(text)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .lowercased()
}

/// Cambia letras parecidas de otros alfabetos o latín extendido (cirílico «е»/«а», griego «υ», «đ», «ø», «ł»...) por su letra
/// ASCII para detectar trucos de escritura en peticiones de consejo (J22).
private let confusableMap: [Character: String] = [
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ї": "i", "ј": "j", "ѕ": "s", "ԁ": "d",
    "к": "k", "м": "m", "т": "t", "н": "h", "в": "b",
    "α": "a", "ε": "e", "ο": "o", "ρ": "p", "ν": "v", "υ": "u", "ι": "i", "κ": "k", "τ": "t", "χ": "x",
    "đ": "d", "ð": "d", "ø": "o", "ł": "l", "ı": "i", "ß": "ss", "þ": "p",
]

private func foldConfusables(_ text: String) -> String {
    var out = ""
    for ch in compatNormalized(text).lowercased() {
        if let mapped = confusableMap[ch] {
            out += mapped
        } else {
            out.append(ch)
        }
    }
    return out
}

/// Lecturas del texto normalizado con NFKD más las lecturas tras doblar confusables.
private func allQuestionReadings(_ text: String) -> [[String]] {
    let compat = compatNormalized(text)
    var readings = wordReadings(compat)
    let conf = foldConfusables(text)
    for r in wordReadings(conf) where !readings.contains(r) { readings.append(r) }
    return readings
}

private func isLetterScalar(_ scalar: UnicodeScalar) -> Bool {
    let cat = scalar.properties.generalCategory
    return cat == .uppercaseLetter || cat == .lowercaseLetter || cat == .titlecaseLetter
        || cat == .modifierLetter || cat == .otherLetter
}

/// true si el escalar pertenece al alfabeto latino (ASCII, Latin-1, Latin Extended-A/B o Latin Extended Additional).
/// Así «Ørsted», «Straße» y «Møller» cuentan como latinos, mientras cirílico/griego/etc. cuentan como otra escritura.
private func isLatinScriptLetter(_ scalar: UnicodeScalar) -> Bool {
    guard isLetterScalar(scalar) else { return false }
    let v = scalar.value
    return v <= 0x024F || (0x1E00...0x1EFF).contains(v)
}

/// true si una misma palabra mezcla letras latinas con letras de otra escritura (p. ej. «vеndo» con cirílico o «bυy» con griego).
private func hasCrossScriptConfusableWord(_ text: String) -> Bool {
    let tokens = compatNormalized(text).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    for token in tokens {
        var hasLatin = false
        var hasNonLatin = false
        for scalar in token.unicodeScalars where isLetterScalar(scalar) {
            if isLatinScriptLetter(scalar) { hasLatin = true } else { hasNonLatin = true }
        }
        if hasLatin && hasNonLatin { return true }
    }
    return false
}

/// true si el texto contiene alguna letra fuera de la escritura latina (cirílico, griego, CJK...).
private func hasNonLatinScriptLetter(_ text: String) -> Bool {
    compatNormalized(text).unicodeScalars.contains { isLetterScalar($0) && !isLatinScriptLetter($0) }
}

// MARK: Detector de peticiones de consejo de inversión (A3, J7, J15, J21(c), J22)

/// Palabras enteras que siempre marcan una petición de consejo o de operación.
private let unconditionalAdviceWords: Set<String> = [
    "conviene", "convienen", "quedate", "quedarme", "tendrias", "should",
    "buy", "buys", "buying", "sell", "sells", "selling", "hold", "holds", "stay",
]

/// Prefijos que siempre marcan una petición de consejo (incluye inglés `invest*` de J7, gerundios y clíticos).
private let unconditionalAdvicePrefixes = [
    "recomiend", "recomend", "aconsej", "suger", "sugier", "asesor", "aprovech",
    "diversific", "reequilibr", "rebalanc", "promedi", "deshaz", "deshag", "deshac",
    "convendr", "acumul", "refuerz", "reforz", "aguant", "manten", "mantien",
    "recommend", "purchase",
]

/// Frases que siempre marcan una petición de consejo.
private let unconditionalAdvicePhrases = [
    "buen momento", "es momento de", "el momento de", "es hora de", "buena idea", "vale la pena", "merece la pena",
    "yo que tu", "yo de ti", "habria que", "tendrias que",
    "toma beneficios", "tomo beneficios", "tomar beneficios", "tomamos beneficios",
    "recoge beneficios", "recojo beneficios", "recoger beneficios",
    "toma ganancias", "tomo ganancias", "tomar ganancias", "recojo ganancias", "recoger ganancias",
    "sal de", "salir de bolsa", "salgo de bolsa", "entrar en bolsa", "entro en bolsa",
    "meter dinero en", "mete dinero en", "meto dinero en",
    "pon dinero en", "pongo dinero en", "poner dinero en",
    "donde meto", "donde meter", "donde pongo mi dinero", "donde poner mi dinero",
    "en que pongo", "en que poner", "donde invierto", "en que invierto", "donde invertir", "en que invertir",
    "sacar rentabilidad",
    "take profit", "take profits", "get out", "stay put", "should i", "good time to",
    "worth buying", "worth selling", "worth investing", "how much to invest", "what to invest",
    "mejor esperar", "espera a que", "esperar a que",
]

/// Formas pasadas que solo describen hechos ya ocurridos (J7).
private let pastDescribingTradeWords: Set<String> = [
    "comprado", "comprada", "comprados", "compradas", "compraste",
    "vendido", "vendida", "vendidos", "vendidas", "vendiste", "vendi",
    "invertido", "invertida", "invertidos", "invertidas", "invertiste", "inverti",
]

/// Determinantes y palabras de contexto de gasto que convierten «compra(s)»/«venta(s)» en sustantivo factual.
private let factualNounPredecessors: Set<String> = [
    "en", "de", "del", "para", "por", "sobre", "con", "sin",
    "categoria", "presupuesto", "presupuestos", "gasto", "gastos", "gaste", "llevo",
    "cuanto", "cuanta", "cuantos", "cuantas",
    "tu", "tus", "la", "las", "una", "unas", "esa", "esas", "esta", "estas", "mi", "mis", "su", "sus",
    "cada", "ultima", "ultimas", "primera", "primeras", "mayor", "mayores", "gran", "grandes",
    "hice", "hechas",
]

/// Marcadores condicionales: piden consejo si acompañan contexto de inversión o verbo de espera/estrategia.
private let conditionalAdviceWords: Set<String> = [
    "deberia", "deberias", "deberiamos", "debo", "debes", "debemos", "debiera", "tendria", "podria", "podrias",
    "mejor", "considera", "considerar", "plantea", "plantear", "planteo", "evita", "evitar", "procura", "intenta",
    "opinas", "opinar", "wait", "avoid", "consider", "better",
]

private let conditionalAdvicePhrases = [
    "tengo que", "tienes que", "hay que", "crees que", "piensas que", "que me dices de",
]

/// Palabras cotidianas que empiezan por «manten» o «acumul» y no piden consejo.
private let nonAdvicePrefixExceptions: Set<String> = [
    "mantenimiento", "mantenimientos", "acumulado", "acumulada", "acumulados", "acumuladas",
]

/// Verbos de acción sobre cartera/posiciones: en contexto de inversión (cartera, acciones, Apple...) son petición de consejo.
private let portfolioActionWords: Set<String> = [
    "meto", "meter", "mete", "metemos", "meten", "meteria", "metiendo",
    "pongo", "poner", "pone", "ponemos", "ponen", "pondria", "poniendo",
    "salgo", "salir", "sal", "salimos", "salen", "saldria", "saliendo",
    "entro", "entrar", "entra", "entramos", "entran", "entraria", "entrando",
    "quedo", "quedar", "quedamos", "quedaria",
    "cambio", "cambiar", "cambia", "cambiamos", "cambiaria", "cambiando",
    "aporto", "aportar", "aporta", "aportamos", "aportaria", "aportando",
    "elijo", "elegir", "elige", "elegiria", "escojo", "escoger",
    "liquido", "liquidar", "liquida", "liquidamos", "liquidaria", "liquidando",
    "saco", "sacar", "saca", "sacaria", "sacando",
    "retiro", "retirar", "retira", "retiramos", "retiraria", "retirando",
    "cierro", "cerrar", "cierra", "cerramos", "cerraria", "cerrando",
    "toco", "tocar", "toques", "toque",
]

/// Frases de rendimiento pasado/actual con «mejor» que son factuales, nunca consejos.
private let factualMejorPhrases = [
    "mejor ha ido", "mejor han ido", "ha ido mejor", "han ido mejor", "fue mejor", "fueron mejor",
    "va mejor", "van mejor",
]

/// Frases de predicción de precios (consejo cuando acompañan contexto de inversión).
private let futurePricePhrases = [
    "va a subir", "va a bajar", "van a subir", "van a bajar", "seguira subiendo", "seguira bajando",
]

private let futurePriceWords: Set<String> = [
    "subira", "subiran", "bajara", "bajaran", "subiria", "bajaria",
]

/// Vocabulario de inversión para evaluar marcadores condicionales (sin bloquear por sí solo preguntas factuales).
private let investmentContextPrefixes = [
    "invers", "invert", "inviert", "invirt", "accion", "cartera", "fondo", "bolsa", "posicion", "exposicion",
    "beneficio", "dividendo", "etf", "cripto", "bitcoin", "ethereum", "broker", "stock", "share", "fund",
    "portfolio", "crypto", "asset", "bono", "bond", "renta", "rentabil", "ibex", "nasdaq", "deposito", "tesoro",
]

private let investmentContextWords: Set<String> = [
    "mercado", "mercados", "oro", "gold", "btc", "eth", "msci", "sp500", "valores",
]

private let billOrPaymentWords: Set<String> = [
    "pagar", "cobro", "cobros", "recibo", "recibos", "factura", "facturas", "nomina", "ingreso", "ingresos",
    "dividendo", "dividendos",
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
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if hasCrossScriptConfusableWord(trimmed) { return true }

    // Conserva tildes del original (NFC) para distinguir el pretérito «compré» del subjuntivo «compre».
    let rawAccentedTokens = Set(
        withoutFormatCharacters(question).precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    )
    let hasPastCompre = rawAccentedTokens.contains("compré")

    for list in allQuestionReadings(trimmed) {
        let joined = " " + list.joined(separator: " ") + " "
        let invContext = hasInvestmentContext(list, portfolio: portfolio)

        // 1. Palabras y prefijos incondicionales (incluye inglés `invest*` de J7).
        for (i, word) in list.enumerated() {
            if unconditionalAdviceWords.contains(word) { return true }
            if !nonAdvicePrefixExceptions.contains(word),
               unconditionalAdvicePrefixes.contains(where: { word.hasPrefix($0) }) { return true }
            if word.hasPrefix("invest") && !word.hasPrefix("investig") { return true }

            // «venta»/«ventas» sin determinante ni «venta(s) de/del» al inicio (R1).
            if word == "venta" || word == "ventas" {
                if isFactualTradeNoun(word, at: i, in: list) { continue }
                return true
            }

            // Raíces de comprar / vender / invertir (cubren gerundios y clíticos sin atrapar «comprobar»/«comprometido»/«comprender»).
            if !pastDescribingTradeWords.contains(word) {
                if word.hasPrefix("vend") { return true }
                if word.hasPrefix("invert") || word.hasPrefix("inviert") || word.hasPrefix("invirt") { return true }
                let isComprarForm = word == "compro" || word.hasPrefix("compra")
                    || (word.hasPrefix("compre") && !word.hasPrefix("comprend") && !word.hasPrefix("compresi")
                        && word != "compresa" && word != "compresas")
                if isComprarForm {
                    if word == "compra" || word == "compras" {
                        if isFactualTradeNoun(word, at: i, in: list) { continue }
                        return true
                    }
                    if word == "compre" {
                        // «¿Qué compré en Mercadona?» / «¿Cuánto compré en Apple Store?» lleva tilde en el original.
                        if hasPastCompre { continue }
                        let pastShop = list.contains("cuanto") && list.contains("en") && !invContext
                        if pastShop { continue }
                        return true
                    }
                    if word == "compramos" && !invContext && (list.contains("cuanto") || list.contains("que")) {
                        continue
                    }
                    return true
                }
            }
        }

        // 2. Frases incondicionales.
        if unconditionalAdvicePhrases.contains(where: { joined.contains(" " + $0 + " ") }) { return true }

        // 3. Predicciones de mercado y «qué hago con …» solo en contexto de inversión o dinero/ahorros.
        if invContext {
            if list.contains(where: { futurePriceWords.contains($0) }) { return true }
            if futurePricePhrases.contains(where: { joined.contains(" " + $0 + " ") }) { return true }
            if list.contains(where: { portfolioActionWords.contains($0) }) { return true }
            if list.contains(where: { $0.hasPrefix("reduc") }) { return true }
            // «esperar»/«espera» en inversiones es consejo, salvo «espero el cobro/dividendo» (hecho esperado).
            let expectsScheduled = list.contains("espero") && list.contains { billOrPaymentWords.contains($0) }
            if !expectsScheduled && list.contains(where: { $0.hasPrefix("esper") || $0.hasPrefix("aguard") }) {
                return true
            }
        }

        let asksWhatToDo = joined.contains(" que hago con ") || joined.contains(" que haria ") || joined.contains(" que harias ")
        if asksWhatToDo && (invContext || list.contains("dinero") || list.contains("ahorro") || list.contains("ahorros")) {
            return true
        }

        // 4. Marcadores condicionales + contexto de inversión o espera de mercado.
        let isFactualMejor = factualMejorPhrases.contains { joined.contains(" " + $0 + " ") }
            && !list.contains(where: { portfolioActionWords.contains($0) })
        let hasConditionalWord = list.contains { w in
            if w == "mejor" && isFactualMejor { return false }
            return conditionalAdviceWords.contains(w)
        }
        let hasConditional = hasConditionalWord || conditionalAdvicePhrases.contains { joined.contains(" " + $0 + " ") }
        if hasConditional {
            if invContext { return true }
            let hasMarketHesitation = list.contains { w in
                w.hasPrefix("esper") || w.hasPrefix("aguard") || w.hasPrefix("reduc") || w.hasPrefix("apost")
            }
            let expectsBill = list.contains { billOrPaymentWords.contains($0) }
            if hasMarketHesitation && !expectsBill { return true }
        }
    }
    return false
}

private func isFactualTradeNoun(_ word: String, at i: Int, in list: [String]) -> Bool {
    if i > 0, factualNounPredecessors.contains(list[i - 1]) { return true }
    // J22: al inicio de frase solo «venta(s) de/del» y plural «compras de/del/en» («Compra de nuevo» es imperativo).
    if i == 0, i + 1 < list.count {
        if (word == "venta" || word == "ventas") && ["de", "del"].contains(list[i + 1]) { return true }
        if word == "compras" && ["de", "del", "en"].contains(list[i + 1]) { return true }
    }
    if word == "compras", i > 0, list[i - 1] == "que",
       i + 1 < list.count, ["hice", "he", "tengo", "hubo", "fueron", "pague", "hay"].contains(list[i + 1]) {
        return true
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
    let digits = rawFolded.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { $0.count == 4 }
    let explicitYear = digits.compactMap(Int.init).first { (2000...2100).contains($0) }
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

private let categoryKeywordWords: Set<String> = Set(
    categoryMatchers.flatMap { $0.phrases.flatMap { $0.split(separator: " ").map(String.init) } }
)

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
    "banco", "bancos", "bank", "group", "holding", "holdings",
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
    "total", "general", "mes", "meses", "este", "pasado", "anterior", "ultimo", "ultimos", "hoy", "ayer",
    "semana", "semanas", "dia", "dias", "ano", "anos", "va", "cuenta", "cuentas", "tarjeta", "tarjetas",
    "banco", "bancos", "revolut", "imagin", "caixabank", "caixa", "trade", "republic", "traderepublic",
    "inversiones", "inversion", "cartera", "bolsa", "acciones", "fondos", "cripto", "presupuesto", "presupuestos",
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "setiembre",
    "octubre", "noviembre", "diciembre",
]

private let trailingTimePhrases = [
    "lo que va de mes", "el ultimo mes", "ultimo mes", "este mes", "el mes pasado", "el mes anterior",
    "mes pasado", "mes anterior", "esta semana", "este ano", "mi tarjeta", "la tarjeta", "hoy", "ayer",
    "en enero", "en febrero", "en marzo", "en abril", "en mayo", "en junio", "en julio", "en agosto",
    "en septiembre", "en setiembre", "en octubre", "en noviembre", "en diciembre",
    "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "setiembre",
    "octubre", "noviembre", "diciembre",
]

private let merchantFillerWords: Set<String> = [
    "que", "el", "la", "los", "las", "un", "una", "mi", "mis", "tu", "tus", "su", "sus",
    "lo", "de", "del", "en", "con", "por", "para", "sin", "al", "y", "o", "a",
]

/// Busca el texto exacto de una palabra de la pregunta cuya forma normalizada coincide con `target` (conserva mayúsculas).
private func originalWordMatching(_ target: String, in rawQuestion: String) -> String {
    let cleaned = rawQuestion.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    if let hit = cleaned.first(where: { normalizeMerchant($0) == target }) { return hit }
    return target.prefix(1).uppercased() + target.dropFirst()
}

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
        // Coincidencia exacta con todo el nombre del comercio (p. ej. «Restaurante Sol» sí gana a la categoría).
        if joined.contains(" " + item.key + " ") {
            if !categoryKeywordWords.contains(item.key) || item.key.contains(" ") {
                if item.key.count > (bestKnown?.length ?? 0) { bestKnown = (item.key.count, item.display) }
            }
            continue
        }
        // Primer nombre de marca si tiene 4+ letras, nunca si es palabra de categoría («restaurante», «farmacia», «casa»...).
        if category == nil,
           let first = item.key.split(separator: " ").first.map(String.init),
           first.count >= 4, !nonMerchantTargets.contains(first), !categoryKeywordWords.contains(first),
           tokens.contains(first) {
            if first.count > (bestKnown?.length ?? 0) {
                bestKnown = (first.count, originalWordMatching(first, in: rawQuestion))
            }
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
        var candidate = candidateParts.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        // Quita años sueltos y coletillas de tiempo al final («Zara, el mes pasado» -> «Zara»).
        var changed = true
        while changed {
            changed = false
            candidate = candidate.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
            let low = foldedQuery(candidate)
            if low.isEmpty { break }
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
        candidate = candidate.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        let key = normalizeMerchant(candidate)
        guard key.count >= 2, key.count <= 40, !nonMerchantTargets.contains(key) else { continue }
        if let bank, key == normalizeMerchant(bank.displayName) { continue }
        if extractCategory(joined: " " + key + " ") != nil { continue }
        let keyTokens = key.split(separator: " ").map(String.init)
        if keyTokens.allSatisfy({ nonMerchantTargets.contains($0) || merchantFillerWords.contains($0) }) { continue }
        return candidate
    }
    return nil
}

// MARK: Enrutador determinista (sin modelo)

private let spendingCues = [
    "gastado", "gaste", "gastos", "gasto", "gastar", "llevo", "pagado", "pague", "pagos", "compre", "comprado", "compramos",
]

private let strongShopSpendingCues = [
    "gastado", "gaste", "gastos", "gasto", "gastar", "pagado", "pague", "pagos", "compre", "comprado", "compramos",
]

private let investmentCues = [
    "inversion", "inversiones", "cartera", "accion", "acciones", "bolsa", "etf", "etfs", "fondo", "fondos",
    "cripto", "criptomonedas", "bitcoin", "btc", "ethereum", "eth", "posicion", "posiciones", "cotizacion",
    "invertido", "inverti", "rentabilidad", "ganancia", "ganancias", "dividendos",
]

private let unconditionalMoverPhrases = [
    "mas ha subido", "mas subio", "mas han subido", "subido mas",
    "mas ha bajado", "mas han bajado", "bajado mas",
    "mejor ha ido", "mejor han ido", "ha ido mejor", "han ido mejor",
    "peor ha ido", "peor han ido", "ha ido peor", "han ido peor",
]

private let recapPhrases = [
    "que ha pasado", "que paso", "desde ayer", "resumen de hoy", "resumen diario", "mi resumen",
    "ponme al dia", "ponte al dia", "ponerme al dia", "novedades", "que hay de nuevo", "cuentame el resumen",
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
    "espero el cobro", "cobros espero",
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

private let explicitBalanceWords: Set<String> = ["saldo", "saldos"]

private let balancePhrases = [
    "cuanto tengo", "cuanto me queda", "cuanto queda", "cuanto hay", "como estan mis cuentas", "como van mis cuentas",
]

private func hasKnownShopMerchant(_ query: String, in state: LedgerState) -> Bool {
    let key = normalizeMerchant(query)
    guard !key.isEmpty else { return false }
    let qTokens = key.split(separator: " ").map(String.init)
    return state.movements.contains { m in
        guard m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending else { return false }
        return [m.merchant, m.bankMerchant].compactMap { $0 }.contains { raw in
            let mk = normalizeMerchant(raw)
            if mk == key { return true }
            let mt = mk.split(separator: " ").map(String.init)
            return qTokens.count <= mt.count && (0...(mt.count - qTokens.count)).contains { Array(mt[$0..<($0 + qTokens.count)]) == qTokens }
        }
    }
}

/// Traduce la pregunta del dueño a una intención conocida sin usar ningún modelo.
public func routeAssistantQuestion(_ question: String, state: LedgerState, portfolio: Portfolio?,
                                   now: Date, calendar: Calendar) -> AssistantIntent {
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
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
    let hasStrongShopCue = tokens.contains { strongShopSpendingCues.contains($0) }
    let hasAccentedBajo = withoutFormatCharacters(question).precomposedStringWithCanonicalMapping.lowercased().contains("bajó")

    // 1. Resumen («¿qué ha pasado desde ayer?»).
    if recapPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .briefingRecap
    }

    // 2. Inversiones explícitas (cartera, subidas/bajadas).
    let hasInvCue = tokens.contains { investmentCues.contains($0) }
    let hasUnconditionalMover = unconditionalMoverPhrases.contains { joined.contains(" " + $0 + " ") }
    let hasBajoMover = joined.contains(" mas bajo ") && (hasAccentedBajo || hasInvCue || positionQuery != nil)
    if (hasUnconditionalMover || hasBajoMover) && (hasInvCue || positionQuery != nil || !hasSpendingCue) {
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

    // 10. Saldo explícito («saldo», «saldos», o «cuánto tengo en <banco>») antes de posición suelta
    // (evita que acciones de «CaixaBank» pisen el saldo del banco).
    if tokens.contains(where: { explicitBalanceWords.contains($0) })
        || (bank != nil && balancePhrases.contains(where: { joined.contains(" " + $0 + " ") })) {
        return .balances(bank: bank)
    }

    // 11. Posición concreta de cartera cuando no hay un verbo de compra en tienda para un comercio del libro
    // («¿Cuánto llevo en MSCI World?», «¿Cuánto llevo ganado en Apple?», «¿Cómo va Apple?»).
    if let positionQuery {
        let matchedPositionName = portfolio.flatMap { p in
            positions(from: p.transactions).first { $0.instrument == positionQuery }?.name
        }
        let isGainQuery = tokens.contains("ganado") || tokens.contains("perdido")
        let isShopSpending = hasStrongShopCue && !isGainQuery
            && (matchedPositionName.map { hasKnownShopMerchant($0, in: state) } ?? false)
        if !isShopSpending {
            let isOnlyLlevoWithoutShop = tokens.contains("llevo")
                && !(matchedPositionName.map { hasKnownShopMerchant($0, in: state) } ?? false)
            if isGainQuery || !hasSpendingCue || isOnlyLlevoWithoutShop {
                return .investments(positionQuery: positionQuery, moversOnly: false)
            }
        }
    }

    // 12. Gastos (mes, categoría, comercio o banco).
    let merchant = extractMerchant(rawQuestion: trimmed, joined: joined, tokens: tokens, state: state,
                                   category: category, bank: bank)
    if hasSpendingCue {
        return .spending(month: month, category: merchant == nil ? category : nil, merchant: merchant,
                         bank: merchant == nil ? bank : nil)
    }
    if let merchant, joined.contains(" cuanto ") || joined.contains(" pagos ") {
        return .spending(month: month, category: nil, merchant: merchant, bank: nil)
    }
    if let category, joined.contains(" cuanto ") || month != .current {
        return .spending(month: month, category: category, merchant: nil, bank: bank)
    }

    // 13. Saldos (todos o un banco).
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

/// Comprueba que el valor propuesto por el modelo aparece como una secuencia de palabras enteras dentro de `originalQuestion`,
/// sin caracteres añadidos ni símbolos prohibidos, y devuelve el trozo original de la pregunta (nunca el texto crudo del modelo).
private func validatedSpanFromQuestion(_ modelValue: String, originalQuestion: String) -> String? {
    guard !hasNonLatinScriptLetter(modelValue),
          !modelValue.contains("€"), !modelValue.contains("%"), !modelValue.contains("$"),
          !modelValue.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
        return nil
    }
    let normValue = normalizeMerchant(modelValue)
    let valueTokens = normValue.split(separator: " ").map(String.init)
    guard normValue.count >= 2, !valueTokens.isEmpty,
          !valueTokens.allSatisfy({ nonMerchantTargets.contains($0) || merchantFillerWords.contains($0) }) else {
        return nil
    }
    // Comprueba que `modelValue` no trae palabras extra eliminadas por `normalizeMerchant` (como sufijos o basura),
    // respetando apóstrofos propios del nombre («McDonald's»).
    let withoutApostrophes = foldedQuery(modelValue)
        .replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: "\u{2019}", with: "")
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: "\u{00B4}", with: "")
    let rawWords = withoutApostrophes.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard rawWords == valueTokens else { return nil }

    // Extrae palabras originales de la pregunta y busca un tramo contiguo cuya forma normalizada coincida (también «H&M»/«Basic-Fit»).
    let qRaw = compatNormalized(originalQuestion)
        .replacingOccurrences(of: "¿", with: " ")
        .replacingOccurrences(of: "?", with: " ")
        .replacingOccurrences(of: "¡", with: " ")
        .replacingOccurrences(of: "!", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
        .filter { !$0.isEmpty }
    let maxSpan = min(valueTokens.count, qRaw.count)
    guard maxSpan >= 1 else { return nil }
    for spanLen in 1...maxSpan {
        for start in 0...(qRaw.count - spanLen) {
            let candidate = qRaw[start..<(start + spanLen)].joined(separator: " ")
            if normalizeMerchant(candidate) == normValue {
                return candidate.precomposedStringWithCanonicalMapping
            }
        }
    }
    return nil
}

/// Parámetros permitidos por cada comando del modelo (cualquier parámetro ajeno invalida la línea).
private let allowedParamsByCommand: [String: Set<String>] = [
    "SALDO": ["banco"],
    "GASTO": ["mes", "categoria", "comercio", "banco"],
    "MAYORES_PAGOS": ["mes"],
    "SUSCRIPCIONES": [],
    "PROXIMOS_COBROS": ["banco"],
    "PRESUPUESTOS": ["categoria"],
    "INGRESOS": ["mes"],
    "TRASPASOS": ["mes"],
    "DINERO_LIBRE": [],
    "INVERSIONES": ["posicion", "movers"],
    "RESUMEN": [],
    "CONSEJO": ["posicion"],
    "DESCONOCIDO": [],
]

/// Lee la línea que devuelve el modelo del dispositivo y valida estrictamente cada parámetro.
/// Si la pregunta pide consejo, devuelve siempre `.adviceRequest` diga lo que diga el modelo; si la respuesta del modelo no se
/// entiende, trae parámetros no permitidos o inventa texto ausente en la pregunta, devuelve nil para usar el enrutador determinista.
public func parseAssistantModelRoute(_ response: String, originalQuestion: String, portfolio: Portfolio?) -> AssistantIntent? {
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

    let parts = tokenizeModelLine(firstLine)
    guard let rawCommand = parts.first else { return nil }
    let command = rawCommand.uppercased()
    guard let allowedKeys = allowedParamsByCommand[command] else { return nil }

    var seenKeys = Set<String>()
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
        guard allowedKeys.contains(key), seenKeys.insert(key).inserted, !value.isEmpty, value.count <= 60 else { return nil }
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
            // Seguridad (J21(d)): nunca se muestra texto crudo del modelo; se extrae el trozo exacto de `originalQuestion`.
            guard let safeSpan = validatedSpanFromQuestion(value, originalQuestion: originalQuestion) else { return nil }
            merchant = safeSpan
        case "posicion":
            guard !hasNonLatinScriptLetter(value), !value.contains("€"), !value.contains("%") else { return nil }
            let norm = normalizeMerchant(value)
            guard !norm.isEmpty else { return nil }
            if let matched = portfolio.flatMap({ p in
                positions(from: p.transactions).first {
                    normalizeMerchant($0.instrument) == norm || normalizeMerchant($0.name) == norm
                }?.instrument
            }) {
                position = matched
            } else if let safeSpan = validatedSpanFromQuestion(value, originalQuestion: originalQuestion) {
                position = safeSpan
            } else {
                return nil
            }
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
        return .spending(month: month, category: merchant == nil ? category : nil, merchant: merchant,
                         bank: merchant == nil ? bank : nil)
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
