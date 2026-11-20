import SwiftUI
import MiBancoCore

/// «77 de 90 €  85 %» y una barra blanca de 6 pt que se llena con un muelle de montaje (con un pequeño rebote);
/// ámbar solo cuando se llega al límite o se pasa. Con Reducir movimiento, la barra ya está llena y solo cambia de color
/// con un fundido. Un solo elemento para VoiceOver.
struct BudgetBar: View {
    let status: BudgetStatus
    /// Nombre del presupuesto para VoiceOver ("Presupuesto del mes", "Presupuesto de Comer fuera").
    let name: String
    /// Orden: escalona el llenado de la barra.
    var index = 0
    /// Margen a la derecha de «77 de 90 €  85 %» (en Presupuestos, el porcentaje se alinea con el texto del campo).
    var textTrailingInset: CGFloat = 0

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var exceeded: Bool { status.level == .exceeded }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(amounts)
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text("\(status.percent)\u{00A0}%")
                    .titan(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(exceeded ? Theme.warning : Theme.label)
            }
            .padding(.trailing, textTrailingInset)
            .privateAmount(radius: 7)
            GeometryReader { geo in
                let fraction = min(1, Double(status.spentCents) / Double(max(status.limitCents, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule()
                        .fill(exceeded ? Theme.warning : Theme.label)
                        .frame(width: status.spentCents > 0 ? max(6, geo.size.width * fraction) * (grown ? 1 : 0.0001) : 0)
                        .opacity(grown ? 1 : 0)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.quick, value: exceeded)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .onAppear(perform: grow)
    }

    /// «77 de 90 €»: el gastado sin el símbolo y el límite con él.
    private var amounts: String {
        let spent = formatEURWhole(status.spentCents).replacingOccurrences(of: "\u{00A0}€", with: "")
        return "\(spent) de \(formatEURWhole(status.limitCents))"
    }

    private var spoken: String {
        let hidden = preferences.privateMode
        let base = "\(name): \(spokenAmount(status.spentCents, hidden: hidden)) de \(spokenAmount(status.limitCents, hidden: hidden))"
        let level = exceeded ? ", límite superado" : ""
        return hidden ? base + level : "\(base), \(status.percent) por ciento\(level)"
    }

    private func grow() {
        guard !grown else { return }
        if reduceMotion {
            grown = true
        } else {
            withAnimation(Theme.Motion.assemble.delay(0.15 + Double(min(index, Theme.Motion.staggerLimit)) * Theme.Motion.staggerStep)) {
                grown = true
            }
        }
    }
}
