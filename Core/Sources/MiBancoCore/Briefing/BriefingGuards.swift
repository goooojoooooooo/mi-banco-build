import Foundation

/// Lo que se dice cuando alguien pide un consejo de inversión. La app describe, no recomienda.
public let investmentAdviceRefusal =
    "No puedo decirte qué comprar, vender o cuánto invertir: eso solo puede hacerlo un asesor financiero autorizado. Sí puedo contarte cómo van tus inversiones."

private func folded(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .lowercased()
}

/// Las palabras de un texto (solo letras), sin mayúsculas ni tildes.
private func words(_ text: String) -> [String] {
    folded(text).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
}

// MARK: Consejos

/// Palabras enteras que marcan un consejo.
private let adviceWords: Set<String> = [
    "conviene", "convienen", "deberias", "deberia", "debes", "should", "hold", "holds", "holding", "buy", "buys", "buying", "sell",
    "sells", "selling",
]

/// Principios de palabra que marcan un consejo (cualquier forma de la palabra).
private let advicePrefixes = [
    "recomiend", "recomend", "aconsej", "suger", "sugier", "aprovech", "invert", "inviert", "invirt", "manten", "mantien",
    "mantuv", "aguant", "diversific", "reequilibr", "compr", "vend", "invest", "recommend",
]

/// Formas que describen lo ya hecho o son sustantivos: no aconsejan nada.
private let describingWords: Set<String> = [
    "comprado", "comprada", "comprados", "compradas", "compraste", "vendido", "vendida", "vendidos", "vendidas", "vendiste",
    "invertido", "invertida", "invertidos", "invertidas", "invertiste", "compra", "compras", "venta", "ventas", "inversion",
    "inversiones",
]

/// Frases (palabras seguidas) que marcan un consejo.
private let advicePhrases = [
    "tienes que", "hay que", "yo que tu", "yo de ti", "buen momento", "el momento de", "es hora de", "buena idea", "vale la pena",
    "merece la pena",
]

/// true si el texto parece aconsejar: qué comprar, vender, mantener, cuánto invertir, o un «deberías», «hay que», «buen
/// momento»... Se mira palabra entera, sin mayúsculas ni tildes. Ante la duda rechaza: un falso positivo solo hace que se
/// enseñe la frase de las reglas.
public func containsAdvice(_ text: String) -> Bool {
    let list = words(text)
    for word in list where !describingWords.contains(word) {
        if adviceWords.contains(word) { return true }
        if advicePrefixes.contains(where: { word.hasPrefix($0) }) { return true }
    }
    // «Compra más…» al empezar una frase es una orden; «tu compra más cara» (sustantivo) no lo es.
    if folded(text).range(of: "(^|[.!?;:¡¿\\n])\\s*compra\\b", options: .regularExpression) != nil { return true }
    let joined = " " + list.joined(separator: " ") + " "
    return advicePhrases.contains { joined.contains(" " + $0 + " ") }
}

/// true si el texto dice qué comprar, vender o cuánto invertir (ver `containsAdvice`).
public func containsInvestmentAdvice(_ text: String) -> Bool { containsAdvice(text) }

// MARK: Cifras

/// Palabras que son un número (en español y en inglés). «un», «uno» y «una» son artículos y no están.
private let numberWords: Set<String> = [
    "cero", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce", "trece", "catorce", "quince",
    "dieciseis", "diecisiete", "dieciocho", "diecinueve", "veinte", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta",
    "ochenta", "noventa", "cien", "ciento", "cientos", "cientas", "quinientos", "quinientas", "mil", "millon", "millones", "medio", "media", "mitad", "doble",
    "triple",
    "zero", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
    "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty",
    "ninety", "hundred", "thousand", "million", "half",
]

/// true si el texto lleva un número: cualquier carácter numérico (cifras, fracciones, otros alfabetos) o una palabra que lo es
/// (dos, veinticinco, quinientos, mil, medio, doble, two, hundred, half...).
public func containsNumber(_ text: String) -> Bool {
    let numeric: Set<Unicode.GeneralCategory> = [.decimalNumber, .letterNumber, .otherNumber]
    if text.unicodeScalars.contains(where: { numeric.contains($0.properties.generalCategory) }) { return true }
    return words(text).contains { word in
        numberWords.contains(word) || word.hasPrefix("veinti") || word.hasSuffix("cientos") || word.hasSuffix("cientas")
    }
}

private let numberPattern = "[0-9][0-9.,]*[0-9]|[0-9]"

private func numberTokens(_ text: String) -> [String] {
    var tokens: [String] = []
    var search = text.startIndex..<text.endIndex
    while let range = text.range(of: numberPattern, options: .regularExpression, range: search) {
        tokens.append(String(text[range]))
        search = range.upperBound..<text.endIndex
    }
    return tokens
}

/// true si cada número del texto es, escrito igual, un número de los hechos. Un texto sin números cumple.
public func numbersAreGrounded(_ text: String, in facts: [String]) -> Bool {
    let known = Set(numberTokens(facts.joined(separator: "\n").replacingOccurrences(of: "\u{00A0}", with: " ")))
    return numberTokens(text.replacingOccurrences(of: "\u{00A0}", with: " ")).allSatisfy { known.contains($0) }
}

/// Lo más largo que puede ser la frase de un modelo.
let maxModelIntroLength = 300

/// Un texto de un modelo solo se enseña si no está vacío, cabe, no lleva enlaces, NO lleva ningún número (las cifras viven en
/// la frase de las reglas que se enseña debajo) y no aconseja. Si no, se usa la frase de las reglas. `facts` ya no sirve para
/// dar por buena una cifra: se conserva por compatibilidad con quien llama.
public func acceptModelIntro(_ text: String, facts: [String]) -> Bool {
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

public func briefingModelPrompt(_ briefing: Briefing) -> String {
    let head = "Datos:\n"
    let tail = "\nEscribe el saludo."
    var body = ""
    for fact in briefingFacts(briefing).prefix(maxPromptFacts) {
        let next = (body.isEmpty ? "" : "\n") + "- " + fact
        if (head + body + next + tail).count > maxPromptLength { break }
        body += next
    }
    return head + body + tail
}
