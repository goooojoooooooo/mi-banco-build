import Foundation

/// Un trozo del texto del resumen. Los importes viajan como números (no como texto) para poder enseñarlos, taparlos con el
/// ojo cerrado o contarlos con animación.
public enum BriefingPart: Equatable, Sendable {
    case text(String)
    case amount(Int)
    case signed(Int)
    case whole(Int)
    case percentTenths(Int)
}

/// Lo que ocurre al tocar una línea.
public enum BriefingAction: Equatable, Sendable {
    case moveMoney(from: BankID?, to: BankID, cents: Int?)
    case openBankSettings(BankID)
    case openBudgets
    case openInvestments
    case openMovement(UUID)
}

public struct BriefingLine: Equatable, Sendable, Identifiable {
    public let id: String
    public let parts: [BriefingPart]
    public let action: BriefingAction?

    public init(id: String, parts: [BriefingPart], action: BriefingAction? = nil) {
        self.id = id
        self.parts = parts
        self.action = action
    }
}

public enum BriefingSectionKind: String, Sendable {
    case money, happened, upcoming, attention, month, investments
}

public struct BriefingSection: Equatable, Sendable, Identifiable {
    public let kind: BriefingSectionKind
    public let title: String
    public let lines: [BriefingLine]
    public var id: String { kind.rawValue }

    public init(kind: BriefingSectionKind, title: String, lines: [BriefingLine]) {
        self.kind = kind
        self.title = title
        self.lines = lines
    }
}

public struct Briefing: Equatable, Sendable {
    public let greeting: String
    public let headline: [BriefingPart]
    public let sections: [BriefingSection]
    public let tip: BriefingLine?
    public let isQuiet: Bool

    public init(greeting: String, headline: [BriefingPart], sections: [BriefingSection], tip: BriefingLine?, isQuiet: Bool) {
        self.greeting = greeting
        self.headline = headline
        self.sections = sections
        self.tip = tip
        self.isQuiet = isQuiet
    }
}

// MARK: Pintar

public enum RenderStyle: Sendable {
    /// Con los importes.
    case plain
    /// Sin ningún importe: cada cifra de dinero (y todo importe escrito dentro de un texto) queda en «•••».
    case masked
}

private let maskDots = "•••"

/// Un importe escrito en un texto libre («13,99 € dos veces hoy», «20 EUR», «5 euros») o un decimal suelto con coma («13,99»):
/// cifras con puntos o comas y un € / EUR / euros detrás, o `n,nn`.
private let writtenAmountPattern =
    "(?i)[-+]?[0-9][0-9.,]*[ \u{00A0}]?(?:€|euros?(?![a-z])|eur(?![a-z]))|[-+]?[0-9][0-9.]*,[0-9]{2}(?![0-9])"

public func render(_ parts: [BriefingPart], _ style: RenderStyle) -> String {
    var out = ""
    for part in parts {
        switch (part, style) {
        case (.text(let s), .plain):
            out += s
        case (.text(let s), .masked):
            out += s.replacingOccurrences(of: writtenAmountPattern, with: maskDots, options: .regularExpression)
        case (.amount(let c), .plain):
            out += formatEUR(c)
        case (.signed(let c), .plain):
            out += formatSignedEUR(c)
        case (.whole(let c), .plain):
            out += formatEURWhole(c)
        case (.percentTenths(let t), .plain):
            out += formatPercentTenths(t, signed: true)
        case (_, .masked):
            out += maskDots
        }
    }
    return out
}

// MARK: Fechas en español (sin formateadores del sistema: igual en Linux y en iOS)

private let weekdayNames = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
private let shortMonthNames = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

private func weekdayName(_ date: Date, _ calendar: Calendar) -> String {
    weekdayNames[((calendar.component(.weekday, from: date) - 1) % 7 + 7) % 7]
}

private func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

private func clock(_ date: Date, _ calendar: Calendar) -> String {
    let h = calendar.component(.hour, from: date), m = calendar.component(.minute, from: date)
    return (h < 10 ? "0" : "") + String(h) + ":" + (m < 10 ? "0" : "") + String(m)
}

