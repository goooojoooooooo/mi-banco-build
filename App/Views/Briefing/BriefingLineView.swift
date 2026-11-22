import SwiftUI
import MiBancoCore

/// Pinta una línea del resumen o del asistente a partir de `[BriefingPart]`.
/// - En modo normal, usa `AttributedString` con verde `Theme.income` en variaciones positivas, signo menos tipográfico
///   (`−`, U+2212) y cifras tabulares. Si `countsFirstAmount` está activo (total de «Tu dinero»), el primer importe cuenta
///   desde 0 en 0,9 s (sin mover el resto de la frase; instantáneo con Reducir movimiento).
/// - En modo privado, sustituye cada parte numérica y cualquier importe o porcentaje incrustado por «•••», sin exponer
///   jamás «€» ni «%» ni en pantalla ni en VoiceOver.
struct BriefingLineView: View {
    let parts: [BriefingPart]
    var role: TitanFont = .row
    var color: Color = Theme.label
    var countsFirstAmount: Bool = false
    var snapCountImmediately: Bool = false

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownAmount: Double?

    private static let countUpAnimation = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)

    var body: some View {
        let hidden = preferences.privateMode
        let label = Self.accessibleText(for: parts, hidden: hidden)
        Group {
            if hidden {
                Text(Self.maskedVisualText(for: parts))
                    .foregroundStyle(color)
            } else if countsFirstAmount, !reduceMotion, !snapCountImmediately, let firstCents = firstAmountCents {
                AnimatedBriefingSentence(
                    parts: parts,
                    animatedValue: shownAmount ?? 0,
                    baseColor: color
                )
                .onAppear { startCount(to: firstCents) }
                .onChange(of: firstCents) { _, newValue in
                    withAnimation(Theme.Motion.roll) { shownAmount = Double(newValue) }
                }
            } else {
                Text(Self.attributed(parts: parts, overrideFirstAmount: nil, baseColor: color))
            }
        }
        .titan(role)
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitive()
        .accessibilityLabel(label)
    }

    private var firstAmountCents: Int? {
        for part in parts {
            if case .amount(let cents) = part { return cents }
        }
        return nil
    }

    private func startCount(to target: Int) {
        guard shownAmount == nil else { return }
        shownAmount = 0
        withAnimation(Self.countUpAnimation.delay(0.08)) {
            shownAmount = Double(target)
        }
    }

    /// Texto pintado en modo privado: conserva «•••» y oculta cualquier importe o porcentaje incrustado en texto libre.
    static func maskedVisualText(for parts: [BriefingPart]) -> String {
        render(parts, .masked).replacingOccurrences(
            of: "[+\\-\u{2212}]?[0-9][0-9.,]*[ \u{00A0}\u{202F}]*(?:€|%)",
            with: "•••",
            options: .regularExpression
        )
    }

    /// Etiqueta hablada para VoiceOver: en privado sustituye importes, porcentajes y «•••» por «importe oculto» (U36).
    static func accessibleText(for parts: [BriefingPart], hidden: Bool) -> String {
        guard hidden else { return render(parts, .plain) }
        return privateSpokenText(render(parts, .masked))
    }

    static func attributed(parts: [BriefingPart], overrideFirstAmount: Int?, baseColor: Color) -> AttributedString {
        var out = AttributedString()
        var usedOverride = false
        for part in parts {
            let chunk: String
            var tint = baseColor
            switch part {
            case .text(let text):
                chunk = text
            case .amount(let cents):
                let value: Int
                if let overrideFirstAmount, !usedOverride {
                    usedOverride = true
                    value = overrideFirstAmount
                } else {
                    value = cents
                }
                chunk = uniformMinus(formatEUR(value))
            case .signed(let cents):
                chunk = uniformMinus(formatSignedEUR(cents))
                if cents > 0 { tint = Theme.income }
            case .whole(let cents):
                chunk = uniformMinus(formatEURWhole(cents))
            case .percentTenths(let tenths):
                chunk = uniformMinus(formatPercentTenths(tenths, signed: true))
                if tenths > 0 { tint = Theme.income }
            }
            var segment = AttributedString(chunk)
            segment.foregroundColor = tint
            out.append(segment)
        }
        return out
    }

    private static func uniformMinus(_ text: String) -> String {
        text.hasPrefix("-") ? "\u{2212}" + text.dropFirst() : text
    }
}

/// Dibuja la frase del total animando solo el primer `.amount` de 0 hasta el saldo (cifras tabulares, sin saltos).
private struct AnimatedBriefingSentence: View, Animatable {
    let parts: [BriefingPart]
    var animatedValue: Double
    let baseColor: Color

    nonisolated var animatableData: Double {
        get { animatedValue }
        set { animatedValue = newValue }
    }

    var body: some View {
        Text(BriefingLineView.attributed(
            parts: parts,
            overrideFirstAmount: Int(animatedValue.rounded()),
            baseColor: baseColor
        ))
    }
}
