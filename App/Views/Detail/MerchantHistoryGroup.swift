import SwiftUI
import MiBancoCore

/// "4 compras este mes, 61,20 €" con los últimos pagos a ese comercio en barras (el actual, en blanco).
struct MerchantHistoryGroup: View {
    let history: MerchantHistory
    /// Últimos pagos al comercio, del más reciente al más antiguo (máx. 4).
    let recent: [Movement]
    let current: UUID

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let hidden = preferences.privateMode
        let largest = max(recent.map { abs($0.amountCents) }.max() ?? 1, 1)
        DetailGroup {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(headline)
                    if history.countThisMonth > 0 {
                        Text(", ")
                        // Con el ojo cerrado no se monta la cifra: se dibuja su máscara.
                        MaskedText(cents: history.totalThisMonthCents, hidden: hidden)
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
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, m in
                            let isCurrent = m.id == current
                            HStack(spacing: 10) {
                                Text(DateText.day(m.date))
                                    .frame(width: 62, alignment: .leading)
                                GeometryReader { geo in
                                    HistoryBar(
                                        index: index, color: isCurrent ? Theme.label : .white.opacity(0.22),
                                        width: geo.size.width * CGFloat(abs(m.amountCents)) / CGFloat(largest))
                                        .frame(maxHeight: .infinity)
                                }
                                .frame(height: 16)
                                // I-1: la barra nunca sale de su hueco (no pisa el importe de al lado).
                                .clipped()
                                MaskedText(cents: abs(m.amountCents), hidden: hidden)
                                    .frame(minWidth: 66, alignment: .trailing)
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

/// Una barra del historial: crece desde la izquierda (escala, no ancho: nada de maquetación animada) con un muelle,
/// 40 ms detrás de la anterior, desde 0,38 s (D1). Con Reducir movimiento ya está entera. Lee `\.motion`.
private struct HistoryBar: View {
    let index: Int
    let color: Color
    let width: CGFloat
    @Environment(\.motion) private var motion
    @State private var grown = false

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: max(width, 0), height: 6)
            .scaleEffect(x: grown || motion.reduce ? 1 : 0.001, y: 1, anchor: .leading)
            .onAppear {
                // m-3: con Reducir movimiento ya está entera, y se queda así aunque Reducir se apague con la hoja abierta.
                guard !motion.reduce else {
                    grown = true
                    return
                }
                let delay = motion.seconds(0.38) + motion.seconds(0.04) * Double(index)
                // I-1: crece sin pasarse (un muelle sin rebote): con rebote, la más larga atravesaba su importe y
                // parecía tachado como «No es mío» (run10 `row-detail` 11–15).
                withAnimation(motion.calmAnimation(.release).delay(delay)) { grown = true }
            }
    }
}