/// "30 nov"
private func shortDate(_ date: Date, _ calendar: Calendar) -> String {
    let month = calendar.component(.month, from: date)
    return "\(calendar.component(.day, from: date)) \(shortMonthNames[(month - 1 + 12) % 12])"
}

/// Días de calendario de `a` a `b` (positivo si `b` es posterior).
private func dayDistance(from a: Date, to b: Date, _ calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
}

public func greeting(at date: Date, calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    switch hour {
    case 5..<13: return "Buenos días"
    case 13..<21: return "Buenas tardes"
    default: return "Buenas noches"
    }
}

/// «Desde las 08:30» (hoy), «Desde ayer a las 22:10», «Desde el miércoles» (hasta 6 días), «Desde el 13 nov» (7 o más),
/// «En las últimas 24 horas» (primera vez).
public func periodPhrase(since: Date, now: Date, isFirst: Bool, calendar: Calendar) -> String {
    if isFirst { return "En las últimas 24 horas" }
    let days = dayDistance(from: since, to: now, calendar)
    switch days {
    case ...0: return "Desde las \(clock(since, calendar))"
    case 1: return "Desde ayer a las \(clock(since, calendar))"
    case 2...6: return "Desde el \(weekdayName(since, calendar))"
    default: return "Desde el \(shortDate(since, calendar))"
    }
}

/// El periodo para «Nada nuevo …»: sin la hora cuando fue ayer y en minúscula.
func quietPeriodPhrase(since: Date, now: Date, isFirst: Bool, calendar: Calendar) -> String {
    let phrase = periodPhrase(since: since, now: now, isFirst: isFirst, calendar: calendar)
    if phrase.hasPrefix("Desde ayer a las") { return "desde ayer" }
    return phrase.prefix(1).lowercased() + phrase.dropFirst()
}

private func dayLabel(_ date: Date, now: Date, _ calendar: Calendar) -> String {
    switch dayDistance(from: now, to: date, calendar) {
    case ...0: return "Hoy"
    case 1: return "Mañana"
    default: return "\(capitalized(weekdayName(date, calendar))) \(calendar.component(.day, from: date))"
    }
}

private func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

/// Lo más largo que sale el nombre de un comercio en una línea del resumen.
let maxMerchantNameLength = 40

/// El nombre de un comercio recortado a 40 caracteres (con «…» al final si se recorta).
func clippedName(_ name: String) -> String {
    name.count <= maxMerchantNameLength ? name : String(name.prefix(maxMerchantNameLength - 1)) + "…"
}

// MARK: Secciones

private func moneyLines(_ input: BriefingInput, quiet: Bool) -> [BriefingLine] {
    var lines: [BriefingLine] = []
    let known = input.banks.filter { $0.cents != nil }
    // «unos» en el total en cuanto UN saldo conocido es una estimación (la suma lo es); cada banco estimado lo dice en su línea.
    let approximate = known.contains(where: \.estimated)
    if let total = input.totalCents {
        // «sin contar imagin»: los bancos sin saldo conocido no están en el total ni en su cambio.
        let leftOut = input.totalLeftOut.isEmpty ? "" : ", sin contar " + input.totalLeftOut.map(\.displayName).joined(separator: ", ")
        if quiet {
            lines.append(BriefingLine(id: "money-total", parts: [.text(approximate ? "Sigues con unos " : "Sigues con "),
                                                                 .amount(total), .text(" en total\(leftOut).")]))
            return lines
        }
        var parts: [BriefingPart] = [.text(approximate ? "En total, unos " : "En total, "), .amount(total)]
        if input.totalChangeCents == 0 {
            parts.append(.text(" (sin cambios)"))
        } else {
            parts += [.text(" ("), .signed(input.totalChangeCents), .text(")")]
        }
        if !leftOut.isEmpty { parts.append(.text(leftOut)) }
        lines.append(BriefingLine(id: "money-total", parts: parts))
    }
    if quiet { return lines }
    for bank in input.banks {
        var parts: [BriefingPart]
        if let cents = bank.cents {
            parts = [.text("\(bank.bank.displayName): \(bank.estimated ? "unos " : "")"), .amount(cents)]
        } else {
            parts = [.text("\(bank.bank.displayName): aún sin saldo")]
        }
        if bank.changeCents == 0 {
            parts.append(.text(" (sin cambios)"))
        } else {
            parts += [.text(" ("), .signed(bank.changeCents), .text(")")]
        }
        lines.append(BriefingLine(id: "money-\(bank.bank.rawValue)", parts: parts))
    }
    return lines
}

