import Foundation

private func spoken(_ text: String) -> String {
    var s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
    s = s.replacingOccurrences(of: "\\+(?=[0-9])", with: "más ", options: .regularExpression)
    s = s.replacingOccurrences(of: "-(?=[0-9])", with: "menos ", options: .regularExpression)
    s = s.replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
    s = s.replacingOccurrences(of: " · ", with: ". ")
    s = s.replacingOccurrences(of: "%", with: "por ciento").replacingOccurrences(of: "€", with: "euros")
    return s
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

/// Lo que lee la voz. Con el modo privado no dice ningún importe: solo cuántas cosas han pasado y cuántos cobros vienen.
/// Sin modo privado lee la frase principal y las líneas del resumen con los símbolos dichos en palabras.
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
        if counts.isEmpty {
            let quiet = quietPeriodPhrase(since: input.since, now: input.now, isFirst: input.isFirst, calendar: calendar)
            sentences.append("Nada nuevo \(quiet).")
        } else {
            sentences.append("\(period): \(join(counts)).")
        }
        let charges = input.upcoming.count
        if charges > 0 {
            sentences.append(charges == 1 ? "Esta semana viene 1 cobro." : "Esta semana vienen \(charges) cobros.")
        }
        return sentences.joined(separator: " ")
    }
    sentences.append(render(briefing.headline, .plain))
    for section in briefing.sections {
        for line in section.lines { sentences.append(sentence(spoken(render(line.parts, .plain)))) }
    }
    if let tip = briefing.tip { sentences.append(sentence(spoken(render(tip.parts, .plain)))) }
    return sentences.joined(separator: " ")
}
