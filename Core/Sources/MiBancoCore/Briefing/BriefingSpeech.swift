import Foundation

private func spoken(_ text: String) -> String {
    var s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
    s = s.replacingOccurrences(of: "\\+(?=[0-9])", with: "más ", options: .regularExpression)
    s = s.replacingOccurrences(of: "-(?=[0-9])", with: "menos ", options: .regularExpression)
    s = s.replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
    s = s.replacingOccurrences(of: "\u{2212}(?=[0-9])", with: "menos ", options: .regularExpression)
    s = s.replacingOccurrences(of: " · ", with: ". ")
    s = s.replacingOccurrences(of: "%", with: "por ciento").replacingOccurrences(of: "€", with: "euros")
    return s
}

/// `spoken` sin tocar los nombres de comercio de dentro del texto («Gym +24 %» se lee como se escribe): se cambian por una marca
/// que las reglas no tocan y se devuelven después.
private func spoken(_ text: String, keeping names: [String]) -> String {
    var protected = text
    var kept: [(token: String, name: String)] = []
    for name in Set(names.flatMap { [$0, clippedName($0)] }).filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
        guard protected.contains(name) else { continue }
        let token = "\u{E000}\(kept.count)\u{E001}"
        protected = protected.replacingOccurrences(of: name, with: token)
        kept.append((token, name))
    }
    var result = spoken(protected)
    for item in kept { result = result.replacingOccurrences(of: item.token, with: item.name) }
    return result
}

private func sentence(_ text: String) -> String {
    guard let last = text.last else { return text }
    return ".!?".contains(last) ? text : text + "."
}

private func join(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    default: return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
    }
}

/// Lo que lee la voz. Con el modo privado no dice ningún importe: solo cuántas cosas han pasado, qué bancos dan problemas y
/// cuántos cobros vienen. Sin modo privado lee la frase principal y las líneas del resumen con los símbolos dichos en palabras.
public func spokenBriefing(_ briefing: Briefing, input: BriefingInput, privateMode: Bool, calendar: Calendar) -> String {
    var sentences = [briefing.greeting + "."]
    if privateMode {
        sentences.append("Tienes el modo privado activado, así que no leo importes.")
        let period = periodPhrase(since: input.since, now: input.now, isFirst: input.isFirst, calendar: calendar)
        var counts: [String] = []
        if !input.income.isEmpty { counts.append("\(input.income.count) \(input.income.count == 1 ? "ingreso" : "ingresos")") }
        if !input.payments.isEmpty { counts.append("\(input.payments.count) \(input.payments.count == 1 ? "pago" : "pagos")") }
        if !input.transfers.isEmpty {
            counts.append("\(input.transfers.count) \(input.transfers.count == 1 ? "traspaso" : "traspasos") entre tus cuentas")
        }
        let problems = bankProblemBanks(input)
        if counts.isEmpty {
            if problems.isEmpty {
                let quiet = quietPeriodPhrase(since: input.since, now: input.now, isFirst: input.isFirst, calendar: calendar)
                sentences.append("Nada nuevo \(quiet).")
            } else {
                sentences.append(nothingNewUnreadable)
            }
        } else {
            sentences.append("\(period): \(join(counts)).")
        }
        if !problems.isEmpty {
            sentences.append("Hay \(problems.count) \(problems.count == 1 ? "aviso" : "avisos"): \(join(problems.map(\.displayName))).")
        }
        let charges = input.upcoming.count
        if charges > 0 {
            sentences.append(charges == 1 ? "Esta semana viene 1 cobro." : "Esta semana vienen \(charges) cobros.")
        }
        return sentences.joined(separator: " ")
    }
    var names = (input.income + input.payments).map(\.name) + input.upcoming.map(\.name) + input.shortfalls.map(\.charge.name)
    if let expected = input.expected { names.append(expected.name) }
    names += (input.investments?.positions ?? []).map(\.position.name)
    sentences.append(render(briefing.headline, .plain))
    for section in briefing.sections {
        for line in section.lines { sentences.append(sentence(spoken(render(line.parts, .plain), keeping: names))) }
    }
    if let tip = briefing.tip { sentences.append(sentence(spoken(render(tip.parts, .plain), keeping: names))) }
    return sentences.joined(separator: " ")
}

/// Texto hablado en modo privado (U36): sustituye importes, porcentajes y «•••» por «importe oculto».
public func privateSpokenText(_ maskedText: String) -> String {
    var out = maskedText.replacingOccurrences(
        of: #"[+\-\u{2212}]?[0-9][0-9.,]*[ \u{00A0}\u{202F}]*(?:€|%)"#,
        with: "importe oculto",
        options: .regularExpression
    )
    out = out.replacingOccurrences(of: "•+", with: "importe oculto", options: .regularExpression)
    out = out.replacingOccurrences(of: "€", with: "importe oculto")
    out = out.replacingOccurrences(of: "%", with: "importe oculto")
    return out
}
