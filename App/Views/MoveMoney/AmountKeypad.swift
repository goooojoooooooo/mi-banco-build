import SwiftUI
import MiBancoCore

/// Estado editable de un importe en euros tecleado dígito a dígito (hasta 99.999,99 €).
/// Pulsar "2", "0", "0" escribe 200,00 €; pulsar "," permite teclear hasta dos decimales.
struct KeypadAmount: Equatable, Sendable {
    static let maxEuros = 99_999

    var eurosText: String = ""
    var hasDecimal: Bool = false
    var centsText: String = ""

    init(cents: Int? = nil) {
        guard let cents, cents > 0 else { return }
        let clamped = min(cents, Self.maxEuros * 100 + 99)
        let whole = clamped / 100
        let frac = clamped % 100
        self.eurosText = whole > 0 ? String(whole) : "0"
        if frac > 0 {
            self.hasDecimal = true
            self.centsText = frac % 10 == 0 ? String(frac / 10) : String(format: "%02d", frac)
        }
    }

    var cents: Int {
        let whole = Int(eurosText) ?? 0
        let frac: Int
        switch centsText.count {
        case 0: frac = 0
        case 1: frac = (Int(centsText) ?? 0) * 10
        default: frac = Int(centsText.prefix(2)) ?? 0
        }
        return whole * 100 + frac
    }

    var formattedEUR: String {
        formatEUR(cents)
    }

    mutating func tapDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if hasDecimal {
            guard centsText.count < 2 else { return }
            centsText.append(String(digit))
            return
        }
        if eurosText == "0" {
            eurosText = digit == 0 ? "0" : String(digit)
            return
        }
        let candidate = eurosText + String(digit)
        guard let value = Int(candidate), value <= Self.maxEuros else { return }
        eurosText = candidate
    }

    mutating func tapComma() {
        guard !hasDecimal else { return }
        if eurosText.isEmpty { eurosText = "0" }
        hasDecimal = true
    }

    mutating func backspace() {
        if hasDecimal {
            if !centsText.isEmpty {
                centsText.removeLast()
            } else {
                hasDecimal = false
            }
        } else if !eurosText.isEmpty {
            eurosText.removeLast()
        }
    }
}

/// Teclado numérico propio de «Mover dinero»: teclas ≥ 44×52 pt, muelle suave y cifra que se vuelve a centrar.
struct AmountKeypad: View {
    @Binding var amount: KeypadAmount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var digitSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 20
    @State private var tapTick = 0

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.comma, .digit(0), .backspace],
    ]

    private enum Key: Hashable {
        case digit(Int)
        case comma
        case backspace

        var label: String {
            switch self {
            case .digit(let n): "\(n)"
            case .comma: ","
            case .backspace: "⌫"
            }
        }

        var spokenLabel: String {
            switch self {
            case .digit(let n): "\(n)"
            case .comma: "Coma decimal"
            case .backspace: "Borrar"
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handle(key)
                        } label: {
                            Group {
                                if key == .backspace {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: iconSize, weight: .medium))
                                } else {
                                    Text(key.label)
                                        .font(.system(size: digitSize, weight: .medium))
                                        .monospacedDigit()
                                }
                            }
                            .foregroundStyle(Theme.label)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.96))
                        .accessibilityLabel(key.spokenLabel)
                        .accessibilityIdentifier(key == .backspace ? "keypad-backspace" : key.label)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: tapTick)
    }

    private func handle(_ key: Key) {
        tapTick += 1
        withAnimation(reduceMotion ? nil : Theme.Motion.morph) {
            switch key {
            case .digit(let n): amount.tapDigit(n)
            case .comma: amount.tapComma()
            case .backspace: amount.backspace()
            }
        }
    }
}
