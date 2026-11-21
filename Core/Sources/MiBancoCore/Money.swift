/// Céntimos -> "1.284,55 €" (punto de miles, coma decimal, NBSP antes de €).
/// Sin NumberFormatter: idéntico en Linux e iOS.
public func formatEUR(_ cents: Int) -> String {
    let mag = cents.magnitude
    let euros = String(mag / 100)
    var grouped = ""
    for (i, ch) in euros.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(".") }
        grouped.append(ch)
    }
    let rest = mag % 100
    let sign = cents < 0 ? "-" : ""
    return "\(sign)\(String(grouped.reversed())),\(rest < 10 ? "0" : "")\(rest)\u{00A0}€"
}

/// Token de importe (puede llevar €, EUR, cualquier espacio Unicode y signo) -> valor absoluto en céntimos.
/// El último `,`/`.` seguido de 1 o 2 dígitos al final es el decimal ("12.5" = 12,50);
/// seguido de 3 dígitos es de miles ("1.234" = 1.234,00).
public func parseAmountToCents(_ raw: Substring) -> Int? {
    let s = String(raw).replacing("EUR", with: "").filter { !$0.isWhitespace && $0 != "€" && $0 != "-" }
    guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }) else { return nil }
    let digits = s.filter { $0.isNumber }
    guard !digits.isEmpty, digits.count <= 12, let value = Int(digits) else { return nil }
    guard let separator = s.lastIndex(where: { $0 == "," || $0 == "." }) else { return value * 100 }
    let decimals = s[s.index(after: separator)...]
    switch decimals.count {
    case 1: return value * 10
    case 2: return value
    default: return value * 100
    }
}

/// Primer importe del texto: junto a `€`/`EUR` o con 2 decimales. Un entero suelto no cuenta.
/// shortcut: una fecha tipo "20.11" se tomaría como importe, solo si el banco la escribe así.
public func firstAmount(in text: String) -> (cents: Int, range: Range<String.Index>)? {
    let n = #"\d+(?:[.,]\d+)*"#
    let sp = "[ \u{00A0}\u{202F}]?"
    let pattern = "(?:€|EUR)" + sp + n + "|" + n + sp + "(?:€|EUR)"
        + "|" + n + #"[.,]\d{2}(?!\d|[.,]\d)"#
    guard let match = text.firstMatch(of: try! Regex(pattern)),
          let cents = parseAmountToCents(text[match.range]) else { return nil }
    return (cents, match.range)
}

/// Importe en otra moneda ("$5.00", "£12,50", "5,00 USD"): no se puede contar como euros.
func containsForeignAmount(_ text: String) -> Bool {
    let codes = "USD|GBP|CHF|JPY|CAD|AUD|SEK|NOK|DKK|PLN|CZK|HUF|RON|MXN|TRY|CNY"
    let symbol = "(?:[$£¥₹₺₣]|US\\$|\\b(?:\(codes))\\b)"
    let sp = "[ \u{00A0}\u{202F}]?"
    let pattern = symbol + sp + #"\d"# + "|" + #"\d"# + sp + symbol
    return text.contains(try! Regex(pattern))
}
