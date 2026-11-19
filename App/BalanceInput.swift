import Foundation

/// Texto de un campo de saldo -> céntimos con signo, o nil si no se entiende.
/// Acepta "-" inicial, miles con punto y 0, 1 o 2 decimales tras `,` o `.` ("340,5" = 340,50).
func parseBalanceInput(_ text: String) -> Int? {
    var s = text.filter { !$0.isWhitespace && $0 != "€" }
    let negative = s.hasPrefix("-")
    if negative { s.removeFirst() }

    var whole = s
    var frac = ""
    if let i = s.lastIndex(where: { $0 == "," || $0 == "." }) {
        let after = s[s.index(after: i)...]
        if after.count <= 2 {
            guard !after.isEmpty else { return nil }
            whole = String(s[..<i])
            frac = String(after)
        }
    }
    guard frac.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }

    let groups = whole.split(separator: ".", omittingEmptySubsequences: false)
    let groupsOK = groups.enumerated().allSatisfy { i, g in
        g.allSatisfy { $0.isASCII && $0.isNumber } && (i == 0 ? (1...(groups.count > 1 ? 3 : 9)).contains(g.count) : g.count == 3)
    }
    let digits = groups.joined()
    guard groupsOK, digits.count <= 9, let euros = Int(digits) else { return nil }

    let cents = euros * 100 + (Int(frac.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
    return negative ? -cents : cents
}
