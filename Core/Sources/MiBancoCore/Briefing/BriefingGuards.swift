import Foundation

/// Lo que se dice cuando alguien pide un consejo de inversión. La app describe, no recomienda.
public let investmentAdviceRefusal =
    "No puedo decirte qué comprar, vender o cuánto invertir: eso solo puede hacerlo un asesor financiero autorizado. Sí puedo contarte cómo van tus inversiones."

private func folded(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .replacingOccurrences(of: "\u{00A0}", with: " ")
}

private let advicePattern = [
    "te recomiendo (comprar|vender|invertir|mantener)",
    "te aconsejo (comprar|vender|invertir|mantener)",
    "te sugiero (comprar|vender|invertir|mantener)",
    "deberias (comprar|vender|invertir|mantener|diversificar)",
    "podrias (comprar|vender|invertir)",
    "considera (comprar|vender|invertir)",
    "compra mas",
    "vende ",
    "invierte en",
    "mi recomendacion es",
    "buen momento para (comprar|vender|entrar|invertir)",
].joined(separator: "|")

/// true si el texto dice qué comprar, vender o cuánto invertir (sin mirar mayúsculas ni tildes).
public func containsInvestmentAdvice(_ text: String) -> Bool {
    folded(text).range(of: advicePattern, options: .regularExpression) != nil
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

/// Un texto de un modelo solo se enseña si no está vacío, cabe, no lleva enlaces, cada número está en los hechos y no
/// aconseja sobre inversiones. Si no, se usa la frase de las reglas.
public func acceptModelIntro(_ text: String, facts: [String]) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= maxModelIntroLength else { return false }
    let lower = trimmed.lowercased()
    guard !lower.contains("http"), !lower.contains("://"), !lower.contains("www.") else { return false }
    return numbersAreGrounded(trimmed, in: facts) && !containsInvestmentAdvice(trimmed)
}

public let briefingModelInstructions =
    "Eres el asistente de Mi Banco que saluda al dueño por la mañana. Escribe el saludo en una o dos frases, de tú, con un tono cálido y tranquilo. Usa solo las cifras que aparecen en los datos. Nunca digas qué comprar, vender ni cuánto invertir. No añadas nada que no esté en los datos."

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
