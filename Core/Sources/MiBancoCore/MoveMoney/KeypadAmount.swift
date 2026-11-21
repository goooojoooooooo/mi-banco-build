import Foundation

/// Estado editable de un importe en euros tecleado dígito a dígito (hasta 99.999,99 €) — U26.
public struct KeypadAmount: Equatable, Sendable {
    public static let maxEuros = 99_999

    public var eurosText: String = ""
    public var hasDecimal: Bool = false
    public var centsText: String = ""

    public init(cents: Int? = nil) {
        guard let cents, cents > 0 else { return }
        let clamped = min(cents, Self.maxEuros * 100 + 99)
        let whole = clamped / 100
        let frac = clamped % 100
        self.eurosText = whole > 0 ? String(whole) : "0"
        if frac > 0 {
            self.hasDecimal = true
            self.centsText = frac % 10 == 0 ? String(frac / 10) : (frac < 10 ? "0\(frac)" : "\(frac)")
        }
    }

    public var cents: Int {
        let whole = Int(eurosText) ?? 0
        let frac: Int
        switch centsText.count {
        case 0: frac = 0
        case 1: frac = (Int(centsText) ?? 0) * 10
        default: frac = Int(centsText.prefix(2)) ?? 0
        }
        return whole * 100 + frac
    }

    public var formattedEUR: String {
        formatEUR(cents)
    }

    /// Texto que ve el dueño mientras teclea (U26): euros con punto de miles + coma y decimales tecleados + « €».
    public var typedText: String {
        let rawEuros = eurosText.isEmpty ? "0" : eurosText
        var grouped = ""
        for (i, ch) in rawEuros.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        let whole = String(grouped.reversed())
        if hasDecimal {
            return "\(whole),\(centsText)\u{00A0}€"
        }
        return "\(whole)\u{00A0}€"
    }

    @discardableResult
    public mutating func tapDigit(_ digit: Int) -> Bool {
        guard (0...9).contains(digit) else { return false }
        if hasDecimal {
            guard centsText.count < 2 else { return false }
            centsText.append(String(digit))
            return true
        }
        if eurosText == "0" {
            let next = digit == 0 ? "0" : String(digit)
            let changed = next != eurosText
            eurosText = next
            return changed
        }
        let candidate = eurosText + String(digit)
        guard let value = Int(candidate), value <= Self.maxEuros else { return false }
        eurosText = candidate
        return true
    }

    @discardableResult
    public mutating func tapComma() -> Bool {
        guard !hasDecimal else { return false }
        if eurosText.isEmpty { eurosText = "0" }
        hasDecimal = true
        return true
    }

    @discardableResult
    public mutating func backspace() -> Bool {
        if hasDecimal {
            if !centsText.isEmpty {
                centsText.removeLast()
            } else {
                hasDecimal = false
            }
            return true
        } else if !eurosText.isEmpty {
            eurosText.removeLast()
            return true
        }
        return false
    }
}
