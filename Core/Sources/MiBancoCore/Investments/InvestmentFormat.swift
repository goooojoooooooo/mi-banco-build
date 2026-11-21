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