private let maxListedPerKind = 3

private func happenedLines(_ input: BriefingInput) -> [BriefingLine] {
    var lines: [BriefingLine] = []
    for item in input.income.prefix(maxListedPerKind) {
        lines.append(BriefingLine(id: "in-\(item.id.uuidString)",
                                  parts: [.text("Entró \(clippedName(item.name)): "), .amount(item.cents),
                                          .text(" en \(item.bank.displayName)")],
                                  action: .openMovement(item.id)))
    }
    if input.income.count > maxListedPerKind {
        let rest = input.income.dropFirst(maxListedPerKind)
        lines.append(BriefingLine(id: "in-rest", parts: [.text("Y \(rest.count) \(plural(rest.count, "ingreso", "ingresos")) más: "),
                                                         .amount(rest.reduce(0) { $0 + $1.cents })]))
    }
    for item in input.payments.prefix(maxListedPerKind) {
        lines.append(BriefingLine(id: "out-\(item.id.uuidString)",
                                  parts: [.text("\(clippedName(item.name)): "), .amount(item.cents),
                                          .text(" con \(item.bank.displayName)")],
                                  action: .openMovement(item.id)))
    }
    if input.payments.count > maxListedPerKind {
        let rest = input.payments.dropFirst(maxListedPerKind)
        lines.append(BriefingLine(id: "out-rest", parts: [.text("Y \(rest.count) \(plural(rest.count, "pago", "pagos")) más: "),
                                                          .amount(rest.reduce(0) { $0 + $1.cents })]))
    }
    for (i, t) in input.transfers.enumerated() {
        lines.append(BriefingLine(id: "transfer-\(i)",
                                  parts: [.amount(t.cents), .text(" de \(t.from.displayName) a \(t.to.displayName) (entre tus cuentas)")]))
    }
    return lines
}

private func upcomingLines(_ input: BriefingInput, calendar: Calendar, quiet: Bool) -> [BriefingLine] {
    var lines: [BriefingLine] = []
    if !quiet, let expected = input.expected {
        let day = "\(weekdayName(expected.date, calendar)) \(calendar.component(.day, from: expected.date))"
        lines.append(BriefingLine(id: "expected", parts: [.text("Hacia el \(day): \(clippedName(expected.name)), unos "), .amount(expected.cents),
                                                          .text(" en \(expected.bank.displayName)")]))
    }
    for (i, charge) in input.upcoming.enumerated() {
        if quiet, dayDistance(from: input.now, to: charge.date, calendar) > 1 { continue }
        lines.append(BriefingLine(id: "upcoming-\(i)",
                                  parts: [.text("\(dayLabel(charge.date, now: input.now, calendar)): \(clippedName(charge.name)), "),
                                          .amount(charge.cents),
                                          .text(" en \(charge.bank.displayName)" + (overdueNote(charge, calendar: calendar).map { " (\($0))" } ?? ""))]))
    }
    return lines
}

