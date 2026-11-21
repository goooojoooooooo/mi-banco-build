import Foundation

public enum BankAction: String, Sendable { case connect, renew, refresh, importStatement, editBalance }

public struct BankStatusLines: Equatable, Sendable {
    public let primary: String
    public let secondary: String?
    public let action: BankAction?

    public init(primary: String, secondary: String?, action: BankAction?) {
        self.primary = primary
        self.secondary = secondary
        self.action = action
    }
}

private let spanishMonths = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]

public func shortSpanishDate(_ date: Date, calendar: Calendar, withYear: Bool) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    let text = "\(c.day ?? 1) \(spanishMonths[((c.month ?? 1) - 1) % 12])"
    return withYear ? "\(text) \(c.year ?? 0)" : text
}

private func clock(_ date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    let h = c.hour ?? 0, m = c.minute ?? 0
    return (h < 10 ? "0" : "") + "\(h):" + (m < 10 ? "0" : "") + "\(m)"
}

private func dayDifference(from a: Date, to b: Date, calendar: Calendar) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
}

public func relativeUpdated(_ date: Date, now: Date, calendar: Calendar) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "hace un momento" }
    if seconds < 3600 { return "hace \(Int(seconds / 60)) min" }
    let days = dayDifference(from: date, to: now, calendar: calendar)
    if seconds < 86_400 && days == 0 { return "hace \(Int(seconds / 3600)) h" }
    if days == 1 { return "ayer a las \(clock(date, calendar: calendar))" }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return "el " + shortSpanishDate(date, calendar: calendar, withYear: !sameYear)
}

private func expiryLine(_ validUntil: Date, now: Date, calendar: Calendar) -> String {
    let days = dayDifference(from: now, to: validUntil, calendar: calendar)
    if days <= 0 { return "Caduca hoy" }
    if days == 1 { return "Caduca mañana" }
    if days <= 10 { return "Caduca en \(days) días" }
    return "Caduca el " + shortSpanishDate(validUntil, calendar: calendar, withYear: true)
}

public func bankStatusLines(
    bank: BankID, link: BankLinkInfo?, estimated: Bool?, canConnect: Bool, now: Date, calendar: Calendar
) -> BankStatusLines {
    guard let link else {
        return canConnect
            ? BankStatusLines(primary: "Sin conectar", secondary: nil, action: .connect)
            : BankStatusLines(primary: "Importa su extracto", secondary: nil, action: .importStatement)
    }
    if now >= link.consentValidUntil || link.problem == .consentExpired {
        // Si el banco la revocó antes de la fecha prevista, la caducidad real es hoy.
        let expiredOn = min(link.consentValidUntil, now)
        let sameYear = calendar.component(.year, from: expiredOn) == calendar.component(.year, from: now)
        return BankStatusLines(
            primary: "La conexión caducó el " + shortSpanishDate(expiredOn, calendar: calendar, withYear: !sameYear),
            secondary: "Renuévala para ver el saldo exacto", action: .renew)
    }
    if link.problem == .keyRejected {
        return BankStatusLines(
            primary: "Enable Banking no acepta la clave", secondary: "Revisa la conexión en Ajustes", action: .renew)
    }
    let expiry = expiryLine(link.consentValidUntil, now: now, calendar: calendar)
    if link.problem == .rateLimited, let until = link.backoffUntil, until > now {
        return BankStatusLines(
            primary: "El banco ha pedido esperar · vuelve a las \(clock(until, calendar: calendar))",
            secondary: expiry, action: nil)
    }
    if link.problem == .unknown, let until = link.backoffUntil, until > now {
        return BankStatusLines(
            primary: "No se pudo actualizar · lo intentamos más tarde", secondary: expiry, action: .refresh)
    }
    if link.problem != nil {
        return BankStatusLines(
            primary: "No se pudo actualizar · lo intentamos al abrir la app", secondary: expiry, action: .refresh)
    }
    guard let ok = link.lastSuccessAt else {
        return BankStatusLines(primary: "Conectado · actualizando…", secondary: expiry, action: nil)
    }
    let days = dayDifference(from: now, to: link.consentValidUntil, calendar: calendar)
    return BankStatusLines(
        primary: "Actualizado \(relativeUpdated(ok, now: now, calendar: calendar)) · "
            + (estimated == true ? "estimado" : "exacto"),
        secondary: expiry, action: days <= 10 ? .renew : .refresh)
}
