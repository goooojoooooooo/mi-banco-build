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
    case unsupportedPeriod
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

/// Cambia letras parecidas de otros alfabetos o latín extendido (cirílico «е»/«а», griego «υ», «đ», «ø», «ł», «ɇ», «ħ»...)
/// por su letra ASCII para detectar trucos de escritura en peticiones de consejo (J22).
private let confusableScalarMap: [UnicodeScalar: String] = [
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "у": "y", "і": "i", "ї": "i", "ј": "j", "ѕ": "s", "ԁ": "d",
    "к": "k", "м": "m", "т": "t", "н": "h", "в": "b",
    "α": "a", "ε": "e", "ο": "o", "ρ": "p", "ν": "v", "υ": "u", "ι": "i", "κ": "k", "τ": "t", "χ": "x",
    "đ": "d", "ð": "d", "ø": "o", "ł": "l", "ı": "i", "ȷ": "j", "ß": "ss", "þ": "p", "ſ": "s",
    "ɇ": "e", "ħ": "h", "ɑ": "a", "ɡ": "g", "ɩ": "i", "ʋ": "v", "ɒ": "a", "ə": "e", "ɛ": "e", "ɪ": "i",
    "ɔ": "o", "ʊ": "u", "ʌ": "a", "ɓ": "b", "ɗ": "d", "ƒ": "f", "ɠ": "g", "ƙ": "k", "ɱ": "m", "ɲ": "n",
    "ƥ": "p", "ɾ": "r", "ƭ": "t", "ƴ": "y", "ʐ": "z",
]

/// Letras latinas extendidas legítimas en nombres europeos (español, nórdicos, alemán, polaco, croata).
private let allowedNonASCIILatinBases: Set<UInt32> = [
    0x00DF, // ß
    0x00E6, // æ
    0x00F0, // ð
    0x00F8, // ø
    0x00FE, // þ
    0x0111, // đ
    0x0131, // ı
    0x0142, // ł
    0x0153, // œ
]

