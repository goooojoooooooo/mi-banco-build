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
    return spokenBriefingLines(briefing, input: input, privateMode: false, calendar: calendar).text
}

/// Lo que lee la voz (el MISMO texto que `spokenBriefing`, palabra por palabra) y, para cada línea del resumen que se
/// lee, dónde está dentro de ese texto: `range` en unidades UTF-16 (las que da el motor de voz al ir leyendo). Así se
/// puede resaltar la línea que suena con el progreso real de la voz. Con el modo privado no hay líneas: la voz no lee
/// ninguna línea del resumen (solo cuenta cosas), así que no se resalta nada.
public struct SpokenBriefing: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// `BriefingLine.id` de la línea (la frase principal es "headline").
        public let id: String
        public let range: Range<Int>
    }
    public let text: String
    public let lines: [Line]

    /// La línea que suena cuando la voz va por la posición `offset` (UTF-16) del texto; nil entre líneas o fuera.
    public func line(at offset: Int) -> String? {
        lines.first { $0.range.contains(offset) }?.id
    }
}

public func spokenBriefingLines(_ briefing: Briefing, input: BriefingInput, privateMode: Bool, calendar: Calendar) -> SpokenBriefing {
    if privateMode {
        return SpokenBriefing(text: spokenBriefing(briefing, input: input, privateMode: true, calendar: calendar), lines: [])
    }
    var names = (input.income + input.payments).map(\.name) + input.upcoming.map(\.name) + input.shortfalls.map(\.charge.name)
    if let expected = input.expected { names.append(expected.name) }
    names += (input.investments?.positions ?? []).map(\.position.name)
    var pieces: [(id: String?, text: String)] = [(nil, briefing.greeting + ".")]
    pieces.append(("headline", render(briefing.headline, .plain)))
    for section in briefing.sections {
        for line in section.lines { pieces.append((line.id, sentence(spoken(render(line.parts, .plain), keeping: names)))) }
    }
    if let tip = briefing.tip { pieces.append((tip.id, sentence(spoken(render(tip.parts, .plain), keeping: names)))) }
    var text = ""
    var lines: [SpokenBriefing.Line] = []
    for (index, piece) in pieces.enumerated() {
        if index > 0 { text += " " }
        let start = text.utf16.count
        text += piece.text
        if let id = piece.id { lines.append(.init(id: id, range: start..<text.utf16.count)) }
    }
    return SpokenBriefing(text: text, lines: lines)
}

/// Texto hablado en modo privado (U36): sustituye importes, porcentajes y «•••» por «importe oculto».
public func privateSpokenText(_ maskedText: String) -> String {
    var out = maskedText.replacingOccurrences(
        of: "[+\\-\u{2212}]?[0-9][0-9.,]*[ \u{00A0}\u{202F}]*(?:€|%)",
        with: "importe oculto",
        options: .regularExpression
    )
    out = out.replacingOccurrences(of: "•+", with: "importe oculto", options: .regularExpression)
    out = out.replacingOccurrences(of: "€", with: "importe oculto")
    out = out.replacingOccurrences(of: "%", with: "importe oculto")
    return out
}
