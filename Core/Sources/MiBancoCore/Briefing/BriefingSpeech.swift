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

        public init(id: String, range: Range<Int>) {
            self.id = id
            self.range = range
        }
    }
    public let text: String
    public let lines: [Line]

    public init(text: String, lines: [Line]) {
        self.text = text
        self.lines = lines
    }

    /// La línea que suena cuando la voz va por la posición `offset` (UTF-16) del texto; nil entre líneas o fuera.
    public func line(at offset: Int) -> String? {
        lines.first { $0.range.contains(offset) }?.id
    }

    /// Lo que lee de verdad la voz: el texto sin los espacios del principio y del final, con los rangos corregidos (el
    /// motor da posiciones del texto que lee). Una línea que quedara fuera se recorta al texto.
    public func trimmed() -> SpokenBriefing {
        let lead = text.utf16.count - text.drop(while: { $0.isWhitespace }).utf16.count
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = body.utf16.count
        let shifted = lines.compactMap { line -> Line? in
            let lower = max(0, line.range.lowerBound - lead), upper = min(count, line.range.upperBound - lead)
            return lower < upper ? Line(id: line.id, range: lower..<upper) : nil
        }
        return SpokenBriefing(text: body, lines: shifted)
    }
}

/// Lote final (privacidad de la voz): por qué ha cambiado la salida de audio, con los mismos casos que
/// `AVAudioSession.RouteChangeReason` (Core no importa AVFoundation).
public enum AudioRouteChange: Equatable, Sendable {
    case unknown, newDeviceAvailable, oldDeviceUnavailable, categoryChange, override, wakeFromSleep
    case noSuitableRouteForCategory, routeConfigurationChange

    /// El valor bruto de `AVAudioSession.RouteChangeReason`.
    public init(rawReason: UInt) {
        switch rawReason {
        case 1: self = .newDeviceAvailable
        case 2: self = .oldDeviceUnavailable
        case 3: self = .categoryChange
        case 4: self = .override
        case 6: self = .wakeFromSleep
        case 7: self = .noSuitableRouteForCategory
        case 8: self = .routeConfigurationChange
        default: self = .unknown
        }
    }

    /// La voz que lee saldos se para (y no vuelve sola) cuando la salida pasa a ser menos privada: se desconectan los
    /// auriculares (`oldDeviceUnavailable`), la salida se fuerza al altavoz (`override`) o ya no hay una salida válida.
    /// Conectar unos auriculares o un cambio de configuración no la paran.
    public var stopsSpeech: Bool {
        switch self {
        case .oldDeviceUnavailable, .override, .noSuitableRouteForCategory: true
        case .unknown, .newDeviceAvailable, .categoryChange, .wakeFromSleep, .routeConfigurationChange: false
        }
    }
}

/// Ronda 2 (N-4): por dónde sale el audio (los mismos grupos que `AVAudioSession.Port`, sin AVFoundation).
public enum AudioOutputKind: Equatable, Sendable {
    /// Auriculares con cable.
    case headphones
    /// El auricular del propio teléfono (pegado a la oreja).
    case receiver
    /// El altavoz del teléfono.
    case speaker
    /// Bluetooth (no se distingue unos auriculares de un altavoz), el coche, AirPlay, HDMI u otro.
    case bluetooth, car, airPlay, other

    /// Una salida privada: solo la oye quien la lleva puesta.
    public var isPrivate: Bool { self == .headphones || self == .receiver }
}

/// Ronda 2 (N-4, privacidad): la voz que lee saldos se para (y no vuelve sola) si la salida deja de ser privada o se
/// abre a otros: se desconectan los auriculares, se fuerza el altavoz, ya no hay salida, o aparece una salida nueva
/// que no es privada (un altavoz Bluetooth, el coche, AirPlay…, también unos auriculares Bluetooth, que no se pueden
/// distinguir de un altavoz). Si sigue saliendo por lo mismo de antes, no se para.
public func speechStops(_ change: AudioRouteChange, previous: [AudioOutputKind], current: [AudioOutputKind]) -> Bool {
    if change.stopsSpeech { return true }
    // N-12: el altavoz solo se exime si la salida de antes tampoco era privada (de auriculares al altavoz, se para).
    let wasPrivate = previous.contains(where: \.isPrivate)
    return current.contains { !$0.isPrivate && !previous.contains($0) && ($0 != .speaker || wasPrivate) }
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
