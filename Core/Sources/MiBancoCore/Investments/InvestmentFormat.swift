import Foundation

/// "+6,00 €", "-6,00 €", "0,00 €".
public func formatSignedEUR(_ cents: Int) -> String {
    cents > 0 ? "+" + formatEUR(cents) : formatEUR(cents)
}

/// Décimas de por ciento -> "+0,4 %", "-2,5 %", "0,0 %" (con espacio duro antes del %).
public func formatPercentTenths(_ tenths: Int, signed: Bool) -> String {
    let sign = tenths < 0 ? "-" : (tenths > 0 && signed ? "+" : "")
    return "\(sign)\(tenths.magnitude / 10),\(tenths.magnitude % 10)\u{00A0}%"
}

/// Acciones con coma decimal, punto de miles y hasta 6 decimales sin ceros de sobra: "12,4", "0,01", "3".
public func formatShares(_ shares: Decimal) -> String {
    guard shares.isFinite else { return "0" }
    var input = shares
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, 6, .plain)
    let plain = "\(rounded.magnitude)"
    let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
    var grouped = ""
    for (i, ch) in String(parts[0]).reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(".") }
        grouped.append(ch)
    }
    let integer = String(grouped.reversed())
    let fraction = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "0+$", with: "", options: .regularExpression) : ""
    let sign = rounded < 0 ? "-" : ""
    return sign + integer + (fraction.isEmpty ? "" : "," + fraction)
}

/// Precio unitario en euros: 2 decimales a partir de 1 € ("110,00 €", "180,33 €") y hasta 4 por debajo de 1 € ("0,0045 €").
public func formatUnitPriceEUR(_ price: Decimal) -> String {
    guard price.isFinite else { return "0,00\u{00A0}€" }
    let scale = price.magnitude < 1 ? 4 : 2
    var input = price
    var rounded = Decimal()
    NSDecimalRound(&rounded, &input, scale, .plain)
    let plain = "\(rounded.magnitude)"
    let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
    var grouped = ""
    for (i, ch) in String(parts[0]).reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(".") }
        grouped.append(ch)
    }
    let integer = String(grouped.reversed())
    var fraction = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "0+$", with: "", options: .regularExpression) : ""
    while fraction.count < 2 { fraction.append("0") }
    let sign = rounded < 0 ? "\u{2212}" : ""
    return "\(sign)\(integer),\(fraction)\u{00A0}€"
}

/// Resultado de importar una exportación de Trade Republic (se omiten las partes a cero).
public func formatPortfolioImportSummary(_ summary: ImportSummary) -> String {
    var parts: [String] = []
    if summary.added == 1 {
        parts.append("Importada 1 operación nueva")
    } else if summary.added > 1 {
        parts.append("Importadas \(summary.added) operaciones nuevas")
    } else {
        parts.append("No había operaciones nuevas")
    }
    if summary.alreadyThere > 0 {
        parts.append(summary.alreadyThere == 1 ? "1 ya estaba" : "\(summary.alreadyThere) ya estaban")
    }
    if summary.ignoredRows > 0 {
        parts.append(summary.ignoredRows == 1 ? "1 fila sin acciones ignorada" : "\(summary.ignoredRows) filas sin acciones ignoradas")
    }
    if summary.notTradeRows > 0 {
        let base = summary.notTradeRows == 1 ? "1 fila no aplicada" : "\(summary.notTradeRows) filas no aplicadas"
        let spanish = spanishNotAppliedTypes(summary.notAppliedTypes)
        if spanish.isEmpty {
            parts.append(base)
        } else {
            parts.append("\(base) (\(spanish.joined(separator: ", ")))")
        }
    }
    if summary.unreadableRows > 0 {
        parts.append(summary.unreadableRows == 1 ? "1 fila que no se pudo leer" : "\(summary.unreadableRows) filas que no se pudieron leer")
    }
    return parts.joined(separator: " · ")
}

private func spanishNotAppliedTypes(_ rawTypes: [String]) -> [String] {
    var seen = Set<Int>()
    let labels = ["dividendos", "intereses", "impuestos", "cambios de la empresa", "otros movimientos"]
    for raw in rawTypes {
        let key = raw.uppercased().filter { $0 != "_" && !$0.isWhitespace }
        guard !key.isEmpty else { continue }
        switch key {
        case "DIVIDEND", "DIVIDENDS": seen.insert(0)
        case "INTEREST", "INTERESTS": seen.insert(1)
        case "TAXREFUND", "TAX", "TAXES": seen.insert(2)
        case "CORPORATEACTION", "SPLIT", "REVERSESPLIT", "SPINOFF", "MERGER": seen.insert(3)
        default: seen.insert(4)
        }
    }
    return seen.sorted().map { labels[$0] }
}

/// Errores de importación de cartera (U15).
public enum PortfolioImportFailure: Error, Equatable, Sendable {
    case tooLarge, empty, unreadable, notTradeRepublic, saveFailed
}

/// Mensaje que ve el dueño cuando falla la importación de cartera (U15).
public func portfolioImportMessage(_ failure: PortfolioImportFailure) -> String {
    switch failure {
    case .tooLarge: return "Ese fichero es demasiado grande: pasa de 10 MB."
    case .empty: return "Ese fichero está vacío."
    case .unreadable: return "No pude leer ese fichero. Inténtalo de nuevo."
    case .notTradeRepublic: return "Ese fichero no parece la exportación de Trade Republic."
    case .saveFailed: return "No se pudo guardar. Inténtalo de nuevo."
    }
}

/// Iniciales de la ficha de una posición (U79, A-M2): dos letras, como la lista de Cartera. Con dos palabras o más, la primera
/// letra de cada una de las dos primeras («iShares Core…» → «IC»); con una, sus dos primeras («Apple» → «AP»). Los signos no
/// cuentan.
public func positionInitials(for name: String) -> String {
    let words = name.split(whereSeparator: \.isWhitespace)
        .map { $0.filter { $0.isLetter || $0.isNumber } }
        .filter { !$0.isEmpty }
    if words.count >= 2, let a = words[0].first, let b = words[1].first {
        return "\(a)\(b)".uppercased()
    }
    return String((words.first ?? "").prefix(2)).uppercased()
}
