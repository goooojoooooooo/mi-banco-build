import Foundation

private let cardPrefixes = ["compra tarj.", "compra tarjeta", "pago tarjeta", "compra en"]
private let genericNames: Set<String> = ["pago con tarjeta", "card payment", "compra", "pago"]
private let smallWords: Set<String> = ["a", "de", "del", "en", "y", "la", "el"]

private func collapse(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func removing(_ pattern: String, from s: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
    return regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
}

/// Nombre del banco sin ruido: sin "COMPRA TARJ."/"COMPRA TARJETA"/"PAGO TARJETA"/"COMPRA EN" al principio, sin
/// tarjetas enmascaradas, con espacios colapsados y, solo si venía todo en mayúsculas, en minúsculas con inicial
/// mayúscula (a, de, del, en, y, la, el quedan en minúsculas salvo la primera palabra).
public func cleanBankMerchant(_ raw: String) -> String {
    var s = removing(#"\d{4}X{4,}\d{4}"#, from: raw)
    s = removing(#"\*\d{4}"#, from: s)
    s = collapse(s)
    let lower = s.lowercased()
    for prefix in cardPrefixes where lower == prefix || lower.hasPrefix(prefix + " ") {
        s = collapse(String(s.dropFirst(prefix.count)))
        break
    }
    let hasLower = s.contains { $0.isLowercase }
    guard s.contains(where: { $0.isLetter }), !hasLower else { return s }
    let words = s.split(separator: " ").enumerated().map { index, word -> String in
        let w = word.lowercased()
        if index > 0, smallWords.contains(w) { return w }
        return w.prefix(1).uppercased() + w.dropFirst()
    }
    return words.joined(separator: " ")
}

/// El nombre que se enseña: el capturado, salvo que esté vacío o sea genérico. Un nombre del banco que el directorio
/// conoce gana a un capturado que no conoce.
public func richerMerchant(captured: String?, bank: String?) -> String? {
    let c = captured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let b = bank?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if b.isEmpty { return c.isEmpty ? nil : c }
    if c.isEmpty || genericNames.contains(c.lowercased()) { return b }
    if merchantDomain(for: b) != nil, merchantDomain(for: c) == nil { return b }
    return c
}
