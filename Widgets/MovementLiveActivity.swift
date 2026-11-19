import ActivityKit
import MiBancoCore
import SwiftUI
import WidgetKit

private extension MovementActivityAttributes.ContentState {
    var bankID: BankID? { BankID(rawValue: bank) }
    var bankColor: Color { bankID?.color ?? Theme.label }
    var bankName: String { bankID?.displayName ?? bank }
    var isIncome: Bool { kind == MovementKind.income.rawValue }
    var signedAmount: String { (lastAmountCents < 0 ? "−" : "+") + formatEUR(abs(lastAmountCents)) }
    /// Para la Dynamic Island compacta (55-65 pt): sin "€" y, desde 100 €, sin céntimos ("−12,50", "+1.450").
    var compactAmount: String {
        let sign = lastAmountCents < 0 ? "−" : "+"
        let magnitude = abs(lastAmountCents)
        var text = formatEUR(magnitude >= 10_000 ? (magnitude + 50) / 100 * 100 : magnitude)
            .replacingOccurrences(of: "\u{00A0}€", with: "")
        if magnitude >= 10_000 { text = text.replacingOccurrences(of: ",00", with: "") }
        return sign + text
    }
    /// Lo que pasó, sin repetir el importe: el comercio o, si no hay, "Pago"/"Ingreso".
    var headline: String { merchant ?? (isIncome ? "Ingreso" : "Pago") }
    var amountColor: Color { isIncome ? Theme.income : Theme.label }
    var balanceText: String { balanceCents.map { formatEUR($0) } ?? "Saldo sin configurar" }
    var balanceTransition: ContentTransition {
        guard let cents = balanceCents else { return .identity }
        return .numericText(value: Double(cents))
    }
    var spokenAmount: String { "\(lastAmountCents < 0 ? "pago de" : "ingreso de") \(formatEUR(abs(lastAmountCents)))" }
    /// Solo con saldo: "estimado" marca que sale de sumar movimientos, no del banco.
    var showsEstimated: Bool { estimated && balanceCents != nil }
    var spokenBalance: String {
        guard balanceCents != nil else { return "Saldo sin configurar" }
        return "Saldo \(showsEstimated ? "estimado " : "")\(balanceText)"
    }
}

/// Etiqueta pequeña junto al saldo cuando es una estimación.
private struct EstimatedCaption: View {
    var body: some View {
        Text("estimado")
            .font(Theme.font(size: 12, relativeTo: .caption))
            .foregroundStyle(Theme.label2)
            .lineLimit(1)
            .fixedSize()
    }
}

struct MovementLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MovementActivityAttributes.self) { context in
            LockScreenView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Theme.canvas)
                .activitySystemActionForegroundColor(Theme.label)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BankTag(name: state.bankName, color: state.bankColor)
                        .padding(.leading, 4)
                        .opacity(stale ? 0.6 : 1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.signedAmount)
                        .font(Theme.font(size: 15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(stale ? Theme.label2 : state.amountColor)
                        .contentTransition(.numericText(value: Double(state.lastAmountCents)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.trailing, 4)
                        .accessibilityLabel(state.spokenAmount)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(state.balanceText)
                                .font(Theme.font(size: state.balanceCents == nil ? 17 : 30, weight: .semibold, relativeTo: .title))
                                .tracking(state.balanceCents == nil ? 0 : -0.6)
                                .foregroundStyle(stale ? Theme.label2 : Theme.label)
                                .contentTransition(state.balanceTransition)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if state.showsEstimated {
                                EstimatedCaption()
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(state.spokenBalance)
                        Text(stale ? "Último movimiento" : state.headline)
                            .font(Theme.font(size: 13, relativeTo: .footnote))
                            .foregroundStyle(Theme.label2)
                            .lineLimit(1)
                        if let bank = state.balanceCents, let total = state.totalCents, bank > 0, total > bank {
                            SplitBar(bank: bank, total: total, color: state.bankColor)
                                .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Capsule()
                    .fill(state.bankColor)
                    .frame(width: 6, height: 16)
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.bankName)
            } compactTrailing: {
                Text(state.compactAmount)
                    .font(Theme.font(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(state.amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.spokenAmount)
            } minimal: {
                Capsule()
                    .fill(state.bankColor)
                    .frame(width: 6, height: 16)
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.bankName)
            }
            .keylineTint(state.bankColor)
        }
    }
}

/// Punto del color del banco y su nombre.
private struct BankTag: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(Theme.font(size: 13, weight: .medium, relativeTo: .footnote))
                .foregroundStyle(Theme.label2)
                .lineLimit(1)
        }
    }
}

/// Pantalla bloqueada: lo que acaba de pasar arriba (comercio e importe), luego el saldo de ese banco.
/// Caducada, no se apaga entera (fallaría el contraste): las cifras pasan a `muted` y el texto lo dice.
private struct LockScreenView: View {
    let state: MovementActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                BankTag(name: state.bankName, color: state.bankColor)
                Spacer(minLength: 8)
                if stale {
                    Text("Último movimiento")
                        .font(Theme.font(size: 13, relativeTo: .footnote))
                        .foregroundStyle(Theme.label2)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(state.headline)
                    .font(Theme.font(size: 17, weight: .medium, relativeTo: .headline))
                    .foregroundStyle(stale ? Theme.label2 : Theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Text(state.signedAmount)
                    .font(Theme.font(size: 20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(stale ? Theme.label2 : state.amountColor)
                    .contentTransition(.numericText(value: Double(state.lastAmountCents)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.balanceText)
                    .font(Theme.font(size: state.balanceCents == nil ? 17 : 30, weight: .semibold, relativeTo: .largeTitle))
                    .tracking(state.balanceCents == nil ? 0 : -0.6)
                    .foregroundStyle(stale || state.balanceCents == nil ? Theme.label2 : Theme.label)
                    .contentTransition(state.balanceTransition)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if state.showsEstimated {
                    EstimatedCaption()
                }
            }
            .padding(.top, 6)
            if let bank = state.balanceCents, let total = state.totalCents, bank > 0, total > bank {
                SplitBar(bank: bank, total: total, color: state.bankColor)
                    .opacity(stale ? 0.5 : 1)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.bankName), \(state.headline), \(state.spokenAmount). \(state.spokenBalance).\(stale ? " Último movimiento." : "")")
    }
}

/// Dos tramos: este banco frente al resto del total. Más simple que `RiverBar`, que necesita el saldo de cada banco.
private struct SplitBar: View {
    let bank: Int
    let total: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                Rectangle()
                    .fill(color)
                    .overlay {
                        LinearGradient(colors: [.white.opacity(0.30), .clear], startPoint: .top, endPoint: .bottom)
                            .blendMode(.softLight)
                    }
                    .frame(width: max(8, (geo.size.width - 3) * Double(bank) / Double(total)))
                Rectangle()
                    .fill(Theme.label.opacity(0.16))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
