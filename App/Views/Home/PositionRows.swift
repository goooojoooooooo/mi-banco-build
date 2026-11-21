import SwiftUI
import MiBancoCore

/// Lista de posiciones de la tarjeta «Cartera» en Inicio (Plan 4b, tarea 7).
/// Filas de 64 pt con monograma, acciones, cambio del día, valor y ganancia; todo ocultable con el ojo.
struct PositionRows: View {
    let summary: PortfolioSummary
    let onOpen: (String) -> Void

    var body: some View {
        let count = summary.positions.count
        let header = count == 1 ? "1 posición" : "\(count) posiciones"
        Text(header)
            .titan(.header)
            .foregroundStyle(Theme.label3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .staggeredEntrance(3, listIndex: 0)

        ForEach(Array(summary.positions.enumerated()), id: \.element.id) { index, value in
            PositionRowView(
                value: value,
                isLast: index == summary.positions.count - 1,
                onOpen: { onOpen(value.position.instrument) }
            )
            .staggeredEntrance(4 + index, listIndex: 1 + index)
        }
    }
}

private struct PositionRowView: View {
    let value: PositionValue
    let isLast: Bool
    let onOpen: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    private var positionChangeDay: Date? {
        guard case .market(let at) = value.origin else { return nil }
        return DateText.madridCalendar.startOfDay(for: at)
    }

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        Button(action: onOpen) {
            layout {
                HStack(spacing: 14) {
                    PositionMonogramTile(name: value.position.name, size: tileSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.position.name)
                            .titan(.row)
                            .foregroundStyle(Theme.label)
                            .lineLimit(stacked ? nil : 1)
                        subtitleView(stacked: stacked)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                    if let cents = value.valueCents {
                        Text(formatEUR(cents).replacingOccurrences(of: "-", with: "\u{2212}"))
                            .titan(.row)
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .fixedSize()
                            .privateAmount()
                    } else {
                        Text("Sin precio")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label3)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    if let gainCents = value.gainCents {
                        Text(gainLabel(cents: gainCents, tenths: value.gainTenths))
                            .titan(.meta)
                            .foregroundStyle(gainCents > 0 ? Theme.income : Theme.label2)
                            .lineLimit(1)
                            .fixedSize()
                            .privateAmount()
                    }
                }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Abre el detalle de la posición")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(value.position.name)
    }

    @ViewBuilder
    private func subtitleView(stacked: Bool) -> some View {
        let shares = sharesText(value.position.shares)
        let sessionLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 4))
        sessionLayout {
            Text(shares)
                .privateAmount()
            if let tenths = PositionFormatting.todayTenths(for: value), let day = positionChangeDay {
                if !stacked { Text("·") }
                Text("\(formatPercentTenths(tenths, signed: true).replacingOccurrences(of: "-", with: "\u{2212}")) \(PositionFormatting.sessionShortLabel(changeDay: day))")
                    .foregroundStyle(tenths > 0 ? Theme.income : Theme.label3)
                    .privateAmount()
            }
        }
        .titan(.subtitle)
        .foregroundStyle(Theme.label3)
        .lineLimit(stacked ? nil : 1)
    }

    private func sharesText(_ shares: Decimal) -> String {
        let formatted = formatShares(shares)
        return shares == 1 ? "1 acción" : "\(formatted) acciones"
    }

    private func gainLabel(cents: Int, tenths: Int?) -> String {
        let eur = formatSignedEUR(cents).replacingOccurrences(of: "-", with: "\u{2212}")
        guard let tenths else { return eur }
        let pct = formatPercentTenths(tenths, signed: true).replacingOccurrences(of: "-", with: "\u{2212}")
        return "\(eur) (\(pct))"
    }

    private var spokenLabel: String {
        if preferences.privateMode {
            return "\(value.position.name), importe oculto"
        }
        var parts = [value.position.name]
        if let cents = value.valueCents {
            parts.append(spokenAmount(cents, hidden: false))
        } else {
            parts.append("sin precio")
        }
        parts.append(sharesText(value.position.shares))
        if let gainCents = value.gainCents {
            let prefix = gainCents >= 0 ? "ganancia de" : "pérdida de"
            parts.append("\(prefix) \(spokenAmount(abs(gainCents), hidden: false))")
        }
        return parts.joined(separator: ", ")
    }
}

/// Ficha de monograma (1–2 letras) para valores de inversión.
struct PositionMonogramTile: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.monogram)
            .frame(width: size, height: size)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: size > 48 ? Theme.Radius.logoLarge : Theme.Radius.logo, style: .continuous))
            .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { !$0.isEmpty }
        if words.count >= 2, let a = words[0].first, let b = words[1].first {
            return "\(a)\(b)".uppercased()
        }
        let letters = name.filter { $0.isLetter || $0.isNumber }
        return String(letters.prefix(2)).uppercased()
    }
}

/// Ayudas compartidas de formato para la tarjeta de inversiones, filas y hoja de posición.
/// Todas las fechas y horas se calculan y formatean en zona horaria `Europe/Madrid` (J10).
enum PositionFormatting {
    /// Décimas de porcentaje del cambio del día de una posición individual.
    static func todayTenths(for value: PositionValue) -> Int? {
        guard let current = value.valueCents, let change = value.todayChangeCents else { return nil }
        let previous = current - change
        guard previous > 0 else { return nil }
        let q = Int((change.magnitude * 2_000 + previous.magnitude) / (previous.magnitude * 2))
        return change < 0 ? -q : q
    }

    /// "hoy" si `changeDay` cae en hoy (Madrid); si no, el día de la semana ("viernes") según J10.
    static func sessionShortLabel(changeDay: Date, now: Date = Date()) -> String {
        if DateText.madridCalendar.isDate(changeDay, inSameDayAs: now) { return "hoy" }
        return DateText.madridWeekday(changeDay)
    }

    /// "hoy" o "en la última sesión (viernes)" (J10).
    static func sessionPhrase(changeDay: Date, now: Date = Date()) -> String {
        if DateText.madridCalendar.isDate(changeDay, inSameDayAs: now) { return "hoy" }
        return "en la última sesión (\(DateText.madridWeekday(changeDay)))"
    }

    /// "precios de las 17:35", "precio de ayer, 17:35" o "precios del 17 nov" (hora de Madrid).
    static func priceTimestamp(_ date: Date, plural: Bool = true, now: Date = Date()) -> String {
        let time = DateText.madridTime(date)
        if DateText.madridCalendar.isDate(date, inSameDayAs: now) {
            return plural ? "precios de las \(time)" : "precio de las \(time)"
        }
        if let yesterday = DateText.madridCalendar.date(byAdding: .day, value: -1, to: now),
           DateText.madridCalendar.isDate(date, inSameDayAs: yesterday) {
            return plural ? "precios de ayer, \(time)" : "precio de ayer, \(time)"
        }
        let day = DateText.madridDay(date)
        return plural ? "precios del \(day)" : "precio del \(day)"
    }
}
