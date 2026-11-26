import Foundation

// Un IBAN es un dato sensible: estas funciones no guardan ni escriben nada en ninguna parte.

/// Mayúsculas y solo letras y cifras ("es91-2100 0418" -> "ES912100…").
public func normalizeIBAN(_ raw: String) -> String {
    // Primero se quita lo que no es ASCII y después se pasa a mayúsculas: así «ß» no se convierte en "SS".
    let ascii = String(raw.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    return ascii.uppercased()
}

/// Longitud 15–34 (España exactamente 24) y dígito de control módulo 97 igual a 1.
public func isValidIBAN(_ raw: String) -> Bool {
    let iban = normalizeIBAN(raw)
    let chars = Array(iban.unicodeScalars)
    guard (15...34).contains(chars.count) else { return false }
    guard chars[0].properties.isAlphabetic, chars[1].properties.isAlphabetic,
          chars[2].properties.numericType != nil, chars[3].properties.numericType != nil else { return false }
    if iban.hasPrefix("ES"), chars.count != 24 { return false }
    // Los cuatro primeros pasan al final; las letras valen A=10 … Z=35.
    var remainder = 0
    for scalar in chars[4...] + chars[..<4] {
        let value = scalar.value
        let digits: [Int]
        switch value {
        case 48...57: digits = [Int(value) - 48]
        case 65...90: let n = Int(value) - 55; digits = [n / 10, n % 10]
        default: return false
        }
        for d in digits { remainder = (remainder * 10 + d) % 97 }
    }
    return remainder == 1
}

/// Grupos de cuatro separados por espacio.
public func formatIBAN(_ iban: String) -> String {
    let clean = normalizeIBAN(iban)
    var out = ""
    for (i, ch) in clean.enumerated() {
        if i > 0 && i % 4 == 0 { out.append(" ") }
        out.append(ch)
    }
    return out
}

/// "ES91 •••• 1332": cuatro primeros y cuatro últimos, solo si el IBAN tiene al menos 12 caracteres;
/// si es más corto, solo los dos últimos ("•••• 32").
public func maskedIBAN(_ iban: String) -> String {
    let clean = normalizeIBAN(iban)
    guard clean.count >= 12 else { return clean.count >= 2 ? "•••• \(clean.suffix(2))" : "••••" }
    return "\(clean.prefix(4)) •••• \(clean.suffix(4))"
}

/// Móvil español (con o sin +34 / 0034, con espacios o guiones) -> "+34 612 345 678"; otra cosa -> nil.
public func normalizeSpanishMobile(_ raw: String) -> String? {
    var digits = String(raw.unicodeScalars.filter { $0.isASCII && ($0.properties.numericType != nil || $0 == "+") }.map(Character.init))
    if digits.hasPrefix("+34") { digits.removeFirst(3) } else if digits.hasPrefix("0034") { digits.removeFirst(4) }
    guard digits.count == 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
          let first = digits.first, first == "6" || first == "7" else { return nil }
    let d = Array(digits)
    return "+34 \(String(d[0..<3])) \(String(d[3..<6])) \(String(d[6..<9]))"
}