private func foldConfusables(_ text: String) -> String {
    var out = ""
    // Descompone primero en NFD para quitar diacríticos combinantes (p. ej. cirílico «е\u{0301}») antes de mapear escalares.
    let decomposed = compatNormalized(text).lowercased().decomposedStringWithCanonicalMapping
    for scalar in decomposed.unicodeScalars {
        let cat = scalar.properties.generalCategory
        if cat == .nonspacingMark || cat == .spacingMark || cat == .enclosingMark { continue }
        if let mapped = confusableScalarMap[scalar] {
            out += mapped
        } else {
            out.unicodeScalars.append(scalar)
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

/// true si una letra base (tras NFD y sin marcas) es una letra latina extendida inusual usada como confusable (p. ej. «ɇ», «ħ»).
private func isSuspiciousConfusableLetter(_ scalar: UnicodeScalar) -> Bool {
    guard isLetterScalar(scalar) else { return false }
    if scalar.value <= 0x007A { return false }
    if allowedNonASCIILatinBases.contains(scalar.value) { return false }
    return true
}

/// true si una misma palabra mezcla letras latinas con letras de otra escritura o confusables exóticos (p. ej. «vеndo», «vɇndo», «ħold»).
private func hasCrossScriptConfusableWord(_ text: String) -> Bool {
    let decomposed = compatNormalized(text).lowercased().decomposedStringWithCanonicalMapping
    let stripped = String(decomposed.unicodeScalars.filter {
        let cat = $0.properties.generalCategory
        return cat != .nonspacingMark && cat != .spacingMark && cat != .enclosingMark
    })
    let tokens = stripped.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    for token in tokens {
        var hasLatin = false
        var hasSuspicious = false
        for scalar in token.unicodeScalars where isLetterScalar(scalar) {
            if isSuspiciousConfusableLetter(scalar) {
                hasSuspicious = true
            } else if isLatinScriptLetter(scalar) {
                hasLatin = true
            }
        }
        if hasLatin && hasSuspicious { return true }
    }
    return false
}

/// true si el texto contiene alguna letra fuera de la escritura latina (cirílico, griego, CJK...).
private func hasNonLatinScriptLetter(_ text: String) -> Bool {
    compatNormalized(text).unicodeScalars.contains { isLetterScalar($0) && !isLatinScriptLetter($0) }
}

// MARK: Detector de peticiones de consejo de inversión (A3, J7, J15, J21(c), J22, U1)

/// Claves normalizadas de comercios presentes en el libro (`merchant` y `bankMerchant`).
func ledgerMerchantKeys(in state: LedgerState) -> Set<String> {
    var keys = Set<String>()
    for m in state.movements where !m.flaggedNotMine {
        for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
            let k = normalizeMerchant(raw)
            if !k.isEmpty { keys.insert(k) }
        }
    }
    return keys
}

/// Convierte dígitos de sustitución (leetspeak) dentro de palabras que contienen letras (`V3ndo` -> `Vendo`, `C0mpro` -> `Compro`).
/// Los números puros (`1000`, `2025`) se dejan intactos.
private func leetNormalized(_ text: String) -> String {
    let map: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t"]
    let folded = foldedQuery(foldConfusables(text))
    let rawTokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let converted = rawTokens.map { token -> String in
        guard token.contains(where: \.isLetter) else { return token }
        return String(token.map { map[$0] ?? $0 })
    }
    return converted.joined(separator: " ")
}

/// Lectura fonética (U1): `v->b`, `k->c`, `m->n` delante de `b`/`p` (aplicada igual a la pregunta y a todas las raíces).
private func phoneticWord(_ word: String) -> String {
    let chars = Array(word.map { ch -> Character in
        switch ch {
        case "v": return "b"
        case "k": return "c"
        default: return ch
        }
    })
    var out: [Character] = []
    out.reserveCapacity(chars.count)
    for i in chars.indices {
        if chars[i] == "m", i + 1 < chars.count, (chars[i + 1] == "b" || chars[i + 1] == "p") {
            out.append("n")
        } else {
            out.append(chars[i])
        }
    }
    return String(out)
}

/// Quita el prefijo `re` delante de una raíz fonética de decisión (`reconpro` -> `conpro`, `rebendo` -> `bendo`).
private func stripReDecisionPrefix(_ phonetic: String) -> String {
    guard phonetic.hasPrefix("re"), phonetic.count > 4 else { return phonetic }
    let tail = String(phonetic.dropFirst(2))
    if tail.hasPrefix("conpr") || tail.hasPrefix("bend") || tail.hasPrefix("inbert")
        || tail.hasPrefix("inbiert") || tail.hasPrefix("inbirt") {
        return tail
    }
    return phonetic
}

/// Todas las lecturas de palabras de la pregunta, incluyendo NFKD, confusables y leetspeak.
private func allAdviceReadings(_ text: String) -> [[String]] {
    var readings = allQuestionReadings(text)
    let leet = leetNormalized(text)
    for r in wordReadings(leet) where !readings.contains(r) { readings.append(r) }
    return readings
}

/// Palabras enteras que siempre marcan una petición de consejo o de operación (U1: sin `quedarme`).
private let unconditionalAdviceWords: Set<String> = Set([
    "conviene", "convienen", "quedate", "tendrias", "should",
    "buy", "buys", "buying", "sell", "sells", "selling", "hold", "holds", "stay",
    "shorteo", "shortear", "shortea", "trading",
].map(phoneticWord))

/// Prefijos que siempre marcan una petición de consejo (U1: sin `manten`/`mantien`, `asesor`, `promedi`).
private let unconditionalAdvicePrefixes: [String] = [
    "recomiend", "recomend", "aconsej", "consej", "suger", "sugier", "aprovech",
    "diversific", "reequilibr", "rebalanc", "deshaz", "deshag", "deshac",
    "convendr", "acumul", "refuerz", "reforz", "aguant",
    "recommend", "advice", "advis", "purchase",
].map(phoneticWord)

/// Frases que siempre marcan una petición de consejo (U1: sin «el momento de», conserva «promedio/a/ar a la baja»).
private let unconditionalAdvicePhrases: [String] = [
    "buen momento", "es momento de", "es hora de", "buena idea",
    "vale la pena", "valen la pena", "valdra la pena", "valdran la pena", "valdria la pena", "valdrian la pena",
    "merece la pena", "merecen la pena", "merecera la pena", "mereceran la pena", "mereceria la pena", "merecerian la pena",
    "promedio a la baja", "promedia a la baja", "promediar a la baja",
    "yo que tu", "yo de ti", "habria que", "tendrias que",
    "toma beneficios", "tomo beneficios", "tomar beneficios", "tomamos beneficios",
    "recoge beneficios", "recojo beneficios", "recoger beneficios",
    "toma ganancias", "tomo ganancias", "tomar ganancias", "recojo ganancias", "recoger ganancias",
    "sal de", "salir de bolsa", "salgo de bolsa", "entrar en bolsa", "entro en bolsa",
    "meter dinero en", "mete dinero en", "meto dinero en",
    "pon dinero en", "pongo dinero en", "poner dinero en",
    "donde meto", "donde meter", "donde pongo mi dinero", "donde poner mi dinero",
    "en que pongo", "en que poner", "donde invierto", "en que invierto", "donde invertir", "en que invertir",
    "sacar rentabilidad", "doblo la apuesta", "doblar la apuesta", "echo dinero a", "echar dinero a",
    "opero con", "renuevo el deposito", "renovar el deposito",
    "take profit", "take profits", "get out", "stay put", "should i", "good time to",
    "worth buying", "worth selling", "worth investing", "how much to invest", "what to invest",
    "where to put my money", "where should i put",
    "mejor esperar", "espera a que", "esperar a que",
].map { $0.split(separator: " ").map { phoneticWord(String($0)) }.joined(separator: " ") }

/// Formas pasadas que solo describen hechos ya ocurridos (J7 + U1 tercera persona, «nosotros» e imperfecto).
private let pastDescribingTradeWords: Set<String> = Set([
    "comprado", "comprada", "comprados", "compradas", "compraste", "compraron",
    "compraba", "comprabas", "comprabamos", "compraban",
    "vendido", "vendida", "vendidos", "vendidas", "vendiste", "vendi", "vendio", "vendieron",
    "vendia", "vendias", "vendiamos", "vendian",
    "invertido", "invertida", "invertidos", "invertidas", "invertiste", "inverti", "invirtio", "invirtieron",
    "invertia", "invertias", "invertiamos", "invertian",
    "aportado", "aportada", "aportados", "aportadas", "aportaste", "aportaron",
    "aportaba", "aportabas", "aportabamos", "aportaban",
].map(phoneticWord))

/// Determinantes y palabras de contexto de gasto que convierten «compra(s)»/«venta(s)» en sustantivo factual.
private let factualNounPredecessors: Set<String> = [
    "en", "de", "del", "para", "por", "sobre", "con", "sin",
    "categoria", "presupuesto", "presupuestos", "gasto", "gastos", "gaste", "llevo",
    "cuanto", "cuanta", "cuantos", "cuantas",
    "tu", "tus", "la", "las", "una", "unas", "esa", "esas", "esta", "estas", "mi", "mis", "su", "sus",
    "cada", "ultima", "ultimas", "primera", "primeras", "mayor", "mayores", "gran", "grandes",
    "hice", "hechas",
]

/// Verbos de planificación/acción que anulan el pase de sustantivo en «una compra»/«una venta» cuando hay contexto de inversión.
private let tradeActionLeadWords: Set<String> = [
    "hago", "hacer", "hagamos", "haria", "programo", "programar", "lanzo", "lanzar",
    "pongo", "poner", "meto", "meter", "debo", "deberia", "quiero", "voy", "toca",
]

/// Marcadores condicionales (U1: solo con S, o dos W distintos, o espera de mercado sin factura/cobro).
private let conditionalAdviceWords: Set<String> = [
    "deberia", "deberias", "deberiamos", "debo", "debes", "debemos", "debiera", "tendria", "podria", "podrias",
    "mejor", "considera", "considerar", "plantea", "plantear", "planteo", "evita", "evitar", "procura", "intenta",
    "opinas", "opinar", "wait", "avoid", "consider", "better",
]

private let conditionalAdvicePhrases = [
    "tengo que", "tienes que", "hay que", "crees que", "piensas que", "piensas de", "opinas de",
    "que te parece", "que me dices de",
]

/// Palabras cotidianas que empiezan por «manten», «acumul» o «bend» y no piden consejo.
private let nonAdvicePrefixExceptions: Set<String> = Set([
    "mantenimiento", "mantenimientos", "acumulado", "acumulada", "acumulados", "acumuladas",
    "bendito", "bendita", "benditos", "benditas", "bendicion", "bendiciones", "bendecir",
].map(phoneticWord))

/// Verbos de acción sobre cartera/posiciones (U1: incluye añadir, soltar, pillar, coger, cancelar, aportar, apostar).
private let portfolioActionWords: Set<String> = [
    "meto", "meter", "mete", "metemos", "meten", "meteria", "metiendo",
    "pongo", "poner", "pone", "ponemos", "ponen", "pondria", "poniendo",
    "salgo", "salir", "sal", "salimos", "salen", "saldria", "saliendo",
    "entro", "entrar", "entra", "entramos", "entran", "entraria", "entrando",
    "quedo", "quedar", "quedarme", "quedamos", "quedaria",
    "cambio", "cambiar", "cambia", "cambiamos", "cambiaria", "cambiando",
    "aporto", "aportar", "aporta", "aportamos", "aportaria", "aportando",
    "anado", "anadir", "anade", "anadimos", "anadiria", "anadiendo",
    "suelto", "soltar", "suelta", "soltamos", "soltaria", "soltando",
    "pillo", "pillar", "pilla", "pillamos", "pillaria", "pillando",
    "cojo", "coger", "coge", "cogemos", "cogeria", "cogiendo",
    "cancelo", "cancelar", "cancela", "cancelamos", "cancelaria", "cancelando",
    "elijo", "elegir", "elige", "elegiria", "escojo", "escoger",
    "liquido", "liquidar", "liquida", "liquidamos", "liquidaria", "liquidando",
    "saco", "sacar", "saca", "sacaria", "sacando",
    "retiro", "retirar", "retira", "retiramos", "retiraria", "retirando",
    "cierro", "cerrar", "cierra", "cerramos", "cerraria", "cerrando",
    "toco", "tocar", "toques", "toque",
    "aumento", "aumentar", "aumenta", "aumentamos", "aumentaria", "aumentando",
    "amplio", "ampliar", "amplia", "ampliamos", "ampliaria", "ampliando",
    "adquiero", "adquirir", "adquiere", "adquirimos", "adquiriria", "adquiriendo",
    "muevo", "mover", "mueve", "movemos", "moveria", "moviendo",
    "paso", "pasar", "pasa", "pasamos", "pasaria", "pasando",
    "apuesto", "apostar", "apuesta", "apostamos", "apostaria", "apostando",
    "sigo", "seguir", "sigue", "seguimos", "seguiria", "siguiendo",
    "dump", "exit", "trim", "reallocate",
]

/// Verbos de decisión en primera persona para la regla B(b) (objeto propio distinto de dinero propio).
private let firstPersonDecisionVerbs: Set<String> = [
    "apuesto", "meto", "pongo", "anado", "suelto", "pillo", "cojo",
    "liquido", "cancelo", "entro", "salgo", "retiro", "cierro",
    "aumento", "amplio", "adquiero", "elijo", "escojo",
    "mantengo", "mantener", "promedio", "promediar",
]

/// Frases de rendimiento pasado/actual con «mejor» que son factuales, nunca consejos.
private let factualMejorPhrases = [
    "mejor ha ido", "mejor han ido", "ha ido mejor", "han ido mejor", "fue mejor", "fueron mejor",
    "va mejor", "van mejor", "peor ha ido", "peor han ido", "ha ido peor", "han ido peor",
]

/// Frases de predicción de precios.
private let futurePricePhrases = [
    "va a subir", "va a bajar", "va a caer", "van a subir", "van a bajar", "van a caer",
    "seguira subiendo", "seguira bajando", "seguira cayendo", "se va a desplomar",
    "go up", "go down", "going to drop", "going to rise", "going to fall", "going to crash",
]

private let futurePriceWords: Set<String> = [
    "subira", "subiran", "bajara", "bajaran", "subiria", "bajaria", "subirian", "bajarian",
    "caera", "caeran", "caeria", "caerian", "desplomara", "desplomaran", "desplomaria",
]

/// Valoraciones (U1: cuentan como D con S y en la regla B(c) con nombre propio que no es banco).
private let valuationPhrases = [
    "buena inversion", "mala inversion", "buena idea", "mala idea",
    "buen momento", "mal momento", "buena opcion", "mala opcion",
    "es buena", "es buen", "esta caro", "esta cara", "esta barato", "esta barata",
    "estan caros", "estan caras", "estan baratos", "estan baratas",
    "es rentable", "son rentables", "me compensa", "te compensa",
    "merece la pena", "merecen la pena", "merecera la pena", "mereceran la pena", "mereceria la pena", "merecerian la pena",
    "vale la pena", "valen la pena", "valdra la pena", "valdran la pena", "valdria la pena", "valdrian la pena",
]

private let valuationWords: Set<String> = ["overvalued", "undervalued", "worth", "compensa"]

private let opinionAboutAssetPhrases = [
    "opinas de", "piensas de", "que te parece", "que me dices de", "me interesa", "tiene futuro",
]

/// Verbos de gasto cotidiano (U1 + N1: hechos; eximen `comprar/comprando/compraron/compramos` y bloquean regla B(b)).
private let spendingVerbWords: Set<String> = [
    "gaste", "gastado", "gastamos", "pague", "pagado", "pagamos", "costo",
]

private let spendingVerbPhrases = [
    "me queda", "me costo", "me cuesta", "me cuestan",
    "me cobra", "me cobran", "me cobro", "me cobraron",
    "me pago", "cuanto pago de", "pago de cuota",
    "he pagado", "he gastado",
]

/// Palabras que marcan pretérito junto a «compre» sin tilde (U1 punto 6).
private let pastMarkersForCompre: Set<String> = [
    "ayer", "anteayer", "anoche", "hoy", "finde", "manana", "tarde", "noche",
    "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "setiembre", "octubre", "noviembre", "diciembre",
]

private let pastPhrasesForCompre = [
    "el otro dia", "semana pasada", "mes pasado", "que compre en", "cuando compre", "cuanto compre", "donde compre",
]

private let billOrPaymentWords: Set<String> = [
    "pagar", "cobro", "cobros", "recibo", "recibos", "factura", "facturas", "nomina", "ingreso", "ingresos",
    "dividendo", "dividendos",
]

/// Plantillas factuales cerradas (F) cuando hay contexto fuerte S (U1 punto 3 + N1 2b).
private let factualInvestmentPhrases = [
    "como va", "como van", "como ha ido", "como han ido", "como esta", "como estan",
    "que tal va", "que tal van", "que tal esta", "que tal estan",
    "cuanto vale", "cuanto valen", "cuanto valia", "cuanto valian",
    "cuanto tengo", "cuanto llevo", "cuantas acciones tengo", "que tengo en",
    "a cuanto esta", "a cuanto cotiza", "cuanto cotiza", "cual es la cotizacion",
    "que precio tiene", "cual es el precio", "cual es el valor",
    "cual es mi cartera", "cual es mi posicion", "cual es la rentabilidad",
    "resumen de mi cartera", "resumen de cartera", "resumen de mis inversiones",
    "valor de mi cartera", "valor de cartera", "valor de mis inversiones",
    "que ha subido", "que ha bajado", "que ha caido", "mas ha subido", "mas ha bajado", "mas subio", "mas bajo",
    "ha subido mas", "ha bajado mas", "subido mas", "bajado mas",
    "mejor ha ido", "peor ha ido", "mejor han ido", "peor han ido",
    "ha ido mejor", "ha ido peor", "han ido mejor", "han ido peor",
    "cuanto ha subido", "cuanto ha bajado", "cuanto ha caido", "cuanto han caido",
    "cuanto me ha dado", "cuanto ha dado", "cuanto me han dado",
    "cuanto he ganado", "cuanto he perdido", "cuanto gane", "cuanto perdi",
    "desde la compra",
    "cuando compre", "cuando vendi", "a que precio compre", "a que precio vendi",
    "cuanto compre", "cuanto he comprado", "cuanto vendi", "cuanto he vendido",
    "cuanto inverti", "cuanto he invertido", "cuanto aporte", "cuanto he aportado",
    "que dividendos he cobrado", "que dividendos cobre", "que dividendos espero", "que dividendos me tocan",
    "cuando cobro el dividendo", "cuando me pagan el dividendo", "cuantos dividendos he cobrado",
    "cuanto he cobrado en dividendos", "cuanto cobre de dividendo", "cuanto cobre en dividendos",
    "cuando espero el cobro", "cuando espero el dividendo",
    "cuando es la proxima aportacion", "cuando es mi proxima aportacion", "proxima aportacion",
    "que suscripciones tengo", "suscripciones tengo",
]

/// Palabras permitidas en una consulta corta factual de cartera («Mi cartera», «Inversiones», «Dividendos»).
private let bareInvestmentFactFillers: Set<String> = [
    "mi", "mis", "la", "el", "los", "las", "de", "resumen", "valor",
]

/// Palabras comunes de inicio de frase en español/inglés que NO son nombres propios de activos cuando van en índice 0.
private let sentenceStarterWords: Set<String> = [
    "que", "quien", "quienes", "cual", "cuales", "cuanto", "cuanta", "cuantos", "cuantas",
    "como", "cuando", "donde", "porque", "para", "por", "con", "sin", "en", "de", "del", "al", "a",
    "el", "la", "los", "las", "un", "una", "unos", "unas", "mi", "mis", "tu", "tus", "su", "sus",
    "este", "esta", "estos", "estas", "ese", "esa", "esos", "esas", "esto", "eso",
    "hay", "es", "son", "fue", "fueron", "era", "eran", "estan", "va", "van", "voy", "veo",
    "tengo", "tienes", "tiene", "tenemos", "tienen", "debo", "debes", "debe", "deberia", "deberias", "deberiamos",
    "puedo", "puedes", "puede", "podria", "podrias", "quiero", "quiere", "querria",
    "hago", "haces", "hace", "haria", "harias", "he", "has", "ha", "hemos", "han",
    "crees", "piensas", "opinas", "merece", "mereceria", "vale", "valdria", "compensa",
    "subira", "bajara", "caera", "mejor", "peor", "mas", "menos", "si", "no", "ya", "aun", "todavia",
    "hola", "dime", "cuentame", "muestrame", "ensename", "resumen", "valor",
    "saldo", "saldos", "gasto", "gastos", "gaste", "pago", "pagos", "pague",
    "compra", "compras", "compro", "compre", "venta", "ventas", "vendo", "vendi",
    "cobro", "cobros", "recibo", "recibos", "factura", "facturas", "ingreso", "ingresos",
    "traspaso", "traspasos", "suscripcion", "suscripciones", "presupuesto", "presupuestos",
    "dinero", "cartera", "inversion", "inversiones", "dividendo", "dividendos",
    "posicion", "posiciones", "accion", "acciones", "fondo", "fondos", "etf", "etfs", "cripto", "bolsa", "oro",
    "mantengo", "promedio", "sigo", "meto", "pongo", "paso", "entro", "salgo", "apuesto", "contrato", "shorteo", "renuevo",
    "buen", "buena", "buenos", "buenas", "mal", "mala", "malos", "malas",
    "hoy", "ayer", "manana", "ahora", "antes", "despues", "luego", "hasta", "desde",
    "todo", "todos", "toda", "todas", "nada", "algo", "otro", "otra", "cada", "solo", "yo", "me", "te", "se", "nos", "le", "lo",
    "should", "what", "which", "where", "when", "how", "is", "are", "will", "would", "can", "do", "does", "did",
    "my", "the", "an", "worth", "good", "best", "buy", "sell", "hold", "invest",
]

/// Contexto FUERTE de inversión S (U1 punto 2).
private let strongInvestmentExactWords: Set<String> = [
    "accion", "acciones", "cartera", "etf", "etfs", "fondo", "fondos", "bolsa",
    "crypto", "bitcoin", "btc", "ethereum", "eth", "msci", "sp500", "ibex", "nasdaq",
    "broker", "stock", "stocks", "share", "shares", "portfolio",
    "inversion", "inversiones", "dividendo", "dividendos", "posicion", "posiciones",
    "exposicion", "dca",
]

private let strongInvestmentPrefixes: [String] = [
    "cripto", "aport",
]

/// Bancos propios y palabras que nunca son un activo externo en reglas B(b)/B(c).
private let ownBankWords: Set<String> = [
    "revolut", "imagin", "caixabank", "caixa", "traderepublic", "trade", "republic",
    "cuenta", "cuentas", "banco", "bancos", "hucha", "presupuesto", "presupuestos", "colchon",
]

/// Índices de `list` cubiertos por un nombre COMPLETO de comercio del libro («apple store», «el vendedor de loteria», «vendome», «comprarte»).
private func fullKnownMerchantIndices(in list: [String], knownMerchants: Set<String>) -> Set<Int> {
    guard !knownMerchants.isEmpty, !list.isEmpty else { return [] }
    var covered = Set<Int>()
    for key in knownMerchants {
        let mt = key.split(separator: " ").map(String.init)
        guard !mt.isEmpty, mt.count <= list.count else { continue }
        for start in 0...(list.count - mt.count) {
            if Array(list[start..<(start + mt.count)]) == mt {
                for i in start..<(start + mt.count) { covered.insert(i) }
            }
        }
    }
    return covered
}

/// Índices que representan un comercio del libro para eximir raíces `vend`/`compr` («en vending» -> «vending sur»).
private func tradeRootMerchantIndices(in list: [String], knownMerchants: Set<String>, fullIndices: Set<Int>) -> Set<Int> {
    var covered = fullIndices
    guard !knownMerchants.isEmpty else { return covered }
    let leadingTokens: Set<String> = Set(knownMerchants.compactMap { key -> String? in
        guard let first = key.split(separator: " ").first.map(String.init), first.count >= 4 else { return nil }
        return first
    })
    for i in list.indices where !covered.contains(i) && leadingTokens.contains(list[i]) {
        let afterEn = (i > 0 && list[i - 1] == "en")
            || (i > 1 && list[i - 2] == "en" && ["el", "la", "los", "las"].contains(list[i - 1]))
        if afterEn { covered.insert(i) }
    }
    return covered
}

/// Extrae las palabras con mayúscula inicial que son candidatas a nombre propio (U1 + N1: incluye índice 0 si no es palabra común de inicio).
private func properNounTokens(in originalQuestion: String) -> Set<String> {
    let cleaned = compatNormalized(originalQuestion)
        .replacingOccurrences(of: "¿", with: " ")
        .replacingOccurrences(of: "?", with: " ")
        .replacingOccurrences(of: "¡", with: " ")
        .replacingOccurrences(of: "!", with: " ")
        .replacingOccurrences(of: ",", with: " ")
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: ":", with: " ")
        .replacingOccurrences(of: ";", with: " ")
    let rawWords = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
    var out = Set<String>()
    for (idx, word) in rawWords.enumerated() {
        guard let first = word.first, first.isUppercase else { continue }
        let norm = foldedQuery(word).components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        guard norm.count >= 2 else { continue }
        if idx == 0 && sentenceStarterWords.contains(norm) { continue }
        out.insert(norm)
    }
    return out
}

/// Detecta si hay contexto FUERTE (S) y cuántos conceptos distintos de contexto DÉBIL (W) hay (U1 punto 2).
private func investmentContexts(list: [String], phoneticList: [String], alnumTokens: [String],
                                fullMerchantIdx: Set<Int>, portfolio: Portfolio?) -> (strong: Bool, weakCount: Int, weakWords: Set<String>) {
    var strong = false
    let joined = " " + list.joined(separator: " ") + " "
    if joined.contains(" plan de inversion ") || joined.contains(" plan de pensiones ")
        || joined.contains(" planes de pensiones ") || joined.contains(" letras del tesoro ") {
        strong = true
    }

    for (i, w) in list.enumerated() where !fullMerchantIdx.contains(i) {
        if strongInvestmentExactWords.contains(w) || strongInvestmentPrefixes.contains(where: { w.hasPrefix($0) }) {
            strong = true; break
        }
        let pw = stripReDecisionPrefix(phoneticList[i])
        if (pw.hasPrefix("inbert") || pw.hasPrefix("inbiert") || pw.hasPrefix("inbirt")) && !w.hasPrefix("investig") {
            strong = true; break
        }
    }
    if !strong {
        for w in alnumTokens {
            if strongInvestmentExactWords.contains(w) || strongInvestmentPrefixes.contains(where: { w.hasPrefix($0) }) {
                strong = true; break
            }
        }
    }
    if !strong, let portfolio {
        let filteredLetters = list.enumerated().compactMap { fullMerchantIdx.contains($0.offset) ? nil : $0.element }
        let joinedFiltered = " " + filteredLetters.joined(separator: " ") + " "
        let filteredAlnum = alnumTokens.filter { tok in
            // Si el token solo aparece dentro de un comercio completo («apple store»), no cuenta como posición.
            let positionsInList = list.indices.filter { list[$0] == tok }
            if !positionsInList.isEmpty && positionsInList.allSatisfy({ fullMerchantIdx.contains($0) }) { return false }
            return true
        }
        let joinedAlnum = " " + filteredAlnum.joined(separator: " ") + " "
        for pos in positions(from: portfolio.transactions) {
            if positionMatchesInFolded(pos, foldedJoined: joinedAlnum, tokens: filteredAlnum)
                || positionMatchesInFolded(pos, foldedJoined: joinedFiltered, tokens: filteredLetters) {
                strong = true; break
            }
        }
    }

    // Contexto DÉBIL W (con las exclusiones exactas de U1: «la renta»/«de la renta»/«bono del/de/transporte/gimnasio», «fund» palabra entera).
    var weakConcepts = Set<String>()
    var weakMatchedWords = Set<String>()
    for (i, w) in list.enumerated() where !fullMerchantIdx.contains(i) {
        let prev = i > 0 ? list[i - 1] : ""
        let next = i + 1 < list.count ? list[i + 1] : ""
        switch w {
        case "mercado", "mercados":
            weakConcepts.insert("mercado"); weakMatchedWords.insert(w)
        case "renta":
            let isTaxRenta = prev == "la" || joined.contains(" de la renta ") || joined.contains(" declaracion de la renta ")
            if !isTaxRenta { weakConcepts.insert("renta"); weakMatchedWords.insert(w) }
        case "bono", "bonos":
            let isNonInvBono = ["del", "de", "transporte", "gimnasio"].contains(next)
            if !isNonInvBono { weakConcepts.insert("bono"); weakMatchedWords.insert(w) }
        case "deposito", "depositos":
            weakConcepts.insert("deposito"); weakMatchedWords.insert(w)
        case "oro", "gold":
            weakConcepts.insert("oro"); weakMatchedWords.insert(w)
        case "tesoro":
            weakConcepts.insert("tesoro"); weakMatchedWords.insert(w)
        case "beneficio", "beneficios":
            weakConcepts.insert("beneficio"); weakMatchedWords.insert(w)
        case "rentable", "rentables", "rentabilidad":
            weakConcepts.insert("rentabilidad"); weakMatchedWords.insert(w)
        case "fund", "funds":
            weakConcepts.insert("fund"); weakMatchedWords.insert(w)
        default:
            break
        }
    }
    return (strong, weakConcepts.count, weakMatchedWords)
}

/// U87: valores y criptos conocidos que no están en la cartera ni en `strongInvestmentExactWords`. Solo los usa
/// `questionNamesInvestmentSubject`; el filtro de consejos no cambia (U69(c)). Sin marcas que también son comercios
/// habituales (Apple, Amazon, Netflix…) ni bancos o recibos (Santander, Iberdrola, Repsol…).
private let knownSecurityNames: Set<String> = [
    "nvidia", "tesla", "amd", "palantir", "alphabet", "berkshire", "inditex", "solana", "dogecoin", "doge",
    "xrp", "ripple", "cardano",
]

/// U87: true si la pregunta nombra algo de inversión: el S del filtro de consejos (una posición de la cartera, vocabulario
/// de inversión o cripto), oro, o un valor conocido. No cuenta lo que forma parte de un comercio del libro («Apple Store»).
func questionNamesInvestmentSubject(_ question: String, portfolio: Portfolio?, knownMerchants: Set<String>) -> Bool {
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let alnumTokens = foldedQuery(foldConfusables(trimmed))
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    for list in allAdviceReadings(trimmed) where !list.isEmpty {
        let fullMerchantIdx = fullKnownMerchantIndices(in: list, knownMerchants: knownMerchants)
        let ctx = investmentContexts(list: list, phoneticList: list.map(phoneticWord), alnumTokens: alnumTokens,
                                     fullMerchantIdx: fullMerchantIdx, portfolio: portfolio)
        if ctx.strong { return true }
        for (i, w) in list.enumerated() where !fullMerchantIdx.contains(i) {
            if w == "oro" || w == "gold" || knownSecurityNames.contains(w) { return true }
        }
    }
    return false
}

/// true si la pregunta es solo «Compra(s)» / «Venta(s)» (≤ 3 palabras o con «este mes» / «el mes pasado» / un mes / ayer / hoy) — U1 punto 6.
private func isBareCategoryTradeQuery(_ list: [String], joined: String) -> Bool {
    guard let first = list.first, ["compra", "compras", "venta", "ventas"].contains(first) else { return false }
    if list.count == 1 { return true }
    let rest = Array(list.dropFirst())
    if rest == ["este", "mes"] || rest == ["mes", "pasado"] || rest == ["el", "mes", "pasado"]
        || rest == ["ayer"] || rest == ["hoy"] || rest == ["esta", "semana"] || rest == ["con", "tarjeta"] {
        return true
    }
    let monthSet = Set(spanishMonthNames.map(\.name))
    if rest.count == 1 && monthSet.contains(rest[0]) { return true }
    if rest.count == 2 && (rest[0] == "de" || rest[0] == "en") && monthSet.contains(rest[1]) { return true }
    return false
}

/// true si la pregunta del dueño pide un consejo de inversión (qué comprar, vender, mantener, cuánto invertir o predicciones).
/// U1: separa contexto fuerte (S) de débil (W) y detecta estructura («verbo de decisión + activo», «valoración/predicción + activo»).
public func isAdviceRequest(_ question: String, portfolio: Portfolio? = nil, knownMerchants: Set<String> = []) -> Bool {
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if hasCrossScriptConfusableWord(trimmed) { return true }

    // Conserva tildes del original (NFC) para distinguir «compré»/«compró»/«aporté»/«entró»/«líquido» de verbos en 1.ª persona.
    let rawAccentedList = withoutFormatCharacters(question).precomposedStringWithCanonicalMapping.lowercased()
        .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    let rawPastCompreCount = rawAccentedList.filter { $0 == "compré" }.count
    let rawUnaccentedCompreCount = rawAccentedList.filter { $0 == "compre" }.count
    let rawPastComproCount = rawAccentedList.filter { $0 == "compró" }.count
    let rawPresentComproCount = rawAccentedList.filter { $0 == "compro" }.count
    let rawPastAporteCount = rawAccentedList.filter { $0 == "aporté" }.count
    let rawPastEntroCount = rawAccentedList.filter { $0 == "entró" }.count
    let rawPresentEntroCount = rawAccentedList.filter { $0 == "entro" }.count
    let rawAccentedLiquidoCount = rawAccentedList.filter { $0 == "líquido" }.count

    let alnumTokens = foldedQuery(foldConfusables(trimmed))
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let hasMoneyCue = trimmed.contains("€") || trimmed.contains("$")
        || alnumTokens.contains("euros") || alnumTokens.contains("euro") || alnumTokens.contains("eur")
        || alnumTokens.contains("dinero")
    let hasExplicitAmount = trimmed.range(of: #"[0-9]+(?:[.,][0-9]+)?\s*(?:€|\$|euros?|eur\b)"#,
                                          options: [.regularExpression, .caseInsensitive]) != nil
        || trimmed.range(
            of: #"\b(?:mil|cien|cientos|doscientos|trescientos|cuatrocientos|quinientos|seiscientos|setecientos|ochocientos|novecientos|millon(?:es)?)\s+(?:de\s+)?(?:€|\$|euros?|eur\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    let properNouns = properNounTokens(in: trimmed)

    for list in allAdviceReadings(trimmed) {
        guard !list.isEmpty else { continue }
        let phoneticList = list.map(phoneticWord)
        let joined = " " + list.joined(separator: " ") + " "
        let phoneticJoined = " " + phoneticList.joined(separator: " ") + " "

        let fullMerchantIdx = fullKnownMerchantIndices(in: list, knownMerchants: knownMerchants)
        let merchantIdx = tradeRootMerchantIndices(in: list, knownMerchants: knownMerchants, fullIndices: fullMerchantIdx)
        let ctx = investmentContexts(list: list, phoneticList: phoneticList, alnumTokens: alnumTokens,
                                     fullMerchantIdx: fullMerchantIdx, portfolio: portfolio)
        let hasTradeActionLead = list.contains { tradeActionLeadWords.contains($0) }
        let hasSpendingVerb = list.contains { spendingVerbWords.contains($0) }
            || spendingVerbPhrases.contains { joined.contains(" " + $0 + " ") }
        let listCompreCount = list.filter { $0 == "compre" }.count
        let hasPastCompreOnly = rawPastCompreCount > 0 && rawUnaccentedCompreCount == 0 && listCompreCount <= rawPastCompreCount
        let hasPastComproOnly = rawPastComproCount > 0 && rawPresentComproCount == 0
        let hasPastEntroOnly = rawPastEntroCount > 0 && rawPresentEntroCount == 0
        let hasComprePastMarker = list.contains { pastMarkersForCompre.contains($0) }
            || pastPhrasesForCompre.contains { joined.contains(" " + $0 + " ") }
            || !merchantIdx.isEmpty
        let bareCategory = isBareCategoryTradeQuery(list, joined: joined)

        // Comprueba marcadores incondicionales (usados tanto en Regla A como en Regla B(a)).
        var hasUnconditionalTradeOrAdvice = false
        for (i, word) in list.enumerated() {
            if merchantIdx.contains(i) { continue }
            let pw = stripReDecisionPrefix(phoneticList[i])
            if unconditionalAdviceWords.contains(pw) { hasUnconditionalTradeOrAdvice = true; break }
            if !nonAdvicePrefixExceptions.contains(pw),
               unconditionalAdvicePrefixes.contains(where: { pw.hasPrefix($0) }) {
                hasUnconditionalTradeOrAdvice = true; break
            }
            if word.hasPrefix("invest") && !word.hasPrefix("investig") {
                hasUnconditionalTradeOrAdvice = true; break
            }

            if word == "venta" || word == "ventas" {
                if bareCategory { continue }
                if isFactualTradeNoun(word, at: i, in: list) && !(ctx.strong && hasTradeActionLead) { continue }
                hasUnconditionalTradeOrAdvice = true; break
            }

            if !pastDescribingTradeWords.contains(pw) {
                if pw.hasPrefix("bend") && !nonAdvicePrefixExceptions.contains(pw) {
                    hasUnconditionalTradeOrAdvice = true; break
                }
                if (pw.hasPrefix("inbert") || pw.hasPrefix("inbiert") || pw.hasPrefix("inbirt")) && !word.hasPrefix("investig") {
                    hasUnconditionalTradeOrAdvice = true; break
                }
                let isComprarForm = pw == "conpro" || pw.hasPrefix("conpra")
                    || (pw.hasPrefix("conpre") && !pw.hasPrefix("conprend") && !pw.hasPrefix("conpresi")
                        && pw != "conpresa" && pw != "conpresas")
                if isComprarForm {
                    if word == "compra" || word == "compras" {
                        if bareCategory { continue }
                        if isFactualTradeNoun(word, at: i, in: list) && !(ctx.strong && hasTradeActionLead) { continue }
                        hasUnconditionalTradeOrAdvice = true; break
                    }
                    if pw == "conpro" && hasPastComproOnly { continue }
                    if word == "compre" {
                        if hasPastCompreOnly { continue }
                        if hasComprePastMarker && !ctx.strong { continue }
                        let pastShop = list.contains("cuanto") && list.contains("en") && !ctx.strong
                        if pastShop { continue }
                        hasUnconditionalTradeOrAdvice = true; break
                    }
                    // U1 punto 6: comprar/comprando/compraron/compramos junto a verbo de gasto es hecho.
                    if ["comprar", "comprando", "compraron", "compramos"].contains(word) && hasSpendingVerb && !ctx.strong {
                        continue
                    }
                    if word == "compramos" && !ctx.strong && (list.contains("cuanto") || list.contains("que")) {
                        continue
                    }
                    hasUnconditionalTradeOrAdvice = true; break
                }
            }
        }
        if !hasUnconditionalTradeOrAdvice,
           unconditionalAdvicePhrases.contains(where: { phoneticJoined.contains(" " + $0 + " ") }) {
            hasUnconditionalTradeOrAdvice = true
        }

        // Helpers para objetos/nombres propios externos y oro/gold.
        let externalProperNounsNotBank = properNouns.filter { noun in
            !ownBankWords.contains(noun)
                && extractCategory(joined: " " + noun + " ") == nil
                && !spanishMonthNames.contains(where: { $0.name == noun })
        }
        let externalProperNounsNotMerchant = externalProperNounsNotBank.filter { noun in
            !knownMerchants.contains(noun)
                && !knownMerchants.contains(where: { $0.split(separator: " ").contains(Substring(noun)) })
        }
        let hasInvestableCommodity = list.enumerated().contains {
            !fullMerchantIdx.contains($0.offset) && ($0.element == "oro" || $0.element == "gold")
        }

        // Marcadores de decisión (D): valoración, predicción, elección, verbos de decisión, condicionales.
        let isFactualMejor = factualMejorPhrases.contains { joined.contains(" " + $0 + " ") }
            && !list.enumerated().contains { (i, w) in
                if w == "entro" && hasPastEntroOnly { return false }
                return portfolioActionWords.contains(w)
            }
        let hasValuation = valuationPhrases.contains { joined.contains(" " + $0 + " ") }
            || list.contains { valuationWords.contains($0) }
        let hasPrediction = list.contains { futurePriceWords.contains($0) }
            || futurePricePhrases.contains { joined.contains(" " + $0 + " ") }
        let hasConditionalWord = list.contains { w in
            if w == "mejor" && isFactualMejor { return false }
            return conditionalAdviceWords.contains(w)
        }
        let hasConditional = hasConditionalWord || conditionalAdvicePhrases.contains { joined.contains(" " + $0 + " ") }
        let expectsScheduled = list.contains("espero") && list.contains { billOrPaymentWords.contains($0) }
        let hasWaitingVerb = !expectsScheduled && list.contains { $0.hasPrefix("esper") || $0.hasPrefix("aguard") }
        let hasSuboAportacion = list.contains { $0.hasPrefix("sub") } && list.contains { $0.hasPrefix("aport") }
        let isScheduledAportFact = joined.contains(" proxima aportacion ") || joined.contains(" ultima aportacion ")
        let hasAportDecision = !isScheduledAportFact && list.contains { w in
            w.hasPrefix("aport") && !pastDescribingTradeWords.contains(phoneticWord(w))
                && !(w == "aporte" && rawPastAporteCount > 0)
        }
        let isFactualInvestmentPerf = ["ha ido", "han ido", "ha subido", "han subido", "ha bajado", "han bajado",
                                       "ha caido", "han caido", "mas subio", "mas bajo", "mas ha subido", "mas ha bajado",
                                       "va mejor", "van mejor", "va peor", "van peor", "tengo", "vale", "valen", "valia"]
            .contains { joined.contains(" " + $0 + " ") }
        let hasTwoAssetChoice: Bool = {
            guard list.contains("o"), !hasSpendingVerb else { return false }
            for idx in list.indices where list[idx] == "o" && idx > 0 && idx + 1 < list.count {
                let left = list[idx - 1], right = list[idx + 1]
                let leftCandidate = strongInvestmentExactWords.contains(left) || externalProperNounsNotBank.contains(left)
                let rightCandidate = strongInvestmentExactWords.contains(right) || externalProperNounsNotBank.contains(right)
                let atLeastOneExternal = strongInvestmentExactWords.contains(left) || strongInvestmentExactWords.contains(right)
                    || externalProperNounsNotMerchant.contains(left) || externalProperNounsNotMerchant.contains(right)
                if leftCandidate && rightCandidate && atLeastOneExternal { return true }
            }
            return false
        }()
        let hasChoice = list.contains("which")
            || (!isFactualInvestmentPerf && ["que etf", "que accion", "que acciones", "que fondo", "que fondos", "que cripto"]
                .contains { joined.contains(" " + $0 + " ") })
            || ["cual elijo", "cual compro", "cual escojo"].contains { joined.contains(" " + $0 + " ") }
            || hasTwoAssetChoice
        let hasContextDecisionVerb = list.enumerated().contains { (i, w) in
            if nonAdvicePrefixExceptions.contains(phoneticWord(w)) { return false }
            if w == "entro" && hasPastEntroOnly { return false }
            if w == "aumento", i > 0, ["el", "un", "del", "este", "ese", "su", "mi"].contains(list[i - 1]) { return false }
            if w == "liquido", rawAccentedLiquidoCount > 0 || (i > 0 && ["dinero", "efectivo", "saldo"].contains(list[i - 1])) {
                return false
            }
            return portfolioActionWords.contains(w) || w.hasPrefix("manten") || w.hasPrefix("mantien")
                || w.hasPrefix("promedi") || w.hasPrefix("asesor") || w.hasPrefix("reduc")
        } || joined.contains(" me hago con ") || joined.contains(" le meto ") || joined.contains(" hago dca ")
            || joined.contains(" que hago con ") || joined.contains(" que haria ") || joined.contains(" que harias ")
            || hasSuboAportacion || hasAportDecision

        let hasAnyDecisionMarker = hasUnconditionalTradeOrAdvice || hasValuation || hasPrediction
            || hasConditional || hasWaitingVerb || hasChoice || hasContextDecisionVerb

        // REGLA A — Hay contexto FUERTE (S): es consejo SALVO que encaje en F sin ningún marcador D (U1 punto 3 + N1 2b).
        if ctx.strong {
            let matchesOwnershipFact: Bool = {
                guard list.contains("tengo"), !joined.contains(" tengo que ") else { return false }
                if list.contains("que") || list.contains("cuanto") || list.contains("cuanta")
                    || list.contains("cuantos") || list.contains("cuantas") {
                    return true
                }
                if let idx = list.firstIndex(of: "tengo"), idx + 1 < list.count {
                    let next = list[idx + 1]
                    return strongInvestmentExactWords.contains(next) || next == "en"
                }
                return false
            }()
            let isBareInvestmentFact: Bool = list.count <= 3 && list.allSatisfy { tok in
                strongInvestmentExactWords.contains(tok) || bareInvestmentFactFillers.contains(tok)
                    || (portfolio.map { p in positions(from: p.transactions).contains { pos in
                        let nk = normalizeMerchant(pos.name)
                        return nk == tok || nk.split(separator: " ").contains(Substring(tok))
                    } } ?? false)
            }
            let matchesFactualTemplate = factualInvestmentPhrases.contains { joined.contains(" " + $0 + " ") }
                || matchesOwnershipFact
                || isBareInvestmentFact
                || list.contains { explicitBalanceWords.contains($0) }
                || hasSpendingVerb
                || !fullMerchantIdx.isEmpty
            if matchesFactualTemplate && !hasAnyDecisionMarker {
                continue
            }
            return true
        }

        // REGLA B — No hay contexto fuerte S (U1 punto 5 + N1):
        // (a) Incondicional de hoy (con arreglos de falsos positivos del punto 6).
        if hasUnconditionalTradeOrAdvice { return true }

        // Paso 2b (U1 punto 6): «¿Meto 500 € en Tesla?» — solo si el destino tras «en» es S, W o nombre propio externo.
        if hasMoneyCue,
           list.contains(where: { ["meto", "meter", "mete", "pongo", "poner", "pon"].contains($0) }),
           !hasSpendingVerb, !list.contains("traspaso"), !list.contains("transferencia") {
            for (idx, tok) in list.enumerated() where tok == "en" && idx + 1 < list.count {
                let tailTokens = Array(list[(idx + 1)...])
                let next = tailTokens[0]
                let afterNext = tailTokens.count > 1 ? tailTokens[1] : ""
                let isOwnBankDest = ownBankWords.contains(next)
                    || (next == "trade" && afterNext == "republic")
                    || (next == "mi" && ownBankWords.contains(afterNext))
                    || (next == "la" && ["cuenta", "hucha"].contains(afterNext))
                if isOwnBankDest { continue }
                let destSpan = tailTokens.prefix(2).joined(separator: " ")
                if extractCategory(joined: " " + destSpan + " ") != nil { continue }
                if !fullMerchantIdx.isEmpty && fullMerchantIdx.contains(idx + 1) { continue }
                let isWeakDest = ctx.weakWords.contains(next)
                let isProperDest = properNouns.contains(next) && !ownBankWords.contains(next)
                if isWeakDest || isProperDest { return true }
            }
        }

        // (b) Verbo de decisión en 1.ª persona + objeto que NO es dinero propio (nombre propio externo, oro o importe explícito).
        if !hasSpendingVerb && !list.contains("traspaso") && !list.contains("transferencia") {
            let asksWhatToDo = joined.contains(" que hago con ") || joined.contains(" que haria ") || joined.contains(" que harias ")
            if asksWhatToDo {
                if let conIdx = list.firstIndex(of: "con") {
                    let objTokens = conIdx + 1 < list.count ? Array(list[(conIdx + 1)...]) : []
                    let objJoined = " " + objTokens.joined(separator: " ") + " "
                    let isOwnObj = objTokens.contains { ownBankWords.contains($0) }
                        || extractCategory(joined: objJoined) != nil
                        || !fullMerchantIdx.isEmpty
                    if !isOwnObj && (hasExplicitAmount || objTokens.contains { externalProperNounsNotMerchant.contains($0) }
                        || objTokens.contains("dinero") || objTokens.contains("ahorro") || objTokens.contains("ahorros")
                        || objTokens.contains("herencia") || objJoined.contains(" paga extra ")) {
                        return true
                    }
                } else if hasExplicitAmount || list.contains("dinero") || list.contains("ahorro") || list.contains("ahorros")
                    || list.contains("herencia") || joined.contains(" paga extra ") {
                    return true
                }
            }
            // «¿En qué meto 1.000 €?» / «¿Dónde pongo 1000 €?» (las cifras se quedan fuera de `list`).
            if (joined.contains(" en que ") || joined.contains(" donde "))
                && list.contains(where: { ["meto", "meter", "pongo", "poner"].contains($0) })
                && (hasExplicitAmount || hasMoneyCue || list.contains("ahorro") || list.contains("ahorros"))
                && !list.contains(where: { ownBankWords.contains($0) })
                && extractCategory(joined: joined) == nil {
                return true
            }
            // «¿Me quedo con Tesla?» / «¿Sigo en Tesla?» / «¿Sigo con Nvidia?»
            if (joined.contains(" me quedo con ") || joined.contains(" quedarme con ")
                || joined.contains(" sigo en ") || joined.contains(" sigo con "))
                && !list.contains(where: { ownBankWords.contains($0) })
                && extractCategory(joined: joined) == nil
                && fullMerchantIdx.isEmpty
                && (!externalProperNounsNotMerchant.isEmpty || hasInvestableCommodity) {
                return true
            }
            for (idx, word) in list.enumerated() where firstPersonDecisionVerbs.contains(word) || word == "paso" {
                if word == "entro" && hasPastEntroOnly { continue }
                if word == "aumento", idx > 0, ["el", "un", "del", "este", "ese", "su", "mi"].contains(list[idx - 1]) {
                    continue
                }
                if word == "liquido", rawAccentedLiquidoCount > 0
                    || (idx > 0 && ["dinero", "efectivo", "saldo"].contains(list[idx - 1])) {
                    continue
                }
                let after = Array(list[(idx + 1)...])
                guard !after.isEmpty else { continue }
                let afterJoined = " " + after.joined(separator: " ") + " "
                if after.contains(where: { ownBankWords.contains($0) }) { continue }
                if extractCategory(joined: afterJoined) != nil { continue }
                if after.indices.contains(where: { fullMerchantIdx.contains(idx + 1 + $0) }) { continue }
                let hasCommodityObject = after.enumerated().contains {
                    !fullMerchantIdx.contains(idx + 1 + $0.offset) && ($0.element == "oro" || $0.element == "gold")
                }
                if word == "paso" {
                    if hasCommodityObject { return true }
                    continue
                }
                let hasProperObject = after.contains { externalProperNounsNotMerchant.contains($0) }
                let hasAmountObject = hasExplicitAmount && after.contains(where: { !["en", "a", "por", "de", "con", "el", "la", "los", "las"].contains($0) })
                if hasProperObject || hasCommodityObject || hasAmountObject { return true }
            }
        }

        // (c) Valoración + nombre propio/oro; Predicción/Opinión + nombre propio externo/oro; elección «X o Y».
        if hasTwoAssetChoice { return true }
        if hasValuation && (!externalProperNounsNotBank.isEmpty || hasInvestableCommodity) { return true }
        if hasPrediction && (!externalProperNounsNotMerchant.isEmpty || hasInvestableCommodity) { return true }
        if opinionAboutAssetPhrases.contains(where: { joined.contains(" " + $0 + " ") })
            && (!externalProperNounsNotMerchant.isEmpty || hasInvestableCommodity) {
            return true
        }

        // (d) Dos W distintos + D, o condicional + espera de mercado (sin cobro/factura).
        if ctx.weakCount >= 2 && hasAnyDecisionMarker { return true }
        if hasConditional {
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
    for entry in spanishMonthNames {
        guard let idx = tokens.firstIndex(of: entry.name) else { continue }
        // U3 + N3: «octubre del año pasado» / «octubre año pasado» -> año actual - 1;
        // nunca cuando va tras una comparación («en octubre que el año pasado»).
        let tail = Array(tokens[(idx + 1)...])
        let lastYearModifiesMonth = tail.starts(with: ["del", "ano", "pasado"])
            || tail.starts(with: ["de", "el", "ano", "pasado"])
            || tail.starts(with: ["ano", "pasado"])
        if lastYearModifiesMonth {
            return .specific(year: currentYear - 1, month: entry.month)
        }
        // U3: un número de 4 cifras solo es año si va pegado al mes («octubre de 2025», «octubre 2025»); si no, se ignora.
        var adjacentYear: Int?
        if idx + 1 < tokens.count {
            let next = tokens[idx + 1]
            if next.count == 4, next.allSatisfy({ $0.isASCII && $0.isNumber }), let y = Int(next), (1000...9999).contains(y) {
                adjacentYear = y
            } else if next == "de", idx + 2 < tokens.count {
                let afterDe = tokens[idx + 2]
                if afterDe.count == 4, afterDe.allSatisfy({ $0.isASCII && $0.isNumber }), let y = Int(afterDe), (1000...9999).contains(y) {
                    adjacentYear = y
                }
            }
        }
        let year = adjacentYear ?? (entry.month > currentMonth ? currentYear - 1 : currentYear)
        return .specific(year: year, month: entry.month)
    }
    return .current
}

/// U3 + N2: comprueba sobre la pregunta original si pide un periodo por días/semanas/años no soportado.
func questionHasUnsupportedPeriod(_ question: String) -> Bool {
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
    let rawFolded = foldedQuery(trimmed)
    let tokens = rawFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return false }
    return hasUnsupportedPeriodCue(tokens: tokens, joined: " " + tokens.joined(separator: " ") + " ")
}

/// U3: periodo por días, semanas o años sin nombre de mes (no soportado para gasto/pagos/ingresos/traspasos).
private func hasUnsupportedPeriodCue(tokens: [String], joined: String) -> Bool {
    if joined.contains(" mes pasado ") || joined.contains(" mes anterior ") || joined.contains(" ultimo mes ")
        || joined.contains(" este mes ") { return false }
    if spanishMonthNames.contains(where: { tokens.contains($0.name) }) { return false }
    let phrases = ["esta semana", "la semana pasada", "semana pasada", "este ano", "el ano pasado", "ano pasado"]
    if phrases.contains(where: { joined.contains(" " + $0 + " ") }) { return true }
    return tokens.contains("hoy") || tokens.contains("ayer") || tokens.contains("anteayer")
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
    "pago", "pagos", "recibo", "recibos", "gasto", "gastos", "cargo", "cargos", "compra", "compras",
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
    // 1. Coincidencia con un comercio ya existente en los pagos del libro (gana la más larga; U2: también «Dia» y por dominio).
    var seenKeys = Set<String>()
    var known: [(key: String, display: String)] = []
    var hasDiaInLedger = false
    for m in state.movements where m.kind == .payment && !m.flaggedNotMine && !m.excludedFromSpending {
        for raw in [m.merchant, m.bankMerchant].compactMap({ $0 }) {
            let key = normalizeMerchant(raw)
            if key == "dia" || key.hasPrefix("dia ") { hasDiaInLedger = true }
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

    // U2 punto 4 + N4: «Dia»/«DIA» con mayúscula en la pregunta solo si no ganó antes un comercio conocido más largo.
    if hasDiaInLedger && category == nil {
        let rawWords = rawQuestion.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if let hit = rawWords.first(where: { ($0 == "Dia" || $0 == "DIA") }) {
            return hit
        }
    }

    // 1b. U2 punto 2: coincidencia por `merchantDomain(for:)` («Amazon» <-> «AMZN Mktp ES*2K4»).
    if category == nil {
        let knownDomains = Set(known.compactMap { merchantDomain(for: $0.display) })
        if !knownDomains.isEmpty {
            for tok in tokens where tok.count >= 3 && !nonMerchantTargets.contains(tok) && !categoryKeywordWords.contains(tok) {
                if let dom = merchantDomain(for: tok), knownDomains.contains(dom) {
                    return originalWordMatching(tok, in: rawQuestion)
                }
            }
        }
    }

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
    let leadingArticles: Set<String> = ["el", "la", "los", "las"]
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
        // U2 punto 1: el candidato pierde el artículo inicial («el», «la», «los», «las»): «en el coche» -> «coche».
        var candWords = candidate.split(separator: " ").map(String.init)
        while candWords.count > 1, let first = candWords.first, leadingArticles.contains(foldedQuery(first)) {
            candWords.removeFirst()
        }
        candidate = candWords.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
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

    let knownMerchants = ledgerMerchantKeys(in: state)
    let positionQuery = extractPositionQuery(tokens: tokens, joined: joined, portfolio: portfolio)

    // 0. Consejo de inversión: SIEMPRE primero (A3, U1).
    if isAdviceRequest(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) {
        return .adviceRequest(positionQuery: positionQuery)
    }

    return routeAssistantQuestionWithoutAdviceGate(question, state: state, portfolio: portfolio, now: now, calendar: calendar)
}

/// U69(a): resuelve la intención factual subyacente sin el freno de `isAdviceRequest`, para que la negativa nunca sustituya
/// a los datos reales que el dueño preguntó.
func routeAssistantQuestionWithoutAdviceGate(_ question: String, state: LedgerState, portfolio: Portfolio?,
                                             now: Date, calendar: Calendar) -> AssistantIntent {
    let trimmed = compatNormalized(question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .unknown }

    let rawFolded = foldedQuery(trimmed)
    let tokens = rawFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return .unknown }
    let joined = " " + tokens.joined(separator: " ") + " "
    let positionQuery = extractPositionQuery(tokens: tokens, joined: joined, portfolio: portfolio)

    let bank = extractBank(tokens: tokens, joined: joined)
    let month = extractMonth(tokens: tokens, joined: joined, rawFolded: rawFolded, now: now, calendar: calendar)
    let unsupportedPeriod = hasUnsupportedPeriodCue(tokens: tokens, joined: joined)
    let category = extractCategory(joined: joined)
    let passiveCharged = joined.contains(" han cobrado ") || joined.contains(" me cobraron ") || joined.contains(" me cobra ")
    let hasSpendingCue = tokens.contains { spendingCues.contains($0) } || passiveCharged
    let hasStrongShopCue = tokens.contains { strongShopSpendingCues.contains($0) }
    let hasAccentedBajo = withoutFormatCharacters(question).precomposedStringWithCanonicalMapping.lowercased().contains("bajó")

    // 1. Resumen («¿qué ha pasado desde ayer?»).
    if recapPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return .briefingRecap
    }

    // 1b. U1 punto 6: «Compra(s)» sola o con «este mes» / «el mes pasado» / mes -> categoría Compras.
    if isBareCategoryTradeQuery(tokens, joined: joined), let first = tokens.first,
       (first == "compra" || first == "compras") {
        return .spending(month: month, category: .compras, merchant: nil, bank: nil)
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
        return unsupportedPeriod ? .unsupportedPeriod : .ownTransfers(month: month)
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

    // 8. Ingresos («me han cobrado» / «han cobrado» / «me cobra» son pagos, nunca ingresos).
    let hasIncomeCue = tokens.contains { cue in
        if cue == "cobrado" && passiveCharged { return false }
        return incomeCues.contains(cue)
    }
    if hasIncomeCue || incomePhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return unsupportedPeriod ? .unsupportedPeriod : .income(month: month)
    }

    // 9. Mayores pagos.
    if biggestPaymentPhrases.contains(where: { joined.contains(" " + $0 + " ") }) {
        return unsupportedPeriod ? .unsupportedPeriod : .biggestPayments(month: month)
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
            let isOnlyLlevoWithoutShop = tokens.contains("llevo") && !hasStrongShopCue
                && !(matchedPositionName.map { hasKnownShopMerchant($0, in: state) } ?? false)
            if isGainQuery || !hasSpendingCue || isOnlyLlevoWithoutShop {
                return .investments(positionQuery: positionQuery, moversOnly: false)
            }
        }
    }

    // 12. Gastos (mes, categoría, comercio o banco; U3: hoy/ayer/semana/año -> .unsupportedPeriod).
    let merchant = extractMerchant(rawQuestion: trimmed, joined: joined, tokens: tokens, state: state,
                                   category: category, bank: bank)
    if hasSpendingCue {
        if unsupportedPeriod { return .unsupportedPeriod }
        return .spending(month: month, category: merchant == nil ? category : nil, merchant: merchant,
                         bank: bank)
    }
    if let merchant, joined.contains(" cuanto ") || joined.contains(" pagos ") {
        if unsupportedPeriod { return .unsupportedPeriod }
        return .spending(month: month, category: nil, merchant: merchant, bank: bank)
    }
    if let category, joined.contains(" cuanto ") || month != .current {
        if unsupportedPeriod { return .unsupportedPeriod }
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

/// Palabras interrogativas o verbos de consulta que nunca pueden elegirse como nombre de comercio desde el modelo (C2).
private let modelMerchantStopWords: Set<String> = [
    "cuanto", "cuanta", "cuantos", "cuantas", "gaste", "gastado", "gastar", "gasto", "gastos",
    "llevo", "pague", "pagado", "pagar", "pago", "pagos", "dinero", "saldo", "saldos",
    "donde", "cuando", "como", "quien", "cual", "cuales", "que",
]

/// Comprueba que el valor propuesto por el modelo aparece como una secuencia de palabras enteras dentro de `originalQuestion`,
/// sin caracteres añadidos ni símbolos prohibidos (ni en el valor ni en el tramo devuelto), no secuestra categorías ni palabras
/// interrogativas, y devuelve el trozo original de la pregunta (nunca el texto crudo del modelo) (C2, J21(d)).
func validatedSpanFromQuestion(_ modelValue: String, originalQuestion: String, rejectCategories: Bool = true,
                               knownMerchants: Set<String> = []) -> String? {
    func isSafeSpanText(_ s: String) -> Bool {
        !hasNonLatinScriptLetter(s)
            && !s.contains("€") && !s.contains("%") && !s.contains("$")
            && !s.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    guard isSafeSpanText(modelValue) else { return nil }
    let spanEdgePrepositions: Set<String> = ["en", "de", "del", "por", "para", "con", "a", "al", "sobre", "desde"]
    let rawNormValue = normalizeMerchant(modelValue)
    let rawValueTokens = rawNormValue.split(separator: " ").map(String.init)
    // U2 punto 5: recorta en ambos bordes tanto preposiciones como palabras de `nonMerchantTargets` («total en Mercadona» -> «Mercadona»).
    var valueTokens = rawValueTokens
    while let first = valueTokens.first, spanEdgePrepositions.contains(first) || nonMerchantTargets.contains(first) {
        valueTokens.removeFirst()
    }
    while let last = valueTokens.last, spanEdgePrepositions.contains(last) || nonMerchantTargets.contains(last) {
        valueTokens.removeLast()
    }
    // Si dentro del tramo queda un comercio conocido del libro (o su primer nombre), priorizamos ese comercio.
    if !knownMerchants.isEmpty && valueTokens.count > 1 {
        let joinedSpan = " " + valueTokens.joined(separator: " ") + " "
        var bestMatch: [String]?
        for key in knownMerchants {
            let kt = key.split(separator: " ").map(String.init)
            if !kt.isEmpty && joinedSpan.contains(" " + key + " ") && kt.count > (bestMatch?.count ?? 0) {
                bestMatch = kt
            } else if let first = kt.first, first.count >= 4, valueTokens.contains(first), (bestMatch?.count ?? 0) == 0 {
                bestMatch = [first]
            }
        }
        if let bestMatch { valueTokens = bestMatch }
    }
    let normValue = valueTokens.joined(separator: " ")
    guard normValue.count >= 2, !valueTokens.isEmpty,
          !valueTokens.allSatisfy({ nonMerchantTargets.contains($0) || merchantFillerWords.contains($0) || modelMerchantStopWords.contains($0) }),
          !valueTokens.contains(where: { modelMerchantStopWords.contains($0) }) else {
        return nil
    }
    if rejectCategories && extractCategory(joined: " " + normValue + " ") != nil {
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
    guard rawWords == rawValueTokens else { return nil }

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
            let candidate = qRaw[start..<(start + spanLen)].joined(separator: " ").precomposedStringWithCanonicalMapping
            if normalizeMerchant(candidate) == normValue && isSafeSpanText(candidate) {
                return candidate
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
public func parseAssistantModelRoute(_ response: String, originalQuestion: String, portfolio: Portfolio?,
                                     knownMerchants: Set<String> = []) -> AssistantIntent? {
    let originalFolded = foldedQuery(originalQuestion)
    let originalTokens = originalFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    let originalJoined = " " + originalTokens.joined(separator: " ") + " "

    // Barrera incondicional: el modelo nunca puede saltarse la negativa a dar consejos.
    if isAdviceRequest(originalQuestion, portfolio: portfolio, knownMerchants: knownMerchants) {
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
            } else if let safeSpan = validatedSpanFromQuestion(value, originalQuestion: originalQuestion, rejectCategories: false) {
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
                         bank: bank)
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
