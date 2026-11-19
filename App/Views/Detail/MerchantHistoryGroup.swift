import SwiftUI
import MiBancoCore

/// "4 compras este mes, 61,20 €" con los últimos pagos a ese comercio en barras (el actual, en blanco).
struct MerchantHistoryGroup: View {
    let history: MerchantHistory
    /// Últimos pagos al comercio, del más reciente al más antiguo (máx. 4).
    let recent: [Movement]
    let current: UUID

    @Environment(AppPreferences.self) private var preferences
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hidden = preferences.privateMode
        let largest = max(recent.map { abs($0.amountCents) }.max() ?? 1, 1)
        DetailGroup {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(headline)
                    if history.countThisMonth > 0 {
                        Text(", ")
                        Text(formatEUR(history.totalThisMonthCents)).privateAmount()
                    }
                }
                .titan(.option)
                .foregroundStyle(Theme.label)
                Text(subline)
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .padding(.top, 2)
                if recent.count > 1 {
                    VStack(spacing: 7) {
                        ForEach(recent) { m in
                            let isCurrent = m.id == current
                            HStack(spacing: 10) {
                                Text(DateText.day(m.date))
                                    .frame(width: 62, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(isCurrent ? Theme.label : .white.opacity(0.22))
                                        .frame(width: grown ? geo.size.width * CGFloat(abs(m.amountCents)) / CGFloat(largest) : 0, height: 6)
                                        .frame(maxHeight: .infinity)
                                }
                                .frame(height: 16)
                                Text(formatEUR(abs(m.amountCents)))
                                    .frame(minWidth: 66, alignment: .trailing)
                                    .privateAmount()
                            }
                            .titan(.subtitle)
                            .foregroundStyle(isCurrent ? Theme.label : Theme.label2)
                        }
                    }
                    .padding(.top, 10)
                    .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(hidden: hidden))
        .onAppear {
            if reduceMotion {
                grown = true
            } else {
                withAnimation(.smooth(duration: 0.6).delay(0.55)) { grown = true }
            }
        }
    }

    private var headline: String {
        switch history.countThisMonth {
        case 0: "Ninguna compra este mes"
        case 1: "1 compra este mes"
        default: "\(history.countThisMonth) compras este mes"
        }
    }

    private var subline: String {
        guard let first = history.firstDate else { return "Aún no hay historial para comparar" }
        let total = history.countAllTime == 1 ? "1 en total" : "\(history.countAllTime) en total"
        return "\(total), desde el \(DateText.day(first))"
    }

    private func spoken(hidden: Bool) -> String {
        var text = headline
        if history.countThisMonth > 0 { text += ", \(spokenAmount(history.totalThisMonthCents, hidden: hidden))" }
        return text + ". " + subline
    }
}
