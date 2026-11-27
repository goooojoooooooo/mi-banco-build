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

/// Longitud exacta del IBAN por código ISO de país (registro ISO 13616 / SWIFT).
public let ibanCountryLengths: [String: Int] = [
    "AD": 24, "AE": 23, "AL": 28, "AT": 20, "AZ": 28, "BA": 20, "BE": 16, "BG": 22,
    "BH": 22, "BI": 27, "BR": 29, "BY": 28, "CH": 21, "CR": 22, "CY": 28, "CZ": 24,
    "DE": 22, "DJ": 27, "DK": 18, "DO": 28, "EE": 20, "EG": 29, "ES": 24, "FI": 18,
    "FO": 18, "FR": 27, "GB": 22, "GE": 22, "GI": 23, "GL": 18, "GR": 27, "GT": 28,
    "HN": 28, "HR": 21, "HU": 28, "IE": 22, "IL": 23, "IQ": 23, "IS": 26, "IT": 27,
    "JO": 30, "KW": 30, "KZ": 20, "LB": 28, "LC": 32, "LI": 21, "LT": 20, "LU": 20,
    "LV": 21, "LY": 25, "MC": 27, "MD": 24, "ME": 22, "MK": 19, "MR": 27, "MT": 31,
    "MU": 30, "NL": 18, "NO": 15, "PK": 24, "PL": 28, "PS": 29, "PT": 25, "QA": 29,
    "RO": 24, "RS": 22, "SA": 24, "SC": 31, "SD": 18, "SE": 24, "SI": 19, "SK": 24,
    "SM": 27, "ST": 25, "SV": 28, "TL": 23, "TN": 24, "TR": 26, "UA": 29, "VA": 22,
    "VG": 24, "XK": 20,
]

/// Valida un IBAN recibido del banco antes de guardarlo en la libreta:
/// solo caracteres ASCII propios de un IBAN (letras, cifras, espacio o guion), país del registro ISO 13616
/// con su longitud exacta, dígitos de control en 02–98 y módulo 97 igual a 1. Devuelve el IBAN normalizado o `nil`.
public func validatedBankIBAN(_ raw: String) -> String? {
    let allowedRaw = raw.unicodeScalars.allSatisfy { s in
        s.isASCII && (
            (s.value >= 48 && s.value <= 57)
            || (s.value >= 65 && s.value <= 90)
            || (s.value >= 97 && s.value <= 122)
            || s.value == 32
            || s.value == 45
        )
    }
    guard allowedRaw else { return nil }
    let clean = normalizeIBAN(raw)
    guard clean.count >= 15 else { return nil }
    let country = String(clean.prefix(2))
    guard let expectedLength = ibanCountryLengths[country], clean.count == expectedLength else {
        return nil
    }
    guard let checkDigits = Int(clean.dropFirst(2).prefix(2)), (2...98).contains(checkDigits) else {
        return nil
    }
    guard isValidIBAN(clean) else { return nil }
    return clean
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