private func attentionLines(_ input: BriefingInput, calendar: Calendar) -> [BriefingLine] {
    input.attention.enumerated().map { (i, item) -> BriefingLine in
        let id = "attention-\(i)"
        switch item {
        case .bankProblem(let bank, let problem):
            let name = bank.displayName
            switch problem {
            case .offline:
                return BriefingLine(id: id, parts: [.text("Sin conexión al actualizar \(name).")])
            case .rateLimited:
                return BriefingLine(id: id, parts: [.text("\(name) ha pedido una pausa: vuelvo a mirar en unas horas.")])
            case .consentExpired, .keyRejected:
                return BriefingLine(id: id, parts: [.text("La conexión con \(name) ha caducado: renuévala en Ajustes.")],
                                    action: .openBankSettings(bank))
            case .bankUnavailable, .unknown:
                return BriefingLine(id: id, parts: [.text("No he podido actualizar \(name): lo intentaré al volver a abrir.")])
            }
        case .consentExpiring(let bank, let date):
            return BriefingLine(id: id, parts: [.text("La conexión con \(bank.displayName) caduca el \(shortDate(date, calendar)): renuévala en Ajustes.")],
                                action: .openBankSettings(bank))
        case .budgetExceeded(let name, let spent, let limit):
            return BriefingLine(id: id, parts: [.text("Te has pasado en \(name): "), .amount(spent), .text(" de "), .amount(limit), .text(".")],
                                action: .openBudgets)
        case .warning(let title, let detail):
            return BriefingLine(id: id, parts: [.text(detail.map { "\(title). \($0)" } ?? title)])
        }
    }
}

private func monthLines(_ month: MonthDigest) -> [BriefingLine] {
    var lines: [BriefingLine] = []
    if let projected = month.projectedCents {
        lines.append(BriefingLine(id: "month-spent", parts: [.text("Llevas "), .amount(month.spentCents),
                                                             .text(" gastados; a este ritmo acabarás en unos "), .whole(projected), .text(".")]))
    } else {
        lines.append(BriefingLine(id: "month-spent", parts: [.text("Llevas "), .amount(month.spentCents), .text(" gastados este mes.")]))
    }
    if let diff = month.paceDifferenceCents {
        if diff < 0 {
            lines.append(BriefingLine(id: "month-pace", parts: [.amount(-diff), .text(" menos que en \(month.previousMonthName) a estas alturas.")]))
        } else if diff > 0 {
            lines.append(BriefingLine(id: "month-pace", parts: [.amount(diff), .text(" más que en \(month.previousMonthName) a estas alturas.")]))
        } else {
            lines.append(BriefingLine(id: "month-pace", parts: [.text("Igual que en \(month.previousMonthName) a estas alturas.")]))
        }
    }
    return lines
}

private func priceAge(_ date: Date, now: Date, _ calendar: Calendar) -> String {
    let time = clock(date, calendar)
    switch dayDistance(from: date, to: now, calendar) {
    case ...0: return "precios de las \(time)"
    case 1: return "precios de ayer, \(time)"
    default: return "precios del \(shortDate(date, calendar)), \(time)"
    }
}

