import Foundation

/// Cabecera de «la cosa a tener en cuenta» en la puesta al día de Nyx (diseño §6.7).
public let nyxFocusHeader = "Para tener en cuenta"

/// Instrucciones del modelo del iPhone para elegir cuál de las candidatas (máximo 3) destacar hoy.
public let nyxFocusInstructions =
    "Eres \(assistantName), el asistente de \(appDisplayName). Te doy varias situaciones numeradas del día. Elige la que más merece destacarse hoy y responde solo con su número. No escribas nada más."

/// El resumen de cada mañana como Nyx: también en los días tranquilos enseña cada banco y todos los cobros próximos.
public func makeNyxBriefing(_ input: BriefingInput, calendar: Calendar) -> Briefing {
    buildBriefing(input, calendar: calendar, fullLists: true)
}

extension NyxSituation {
    /// Etiqueta en palabras para el modelo del dispositivo: sin cifras, bancos, comercios ni vocabulario de inversión.
    public var promptLabel: String {
        switch self {
        case .unusualPayment: "un pago poco habitual"
        case .largePayment: "un pago grande"
        case .duplicateCharge: "un cobro repetido"
        case .subscriptionUp: "una suscripción que sube"
        case .subscriptionDown: "una suscripción que baja"
        case .budgetNear: "un presupuesto cerca del límite"
        case .budgetExceeded: "un presupuesto superado"
        case .salary: "la llegada de la nómina"
        case .largeIncome: "un ingreso grande"
        case .lowBalance: "saldo bajo en una cuenta"
        case .shortfall: "un cobro que no cabe"
        case .budgetOffPace: "un presupuesto que va rápido"
        case .categoryAboveNormal: "gasto por encima de lo habitual en una categoría"
        case .bankExpired: "una conexión de banco caducada"
        case .bankExpiring: "una conexión de banco que caduca pronto"
        case .bankStale: "un banco sin actualizar"
        case .alertsSilent: "avisos que han dejado de llegar"
        case .alertsNeverArrived: "avisos que aún no llegan"
        case .notificationsOff: "los avisos de la app apagados"
        case .appExpiring: "la app caduca"
        case .suggestMute: "silenciar avisos de un comercio"
        case .suggestAlertOff: "apagar un tipo de aviso"
        }
    }
}

private let nyxFocusWindowSeconds: TimeInterval = 7 * 86_400

/// Hasta tres candidatas para «Para tener en cuenta» (diseño §6.6): las observaciones de esta apertura más las entradas
/// `nueva`/`vista` de los últimos 7 días, quitando las descartadas/hechas y lo que ya sale en «Ojo con esto».
public func nyxFocusCandidates(current: [NyxObservation], memory: NyxMemory, briefing: Briefing,
                               input: BriefingInput, now: Date) -> [NyxObservation] {
    let cutoff = now.addingTimeInterval(-nyxFocusWindowSeconds)
    let resolvedIDs = Set(memory.entries.filter { $0.status == .dismissed || $0.status == .done }.map(\.id))

    var attentionBanks = Set(bankProblemBanks(input))
    for case .consentExpiring(let bank, _) in input.attention {
        attentionBanks.insert(bank)
    }

    var pool: [NyxObservation] = []
    var seen = Set<String>()

    func consider(_ obs: NyxObservation) {
        guard !resolvedIDs.contains(obs.id), seen.insert(obs.id).inserted else { return }
        if obs.situation == .budgetExceeded { return }
        if (obs.situation == .bankExpired || obs.situation == .bankExpiring || obs.situation == .bankStale),
           let bank = obs.facts.bank, attentionBanks.contains(bank) {
            return
        }
        pool.append(obs)
    }

    for obs in current { consider(obs) }
    for entry in memory.entries where entry.status == .new || entry.status == .seen {
        guard entry.observation.observedAt >= cutoff, entry.observation.observedAt <= now else { continue }
        consider(entry.observation)
    }

    let sorted = pool.sorted { a, b in
        if a.priority != b.priority { return a.priority < b.priority }
        if a.observedAt != b.observedAt { return a.observedAt > b.observedAt }
        return a.id < b.id
    }
    return Array(sorted.prefix(3))
}

/// Mensaje al modelo con las etiquetas numeradas de las candidatas (los únicos dígitos del texto son 1..N).
public func nyxFocusPrompt(_ candidates: [NyxObservation]) -> String {
    var text = "Situaciones del día:\n"
    for (index, candidate) in candidates.enumerated() {
        text += "\(index + 1). \(candidate.situation.promptLabel).\n"
    }
    return text + "Responde solo con el número de la que merece destacarse."
}

