import Foundation

/// Lo que se dice cuando alguien pide un consejo de inversión. La app describe, no recomienda.
public let investmentAdviceRefusal =
    "No puedo decirte qué comprar, vender o cuánto invertir: eso solo puede hacerlo un asesor financiero autorizado. Sí puedo contarte cómo van tus inversiones."

private func folded(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .lowercased()
}

// MARK: Capa (b): normalización

/// El texto sin ningún carácter de formato (`\p{Cf}`: guion blando, espacio de ancho cero, unión de ancho cero...).
func withoutFormatCharacters(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars where scalar.properties.generalCategory != .format { scalars.append(scalar) }
    return String(scalars)
}

private let letterCategories: Set<Unicode.GeneralCategory> = [
    .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
]

/// true si hay alguna letra fuera de la escritura latina (cualquier letra por encima de U+024F: cirílico, griego...). Una
/// «е» cirílica dentro de «vеnde» engañaría a las listas de palabras: la línea entera se rechaza.
func hasNonLatinLetter(_ text: String) -> Bool {
    withoutFormatCharacters(text).unicodeScalars.contains { $0.value > 0x24F && letterCategories.contains($0.properties.generalCategory) }
}

/// Las palabras de un texto (solo letras), sin mayúsculas ni tildes.
private func splitWords(_ text: String) -> [String] {
    folded(text).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
}

private let hyphens: [String] = ["-", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2212}"]

/// Las dos lecturas de un texto: sus palabras tal cual y sus palabras con los guiones y saltos de línea quitados (una palabra
/// partida «ven-\nde» o «ven\nde» vuelve a ser «vende»). Se mira cada una; basta que una marque.
func wordReadings(_ text: String) -> [[String]] {
    let clean = withoutFormatCharacters(text)
    var joined = clean
    for hyphen in hyphens { joined = joined.replacingOccurrences(of: hyphen, with: "") }
    joined = joined.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    let plain = splitWords(clean), merged = splitWords(joined)
    return plain == merged ? [plain] : [plain, merged]
}

// MARK: Capa (c): vocabulario de inversiones

/// Principios de palabra de inversiones: la línea se rechaza digan lo que digan el resto de palabras.
private let investmentPrefixes = [
    "invers", "invert", "inviert", "invirt", "accion", "cartera", "fondo", "bolsa", "posicion", "exposicion", "beneficio",
    "perdida", "cotiz", "dividend", "valor", "precio", "etf", "cripto", "bitcoin", "broker", "stock", "share", "market", "fund",
    "portfolio", "profit", "crypto", "asset", "holding", "invest",
]

/// «mercado» solo entero: «Mercadona» no es vocabulario de inversiones.
private let investmentWords: Set<String> = ["mercado", "mercados"]

func hasInvestmentVocabulary(_ text: String) -> Bool {
    wordReadings(text).contains { list in
        list.contains { word in investmentWords.contains(word) || investmentPrefixes.contains { word.hasPrefix($0) } }
    }
}

// MARK: Capa (d): marcadores de consejo

/// Palabras enteras que marcan un consejo.
private let adviceWords: Set<String> = [
    "conviene", "convienen", "deberias", "deberia", "debes", "should", "hold", "holds", "holding", "buy", "buys", "buying", "sell",
    "sells", "selling", "quedate", "tendrias", "podrias", "stay", "better",
]

/// Principios de palabra que marcan un consejo (cualquier forma de la palabra).
private let advicePrefixes = [
    "recomiend", "recomend", "aconsej", "suger", "sugier", "aprovech", "manten", "mantien", "mantuv", "aguant", "diversific",
    "reequilibr", "compr", "vend", "recommend", "mejor", "esper", "aguard", "convendr", "tendri", "debe", "debier", "considera",
    "consider", "plantea", "deshaz", "acumul", "promedi", "reduc", "refuerz", "reforz", "toma", "evita", "avoid", "procura",
    "intenta", "wait",
]

/// Frases (palabras seguidas) que marcan un consejo.
private let advicePhrases = [
    "tienes que", "hay que", "habria que", "yo que tu", "yo de ti", "buen momento", "el momento de", "es hora de", "buena idea",
    "vale la pena", "merece la pena", "sal de", "entra en", "get out", "take profit", "take profits",
]

// MARK: Capa (e): compra y venta como sustantivos

/// Formas que describen lo ya hecho: no aconsejan nada.
private let describingWords: Set<String> = [
    "comprado", "comprada", "comprados", "compradas", "compraste", "vendido", "vendida", "vendidos", "vendidas", "vendiste",
]

/// «compra», «compras», «venta», «ventas»: sustantivo solo justo detrás de un determinante (o «Venta de…» al empezar); en
/// cualquier otro sitio son el verbo y aconsejan.
private let tradeNouns: Set<String> = ["compra", "compras", "venta", "ventas"]

private let determiners: Set<String> = [
    "tu", "tus", "la", "las", "una", "unas", "esa", "esas", "mi", "mis", "su", "sus", "de", "cada", "ultima", "primera",
]

private func hasAdviceMarker(_ list: [String]) -> Bool {
    for word in list where !describingWords.contains(word) {
        if tradeNouns.contains(word) { continue }
        if adviceWords.contains(word) || advicePrefixes.contains(where: { word.hasPrefix($0) }) { return true }
    }
    let joined = " " + list.joined(separator: " ") + " "
    return advicePhrases.contains { joined.contains(" " + $0 + " ") }
}

private func hasTradeVerb(_ list: [String]) -> Bool {
    for (i, word) in list.enumerated() where tradeNouns.contains(word) {
        if i > 0, determiners.contains(list[i - 1]) { continue }
        if i == 0, i + 1 < list.count, list[i + 1] == "de" { continue }
        return true
    }
    return false
}