/// `valueOnly`: solo la primera línea y los avisos de honestidad (día tranquilo).
private func investmentLines(_ s: PortfolioSummary, now: Date, calendar: Calendar, valueOnly: Bool) -> [BriefingLine] {
    var lines: [BriefingLine] = []
    guard let value = s.valueCents else {
        return [BriefingLine(id: "inv-value", parts: [.text("Aún no tengo precios de tus inversiones.")], action: .openInvestments)]
    }
    // Con precios que faltan, la cifra es parcial y se dice.
    let partial = s.missingPrices > 0
    var first: [BriefingPart] = [.text(partial ? "Valen al menos " : "Valen "), .amount(value)]
    if partial { first.append(.text(" de las que tienen precio")) }
    // El cambio solo es «de hoy» si el precio es de hoy; si no, se dice de qué sesión es. Sin día no se escribe.
    if let today = s.todayChangeCents, let day = s.changeDay {
        let when = dayDistance(from: day, to: now, calendar) <= 0 ? "hoy" : "en la última sesión (\(weekdayName(day, calendar)))"
        first += [.text(": "), .signed(today), .text(" \(when)")]
        if let tenths = s.todayChangeTenths { first += [.text(" ("), .percentTenths(tenths), .text(")")] }
    } else {
        // Sin cierre anterior no hay cambio que contar: no se escribe.
        first.append(.text("."))
    }
    lines.append(BriefingLine(id: "inv-value", parts: first, action: .openInvestments))
    if !valueOnly {
        var second: [BriefingPart] = []
        if let gain = s.gainCents {
            second += [.text(partial ? "Desde la compra, de las que tienen precio: " : "Desde la compra: "), .signed(gain)]
            if let tenths = s.gainTenths { second += [.text(" ("), .percentTenths(tenths), .text(")")] }
        }
        if let at = s.pricedAt {
            let age = priceAge(at, now: now, calendar)
            second.append(.text(second.isEmpty ? capitalized(age) : " · " + age))
        }
        if !second.isEmpty { lines.append(BriefingLine(id: "inv-gain", parts: second, action: .openInvestments)) }
    }
    if s.missingPrices > 0 {
        lines.append(BriefingLine(id: "inv-missing",
                                  parts: [.text("Falta el precio de \(s.missingPrices) \(plural(s.missingPrices, "posición", "posiciones")).")],
                                  action: .openInvestments))
    }
    if s.hasStalePrice, let oldest = s.oldestPriceAt {
        lines.append(BriefingLine(id: "inv-stale",
                                  parts: [.text("Algún precio es viejo (el más antiguo, del \(shortDate(oldest, calendar))): el valor puede estar desfasado.")],
                                  action: .openInvestments))
    }
    return lines
}

// MARK: Consejo

private func tipLine(_ input: BriefingInput, calendar: Calendar, shortfallOnly: Bool) -> BriefingLine? {
    if let s = input.shortfalls.first {
        let when: String
        switch dayDistance(from: input.now, to: s.charge.date, calendar) {
        case ...0: when = "Hoy te cobran"
        case 1: when = "Mañana te cobran"
        default: when = "El \(weekdayName(s.charge.date, calendar)) \(calendar.component(.day, from: s.charge.date)) te cobran"
        }
        var parts: [BriefingPart] = [.text("\(when) \(clippedName(s.charge.name)) ("), .amount(s.charge.cents),
                                     .text(") en \(s.bank.displayName) y tienes \(s.isEstimated ? "unos " : "")"), .amount(s.balanceCents)]
        if let from = s.suggestedFrom {
            parts += [.text(". Pasa "), .amount(s.suggestedCents), .text(" desde \(from.displayName).")]
            if s.suggestedIsEstimated { parts.append(.text(" El saldo de \(from.displayName) es aproximado.")) }
        } else {
            parts += [.text(". Pásale "), .amount(s.suggestedCents), .text(" antes.")]
        }
        return BriefingLine(id: "tip-shortfall", parts: parts,
                            action: .moveMoney(from: s.suggestedFrom, to: s.bank, cents: s.suggestedCents))
    }
    if shortfallOnly { return nil }
    // Nunca «unos 0 € al día»: si lo que sale por día no llega a medio euro, esa línea no se escribe.
    if let tip = input.budgetTip {
        let days = calendar.range(of: .day, in: .month, for: input.now)?.count ?? 30
        let daysLeft = max(1, days - calendar.component(.day, from: input.now) + 1)
        let perDay = tip.remainingCents / daysLeft
        if perDay.magnitude >= 50 {
            return BriefingLine(id: "tip-budget",
                                parts: [.text("Te quedan "), .amount(tip.remainingCents), .text(" para \(tip.name) hasta fin de mes: unos "),
                                        .whole(perDay), .text(" al día.")],
                                action: .openBudgets)
        }
    }
    if let free = input.freeMoney, free.perDayCents.magnitude >= 50 {
        var parts: [BriefingPart] = [.text("Hasta fin de mes te quedan unos "), .whole(free.cents), .text(" libres: unos "),
                                     .whole(free.perDayCents)]
        if free.missingBanks.isEmpty {
            parts.append(.text(" al día, sin contar el gasto del día a día."))
        } else {
            let names = free.missingBanks.map(\.displayName).joined(separator: ", ")
            parts.append(.text(" al día. Sin contar \(names): no tengo su saldo, y sin contar el gasto del día a día."))
        }
        return BriefingLine(id: "tip-free", parts: parts)
    }
    return nil
}

