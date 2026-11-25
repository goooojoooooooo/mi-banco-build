import ActivityKit
import MiBancoCore
import SwiftUI
import WidgetKit

private extension MovementActivityAttributes.ContentState {
    var bankID: BankID? { BankID(rawValue: bank) }
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
        guard balanceCents != nil else { return "Saldo de \(bankName) sin configurar" }
        return "Te quedan \(showsEstimated ? "unos " : "")\(balanceText) en \(bankName)"
    }
    var material: CardMaterial { bankID?.material ?? .all }
}

/// N2: las cifras de la Live Activity cambian con el muelle `snap` del kit (0,46 / 0,74), sobre `numericText`.
private let liveSpring = Animation.spring(response: Theme.Motion.snapSpec.response,
                                          dampingFraction: Theme.Motion.snapSpec.dampingFraction)

/// Logo del comercio (si va en la app) o, si no, el del banco; sin ninguno, una ficha con el símbolo del pago.
private struct ActivityLogo: View {
    let state: MovementActivityAttributes.ContentState
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .background(Color.white)
            } else {
                Image(systemName: state.isIncome ? "arrow.down.left" : "creditcard")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Theme.monogram)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.raised)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var image: UIImage? {
        if let domain = state.logoDomain, let logo = BundledLogos.image(domain: domain) { return logo }
        return state.bankID.flatMap { BundledLogos.image(domain: $0.logoDomain) }
    }
}

/// "estimado" junto al saldo cuando es una estimación.
private struct EstimatedCaption: View {
    var body: some View {
        Text("estimado")
            .font(Theme.font(size: 12))
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
                    ActivityLogo(state: state, size: 44)
                        .padding(.leading, 4)
                        .opacity(stale ? 0.6 : 1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.signedAmount)
                        .font(Theme.font(size: 17, weight: .semibold))
                        .foregroundStyle(stale ? Theme.label2 : state.amountColor)
                        .contentTransition(.numericText(value: Double(state.lastAmountCents)))
                    .animation(liveSpring, value: state.lastAmountCents)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.trailing, 4)
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel(state.spokenAmount)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(stale ? "Último movimiento" : state.headline)
                        .font(Theme.font(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if state.balanceCents != nil {
                            Text("Te quedan\(state.showsEstimated ? " unos" : "")")
                                .font(Theme.font(size: 13))
                                .foregroundStyle(Theme.label2)
                        }
                        Text(state.balanceText)
                            .font(Theme.font(size: state.balanceCents == nil ? 15 : 26, weight: .semibold))
                            .tracking(state.balanceCents == nil ? 0 : -0.5)
                            .foregroundStyle(stale || state.balanceCents == nil ? Theme.label2 : Theme.label)
                            .contentTransition(state.balanceTransition)
                            .animation(liveSpring, value: state.balanceCents)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        Text(state.bankName)
                            .font(Theme.font(size: 13))
                            .foregroundStyle(Theme.label2)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(state.spokenBalance)
                }
            } compactLeading: {
                // N2: si cambia el comercio, su logo entra creciendo desde 0,7.
                ActivityLogo(state: state, size: 22)
                    .id(state.logoDomain ?? state.bank)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.headline)
            } compactTrailing: {
                Text(state.compactAmount)
                    .font(Theme.font(size: 14, weight: .semibold))
                    .foregroundStyle(state.amountColor)
                    .contentTransition(.numericText(value: Double(state.lastAmountCents)))
                    .animation(liveSpring, value: state.lastAmountCents)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.spokenAmount)
            } minimal: {
                ActivityLogo(state: state, size: 22)
                    .opacity(stale ? 0.5 : 1)
                    .accessibilityLabel(state.headline)
            }
            .keylineTint(Theme.label2)
        }
    }
}

/// Pantalla bloqueada: el logo, el comercio y el importe arriba; debajo, grande, lo que te queda en ese banco,
/// sobre el titanio del banco. Caducada, no se apaga entera (fallaría el contraste): las cifras pasan a gris.
private struct LockScreenView: View {
    let state: MovementActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ActivityLogo(state: state, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.headline)
                        .font(Theme.font(size: 17, weight: .semibold))
                        .foregroundStyle(stale ? Theme.label2 : Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(stale ? "Último movimiento" : state.bankName)
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.card2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(state.signedAmount)
                    .font(Theme.font(size: 20, weight: .semibold))
                    .foregroundStyle(stale ? Theme.label2 : state.amountColor)
                    .contentTransition(.numericText(value: Double(state.lastAmountCents)))
                    .animation(liveSpring, value: state.lastAmountCents)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if state.balanceCents != nil {
                    Text("Te quedan\(state.showsEstimated ? " unos" : "")")
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.card2)
                }
                Text(state.balanceText)
                    .font(Theme.font(size: state.balanceCents == nil ? 17 : 30, weight: .semibold))
                    .tracking(state.balanceCents == nil ? 0 : -0.6)
                    .foregroundStyle(stale || state.balanceCents == nil ? Theme.label2 : Theme.label)
                    .contentTransition(state.balanceTransition)
                            .animation(liveSpring, value: state.balanceCents)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if state.balanceCents != nil {
                    Text("en \(state.bankName)")
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.card2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.showsEstimated {
                    EstimatedCaption()
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(state.material.gradient)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.headline), \(state.spokenAmount). \(state.spokenBalance).\(stale ? " Último movimiento." : "")")
    }
}
