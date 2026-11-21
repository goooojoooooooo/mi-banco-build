import SwiftUI
import MiBancoCore

/// Teclado numérico propio de «Mover dinero»: teclas ≥ 44×52 pt, muelle suave y cifra que se vuelve a centrar.
/// `KeypadAmount` vive ahora en `MiBancoCore` (U26); las teclas ignoradas disparan háptica de error.
struct AmountKeypad: View {
    @Binding var amount: KeypadAmount
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var digitSize: CGFloat = 24
    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 20
    @State private var tapTick = 0
    @State private var errorTick = 0

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
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private func handle(_ key: Key) {
        var changed = false
        withAnimation(reduceMotion ? nil : Theme.Motion.morph) {
            switch key {
            case .digit(let n): changed = amount.tapDigit(n)
            case .comma: changed = amount.tapComma()
            case .backspace: changed = amount.backspace()
            }
        }
        if changed {
            tapTick += 1
        } else {
            errorTick += 1
        }
    }
}
