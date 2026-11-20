import SwiftUI
import MiBancoCore

/// Una categoría del mes: ficha con el símbolo, nombre, importe y una barra blanca de 4 pt (la mayor del mes la llena)
/// con una marca fina donde quedó el mes anterior; a su lado, el cambio. Un solo elemento para VoiceOver.
struct CategoryRow: View {
    let row: CategoryRowModel
    /// Orden de la fila: escalona el crecimiento de la barra.
    let index: Int
    /// Lo que marca la rayita ("el mes pasado a estas alturas"), para VoiceOver.
    var markName = "el mes anterior"

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.category.symbolName)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.label)
                .frame(width: 40, height: 40)
                .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.category.displayName)
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(formatEUR(row.cents))
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .privateAmount()
                }
                HStack(spacing: 10) {
                    SpendBar(fraction: row.fraction, previous: row.previousFraction, grown: grown)
                    // Columna fija (aunque no haya cambio): todas las barras comparten escala y se pueden comparar.
                    Text(row.change ?? "")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                        .frame(width: 56, alignment: .trailing)
                        .privateAmount(radius: 6)
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("gasto.fila.\(row.category.rawValue)")
        .onAppear(perform: grow)
    }

    /// La barra crece con el muelle de montaje, una fila tras otra; con Reducir movimiento ya está llena.
    private func grow() {
        guard !grown else { return }
        if reduceMotion {
            grown = true
        } else {
            withAnimation(Theme.Motion.assemble.delay(0.1 + Double(min(index, Theme.Motion.staggerLimit)) * Theme.Motion.staggerStep)) {
                grown = true
            }
        }
    }

    private var spoken: String {
        let hidden = preferences.privateMode
        let amount = spokenAmount(row.cents, hidden: hidden)
        // Con el modo privado el porcentaje está difuminado: tampoco se lee.
        let change = row.spokenChange == nil ? nil : (hidden ? "cambio oculto" : row.spokenChange)
        let mark = row.previousCents.map { "la marca indica \(markName): \(spokenAmount($0, hidden: hidden))" }
        return [row.category.displayName, amount, change, mark].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Barra de 4 pt sobre #1C1C1E; la marca de 1 pt señala el mes anterior.
private struct SpendBar: View {
    let fraction: Double
    let previous: Double?
    let grown: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised).frame(height: 4)
                Capsule()
                    .fill(Theme.label)
                    .frame(width: max(4, width * fraction) * (grown ? 1 : 0.0001), height: 4)
                    .opacity(grown ? 1 : 0)
                if let previous {
                    Rectangle()
                        .fill(Theme.label2)
                        .frame(width: 1, height: 10)
                        .offset(x: min(max(width * previous, 0), width - 1))
                        .opacity(grown ? 1 : 0)
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
