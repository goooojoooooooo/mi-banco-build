import MiBancoCore
import SwiftUI

/// Una entrada de «Movimientos» en la hoja de un banco: la cabecera de un día o un movimiento.
/// Las filas enseñan lo mismo que las de Inicio (logo, comercio, subtítulo, importe con su signo y su color) y abren el
/// mismo detalle, pero aquí el importe, con el ojo cerrado, es la máscara del kit («−•••,•• €»): no se monta ninguna
/// cifra (las filas de Inicio todavía dejan la cifra montada bajo un desenfoque, que una prueba de toque puede leer).
struct BankMovementEntry: View {
    let entry: ListEntry
    let logoDomain: String?
    let onOpen: (UUID) -> Void

    var body: some View {
        switch entry.kind {
        case let .header(title, isFirst):
            Text(title)
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, isFirst ? 14 : 22)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
        case let .row(row, isLast):
            if case .movement(let movement) = row.item {
                BankMovementRow(movement: movement, row: row, logoDomain: logoDomain, isLast: isLast) { onOpen(movement.id) }
            }
        }
    }
}

/// Fila de un movimiento en la hoja de un banco. Un solo elemento para VoiceOver, con la misma lectura que en Inicio.
private struct BankMovementRow: View {
    let movement: Movement
    let row: ListRow
    let logoDomain: String?
    let isLast: Bool
    let onOpen: () -> Void

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    var body: some View {
        let hidden = preferences.privateMode
        let logo = logos.image(merchant: movement.merchant, domain: logoDomain, isShop: movement.isShop)
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        Button(action: onOpen) {
            layout {
                HStack(spacing: 14) {
                    MerchantTile(image: logo, symbol: movement.fallbackSymbol, size: tileSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .titan(.row)
                            .foregroundStyle(Theme.label)
                            .lineLimit(stacked ? nil : 1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .titan(.subtitle)
                                .foregroundStyle(row.unconfirmed && row.subtitle.isEmpty ? Theme.warning : Theme.label3)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Con el ojo cerrado, la máscara del kit con su signo: ninguna cifra montada.
                Text(hidden ? maskedEUR(movement.amountCents, sign: true) : signed)
                    .titan(.row)
                    .foregroundStyle(amountColor)
                    .strikethrough(movement.flaggedNotMine, color: Theme.label3)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.identity)
                    .privacySensitive()
                    .accessibilityLabel(hidden ? "importe oculto" : signed)
                    .padding(.leading, stacked ? tileSize + 14 : 0)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 0.5)
                    .padding(.leading, stacked ? Theme.Space.gutter : Theme.Space.gutter + tileSize + 14)
                    .opacity(isLast ? 0 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .task(id: movement.merchant) {
            logos.requestIfNeeded(for: movement, domain: logoDomain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Abre el detalle")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("movementRow")
    }

    /// «−12,50 €» o «+1.450,00 €».
    private var signed: String {
        (movement.amountCents < 0 ? "\u{2212}" : "+") + formatEUR(abs(movement.amountCents))
    }

    private var subtitle: String {
        if row.unconfirmed {
            return row.subtitle.isEmpty ? "Sin confirmar por el banco" : "\(row.subtitle) · Sin confirmar por el banco"
        }
        return row.subtitle
    }

    private var amountColor: Color {
        if movement.flaggedNotMine { return Theme.label3 }
        return movement.amountCents > 0 ? Theme.income : Theme.label
    }

    private var spoken: String {
        let what = movement.amountCents < 0 ? "pago de" : "ingreso de"
        var text = "\(row.title), \(what) \(spokenAmount(abs(movement.amountCents), hidden: preferences.privateMode)). "
        text += "\(movement.bank.displayName), \(DateText.moment(movement.date, dayOnly: movement.dayOnly))"
        if let note = movement.note { text += ". Nota: \(note)" }
        if movement.bankStatus == .pending { text += ". Pendiente" }
        if row.unconfirmed { text += ". Sin confirmar por el banco" }
        if movement.flaggedNotMine { text += ". Marcado como no es mío" }
        return text
    }
}