/// El número que contesta el modelo dentro de `1...count` (mismas reglas que `openingChoice`); nil si no vale.
public func nyxFocusChoice(from answer: String, count: Int) -> Int? {
    openingChoice(from: answer, count: count)
}

/// La puesta al día completa que enseña la hoja de Nyx cada mañana.
public struct NyxDailyUpdate: Equatable, Sendable {
    public let briefing: Briefing
    public let opening: String
    public let focus: NyxMessage?
    public let seenSinceLastLook: Int

    public var showsTip: Bool { focus == nil }

    public init(briefing: Briefing, opening: String, focus: NyxMessage?, seenSinceLastLook: Int) {
        self.briefing = briefing
        self.opening = opening
        self.focus = focus
        self.seenSinceLastLook = seenSinceLastLook
    }
}

/// Compone la puesta al día de Nyx a partir de las entradas del libro, las candidatas a foco y las elecciones del modelo (si las hay).
public func nyxDailyUpdate(input: BriefingInput, candidates: [NyxObservation], focusChoice: Int?, openingChoice: Int?,
                           seenSinceLastLook: Int, privateMode: Bool, calendar: Calendar) -> NyxDailyUpdate {
    let briefing = makeNyxBriefing(input, calendar: calendar)
    let opening = openingLine(briefing: briefing, choice: openingChoice, day: input.now, privateMode: privateMode)
    let chosen: NyxObservation?
    if !candidates.isEmpty, let choice = focusChoice, (1...candidates.count).contains(choice) {
        chosen = candidates[choice - 1]
    } else {
        chosen = candidates.first
    }
    let focus = chosen.map { nyxMessage(for: $0, now: input.now, calendar: calendar) }
    return NyxDailyUpdate(briefing: briefing, opening: opening, focus: focus, seenSinceLastLook: max(0, seenSinceLastLook))
}

/// Línea de novedades en la puesta al día; nil si no hay ninguna.
public func nyxSeenLine(_ count: Int) -> String? {
    guard count > 0 else { return nil }
    return count == 1 ? "He visto una cosa desde la última vez." : "He visto \(count) cosas desde la última vez."
}

private func nyxEndSentence(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.last else { return "" }
    return ".!?".contains(last) ? trimmed : trimmed + "."
}

/// Versión hablada de la puesta al día: saludo, apertura, el resumen y la cosa del día (con el ojo cerrado, sin importes ni líneas).
public func nyxSpokenUpdate(_ u: NyxDailyUpdate, input: BriefingInput, privateMode: Bool, calendar: Calendar) -> SpokenBriefing {
    let greetingPrefix = u.briefing.greeting + "."
    let openingSentence = nyxEndSentence(u.opening)

    if privateMode {
        let base = spokenBriefing(u.briefing, input: input, privateMode: true, calendar: calendar)
        var parts: [String] = []
        if base.hasPrefix(greetingPrefix) {
            parts.append(greetingPrefix)
            if !openingSentence.isEmpty { parts.append(openingSentence) }
            let rest = String(base.dropFirst(greetingPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { parts.append(rest) }
        } else {
            if !openingSentence.isEmpty { parts.append(openingSentence) }
            if !base.isEmpty { parts.append(base) }
        }
        if let focus = u.focus {
            let focusClosed = nyxEndSentence(nyxDisplayText(focus, hidden: true))
            if !focusClosed.isEmpty { parts.append(focusClosed) }
        }
        return SpokenBriefing(text: parts.joined(separator: " "), lines: [])
    }

    let adjustedTip: BriefingLine? = u.focus.map { BriefingLine(id: "nyx-focus", parts: $0.open) } ?? u.briefing.tip
    let adjustedBriefing = Briefing(
        greeting: u.briefing.greeting,
        headline: u.briefing.headline,
        sections: u.briefing.sections,
        tip: adjustedTip,
        isQuiet: u.briefing.isQuiet,
        situation: u.briefing.situation)
    let base = spokenBriefingLines(adjustedBriefing, input: input, privateMode: false, calendar: calendar)
    guard !openingSentence.isEmpty, base.text.hasPrefix(greetingPrefix) else { return base }

    let insertion = " " + openingSentence
    let shift = insertion.utf16.count
    let rest = String(base.text.dropFirst(greetingPrefix.count))
    let fullText = greetingPrefix + insertion + rest
    let shiftedLines = base.lines.map { line in
        SpokenBriefing.Line(id: line.id, range: (line.range.lowerBound + shift)..<(line.range.upperBound + shift))
    }
    return SpokenBriefing(text: fullText, lines: shiftedLines)
}
