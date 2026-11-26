import SwiftUI
import MiBancoCore

/// Una categoría del mes: ficha con el símbolo, nombre, importe y la barra blanca del kit (`FillBar`, sin aviso: la mayor
/// del mes la llena), que se llena con un muelle, una fila tras otra, con una marca fina donde quedó el mes anterior; a su
/// lado, el cambio. Un solo elemento para VoiceOver.
struct CategoryRow: View {
    let row: CategoryRowModel
    /// Orden de la fila: escalona el crecimiento de la barra.
    let index: Int
    /// Lo que marca la rayita ("el mes pasado a estas alturas"), para VoiceOver.
    var markName = "el mes anterior"

    @Environment(AppPreferences.self) private var preferences
    /// Cabe «+1.234 %» al tamaño de letra que sea.
    @ScaledMetric(relativeTo: .caption) private var changeWidth: CGFloat = 66

    var body: some View {
        let hidden = preferences.privateMode
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
                    // Con el ojo cerrado no se monta ninguna cifra: la máscara del kit («•••,•• €»), no un desenfoque.
                    Text(hidden ? maskedEUR(row.cents, sign: false) : formatEUR(row.cents))
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .contentTransition(.identity)
                        .privacySensitive()
                }
                HStack(spacing: 10) {
                    SpendBar(name: row.category.displayName, fraction: row.fraction, previous: row.previousFraction, index: index)
                    // Columna fija (aunque no haya cambio): todas las barras comparten escala y se pueden comparar.
                    Text(hidden && row.change != nil ? "•••" : (row.change ?? ""))
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                        .frame(width: changeWidth, alignment: .trailing)
                        .contentTransition(.identity)
                        .privacySensitive()
                }
            }
            // Empuja la pantalla de la categoría.
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.passive)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("gasto.fila.\(row.category.rawValue)")
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

/// La barra de la categoría (`FillBar` sin aviso: siempre blanca) y, encima, la marca de 1 pt del mes anterior.
/// Las categorías entran 0,2 s después de empezar y luego una tras otra (48 ms × 0,86ⁿ), como en la maqueta.
private struct SpendBar: View {
    let name: String
    let fraction: Double
    let previous: Double?
    let index: Int

    var body: some View {
        // Las categorías empiezan a los 0,6 s: terminan después de la línea del gráfico (0,02 + 0,9 s), en el orden de
        // lectura total → gráfico → presupuesto → categorías (ojo de diseño 15.1, menor m-10 del lote 3).
        FillBar(fraction: fraction, warnAt: nil, label: name,
                delay: 0.6 + MotionMath.staggerDelays(count: index + 1, firstGap: 0.048, decay: 0.86)[index])
            .overlay {
                if let previous {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Theme.label2)
                            .frame(width: 1, height: 14)
                            .position(x: min(max(geo.size.width * previous, 0.5), geo.size.width - 0.5), y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
    }
}