func hasAdviceMarker(_ text: String) -> Bool { wordReadings(text).contains(where: hasAdviceMarker) }

func hasTradeVerb(_ text: String) -> Bool { wordReadings(text).contains(where: hasTradeVerb) }

/// true si el texto parece aconsejar o hablar de inversiones. En capas, por este orden: (b) letras de otra escritura (se
/// rechaza la línea), (c) vocabulario de inversiones, (d) marcadores de consejo y (e) compra/venta como verbo. Ante la duda
/// rechaza: un falso positivo solo hace que se enseñe la frase de las reglas.
public func containsAdvice(_ text: String) -> Bool {
    if hasNonLatinLetter(text) { return true }
    if hasInvestmentVocabulary(text) { return true }
    if hasAdviceMarker(text) { return true }
    return hasTradeVerb(text)
}

/// true si el texto dice qué comprar, vender o cuánto invertir (ver `containsAdvice`).
public func containsInvestmentAdvice(_ text: String) -> Bool { containsAdvice(text) }

// MARK: Cifras

/// Palabras que son un número (en español y en inglés). «un», «uno» y «una» son artículos y no están.
private let numberWords: Set<String> = [
    "cero", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce", "trece", "catorce", "quince",
    "dieciseis", "diecisiete", "dieciocho", "diecinueve", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta",
    "ochenta", "noventa", "cien", "ciento", "cientos", "cientas", "quinientos", "quinientas", "mil", "millon", "millones", "medio",
    "media", "mitad", "doble", "triple", "double",
    "par", "pares", "docena", "docenas", "decena", "decenas", "centenar", "centenares", "millar", "millares", "billon", "billones",
    "cuarto", "cuartos", "tercio", "tercios", "quinto", "quintos",
    "zero", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
    "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty",
    "ninety", "hundred", "thousand", "million", "half",
    "dozen", "dozens", "couple", "couples", "pair", "pairs", "billion", "billions", "quarter", "quarters", "third", "thirds", "percent",
]

/// true si el texto lleva un número: cualquier carácter numérico (cifras, fracciones, otros alfabetos), una palabra que lo es
/// (dos, veinticinco, quinientos, mil, medio, doble, docena, two, hundred, half...) o un número romano en mayúsculas (II, XIV).
public func containsNumber(_ text: String) -> Bool {
    let clean = withoutFormatCharacters(text)
    let numeric: Set<Unicode.GeneralCategory> = [.decimalNumber, .letterNumber, .otherNumber]
    if clean.unicodeScalars.contains(where: { numeric.contains($0.properties.generalCategory) }) { return true }
    // Un número romano se mira en el texto original (en mayúsculas): «mi» y «di» no lo son, «MI» y «XIV» sí.
    let tokens = clean.components(separatedBy: CharacterSet.letters.inverted)
    if tokens.contains(where: { $0.range(of: "^[IVXLCDM]{2,}$", options: .regularExpression) != nil }) { return true }
    return wordReadings(text).contains { list in
        list.contains { word in
            numberWords.contains(word) || word.hasPrefix("veinti") || word.hasSuffix("cientos") || word.hasSuffix("cientas")
        }
    }
}

/// Lo más largo que puede ser la frase de un modelo.
let maxModelIntroLength = 300

/// Un texto de un modelo solo se enseña si no está vacío, cabe, no lleva enlaces, NO lleva ningún número (las cifras viven en
/// la frase de las reglas que se enseña debajo) y no aconseja ni habla de inversiones. Si no, se usa la frase de las reglas.
/// `facts` no sirve para dar por buena nada: se conserva por compatibilidad con quien llama. Solo `openingLine` es pública.
func acceptModelIntro(_ text: String, facts: [String]) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= maxModelIntroLength else { return false }
    let lower = trimmed.lowercased()
    guard !lower.contains("http"), !lower.contains("://"), !lower.contains("www.") else { return false }
    return !containsNumber(trimmed) && !containsAdvice(trimmed)
}

/// La frase que abre el resumen. Con el modo privado, siempre la de las reglas con los importes tapados (el texto de un modelo
/// nunca sale en ese modo). Si no, el texto del modelo cuando existe y pasa las dos barreras (cifras y consejos); si no, la de
/// las reglas.
public func openingLine(briefing: Briefing, modelText: String?, facts: [String], privateMode: Bool) -> String {
    if privateMode { return render(briefing.headline, .masked) }
    if let modelText, acceptModelIntro(modelText, facts: facts) {
        return modelText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return render(briefing.headline, .plain)
}

public let briefingModelInstructions =
    "Eres el asistente de Mi Banco que saluda al dueño por la mañana. Escribe el saludo en una o dos frases, de tú, con un tono cálido y tranquilo. No escribas ninguna cifra ni ningún número, ni con dígitos ni con letras: las cifras se enseñan debajo. Nunca digas qué comprar, vender ni cuánto invertir. No añadas nada que no esté en los datos."

/// Lo más largo que puede ser el mensaje al modelo y cuántos hechos lleva.
private let maxPromptLength = 2500
private let maxPromptFacts = 25

/// El mensaje al modelo. Se arma con los hechos SIN las líneas de inversiones: el modelo nunca se entera de ellas.
public func briefingModelPrompt(_ briefing: Briefing) -> String {
    let head = "Datos:\n"
    let tail = "\nEscribe el saludo."
    var body = ""
    for fact in briefingModelFacts(briefing).prefix(maxPromptFacts) {
        let next = (body.isEmpty ? "" : "\n") + "- " + fact
        if (head + body + next + tail).count > maxPromptLength { break }
        body += next
    }
    return head + body + tail
}