// MARK: El resumen

let nothingNewUnreadable = "Nada nuevo en lo que he podido ver."

/// Los bancos con un problema de conexión en la lista de atención (en su orden, sin repetir).
func bankProblemBanks(_ input: BriefingInput) -> [BankID] {
    var banks: [BankID] = []
    for case .bankProblem(let bank, _) in input.attention where !banks.contains(bank) { banks.append(bank) }
    return banks
}

private func headline(_ input: BriefingInput, calendar: Calendar) -> [BriefingPart] {
    let period = periodPhrase(since: input.since, now: input.now, isFirst: input.isFirst, calendar: calendar)
    let incomeTotal = input.income.reduce(0) { $0 + $1.cents }
    let spent = input.payments.reduce(0) { $0 + $1.cents }
    let count = input.payments.count
    let payments = "en \(count) \(plural(count, "pago", "pagos"))."
    switch (input.income.isEmpty, input.payments.isEmpty) {
    case (false, false):
        return [.text("\(period) entraron "), .amount(incomeTotal), .text(" y gastaste "), .amount(spent), .text(" \(payments)")]
    case (true, false):
        return [.text("\(period) gastaste "), .amount(spent), .text(" \(payments)")]
    case (false, true):
        return [.text("\(period) entraron "), .amount(incomeTotal), .text(".")]
    case (true, true):
        if !input.transfers.isEmpty { return [.text("\(period) solo has movido dinero entre tus cuentas.")] }
        // Con un banco que no se ha podido leer, «nada nuevo» no es seguro: se dice solo lo que se ha podido ver.
        if !bankProblemBanks(input).isEmpty { return [.text(nothingNewUnreadable)] }
        let quiet = quietPeriodPhrase(since: input.since, now: input.now, isFirst: input.isFirst, calendar: calendar)
        return [.text("Nada nuevo \(quiet).")]
    }
}

/// El resumen con las reglas de siempre (sin modelo): es la base que se enseña si el modelo no está o su texto no pasa las
/// barreras. Cada cifra sale de `BriefingInput`, que sale del libro.
public func makeBriefing(_ input: BriefingInput, calendar: Calendar) -> Briefing {
    let quiet = input.income.isEmpty && input.payments.isEmpty && input.transfers.isEmpty && input.attention.isEmpty
    var sections: [BriefingSection] = []
    func add(_ kind: BriefingSectionKind, _ title: String, _ lines: [BriefingLine]) {
        if !lines.isEmpty { sections.append(BriefingSection(kind: kind, title: title, lines: lines)) }
    }
    add(.money, "Tu dinero", moneyLines(input, quiet: quiet))
    if !quiet {
        add(.happened, "Qué ha pasado", happenedLines(input))
    }
    add(.upcoming, "Lo que viene", upcomingLines(input, calendar: calendar, quiet: quiet))
    if !quiet {
        add(.attention, "Ojo con esto", attentionLines(input, calendar: calendar))
        add(.month, "El mes", input.month.map(monthLines) ?? [])
    }
    if let investments = input.investments {
        add(.investments, "Inversiones", investmentLines(investments, now: input.now, calendar: calendar, valueOnly: quiet))
    }
    return Briefing(greeting: greeting(at: input.now, calendar: calendar), headline: headline(input, calendar: calendar),
                    sections: sections, tip: tipLine(input, calendar: calendar, shortfallOnly: quiet), isQuiet: quiet)
}

/// Los hechos que puede usar un modelo para redactar: la frase principal, cada línea y el consejo, ya escritos con importes.
public func briefingFacts(_ briefing: Briefing) -> [String] {
    var facts = [render(briefing.headline, .plain)]
    for section in briefing.sections {
        for line in section.lines { facts.append(render(line.parts, .plain)) }
    }
    if let tip = briefing.tip { facts.append(render(tip.parts, .plain)) }
    return facts
}
