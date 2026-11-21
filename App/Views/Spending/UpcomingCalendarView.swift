import SwiftUI
import MiBancoCore

/// Calendario de próximos cobros a 14 días dentro de Gasto (Plan 4b, tarea 16).
/// Agrupa por día suscripciones (incluidas las retrasadas con `overdueNote`), nómina esperada y saldo previsto
/// por banco al final de cada día. Tocar un aviso de saldo insuficiente abre «Mover dinero» ya rellenado.
struct UpcomingCalendarView: View {
    let model: LedgerModel
    let accountBook: AccountBookModel
    let onMoveMoney: (MoveRequest) -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQuietDays = false

    var body: some View {
        let now = Date()
        let cal = DateText.madridCalendar
        let days = upcomingCalendar(state: model.state, book: accountBook.book, now: now, calendar: cal)
        let activeDays = days.filter { !$0.isEmpty || !$0.belowFloor.isEmpty }
        let displayedDays = showQuietDays ? days : activeDays
        let shortfallMap = shortfallLookup(days: days, now: now, calendar: cal)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Previsión de los próximos 14 días según tus suscripciones activas y tus ingresos habituales. No estima el gasto diario.")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if displayedDays.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sin cobros previstos en los próximos 14 días.")
                            .titan(.option)
                            .foregroundStyle(Theme.label)
                        Text("Cuando se detecten suscripciones o una nómina habitual aparecerán aquí.")
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                } else {
                    ForEach(displayedDays, id: \.day) { day in
                        dayCard(day, now: now, calendar: cal, shortfalls: shortfallMap)
                    }
                }

                if activeDays.count < days.count {
                    Button {
                        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                            showQuietDays.toggle()
                        }
                    } label: {
                        Text(showQuietDays ? "Mostrar solo los días con movimientos" : "Ver los 14 días completos")
                            .titan(.subtitle)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.grouped, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Próximos cobros")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayCard(
        _ day: UpcomingDay,
        now: Date,
        calendar: Calendar,
        shortfalls: [BankID: Shortfall]
    ) -> some View {
        let hidden = preferences.privateMode
        let title = dayHeading(day.day, now: now, calendar: calendar)
        let hasWarning = !day.belowFloor.isEmpty

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .titan(.header)
                    .foregroundStyle(hasWarning ? Theme.warning : Theme.label3)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if hasWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("Saldo por debajo del mínimo")
                }
            }

            if day.isEmpty {
                Text("Sin cobros ni ingresos previstos")
                    .titan(.meta)
                    .foregroundStyle(Theme.label3)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(day.expectedIncome.enumerated()), id: \.offset) { idx, income in
                        incomeRow(income, divided: idx > 0, hidden: hidden)
                    }
                    ForEach(Array(day.charges.enumerated()), id: \.offset) { idx, charge in
                        chargeRow(charge, calendar: calendar, divided: idx > 0 || !day.expectedIncome.isEmpty, hidden: hidden)
                    }
                }
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            }

            if !day.belowFloor.isEmpty {
                ForEach(BankID.allCases.filter { day.belowFloor.contains($0) }, id: \.self) { bank in
                    shortfallActionButton(bank: bank, day: day, shortfall: shortfalls[bank], hidden: hidden)
                }
            }

            if !day.balanceAfter.isEmpty {
                balancesFooter(day: day, hidden: hidden)
            }
        }
        .padding(16)
        .background(
            Theme.grouped.opacity(0.65),
            in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
        )
        .overlay {
            if hasWarning {
                RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                    .strokeBorder(Theme.warning.opacity(0.45), lineWidth: 1)
            }
        }
    }

    private func chargeRow(_ charge: UpcomingCharge, calendar: Calendar, divided: Bool, hidden: Bool) -> some View {
        let overdue = overdueNote(charge, calendar: calendar)
        let spoken = "\(charge.name), \(charge.bank.displayName), \(spokenAmount(charge.cents, hidden: hidden))"
            + (overdue.map { ", \($0)" } ?? "")
        return HStack(spacing: 12) {
            BankLogo(bank: charge.bank, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(charge.name)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                if let overdue {
                    Text("\(charge.bank.displayName) · \(overdue)")
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                } else {
                    Text(charge.bank.displayName)
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                }
            }
            Spacer(minLength: 8)
            Text("\u{2212}\(formatEUR(charge.cents))")
                .titan(.option)
                .foregroundStyle(Theme.label)
                .privateAmount()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func incomeRow(_ income: ExpectedIncome, divided: Bool, hidden: Bool) -> some View {
        let spoken = "\(income.name), ingreso estimado en \(income.bank.displayName), \(spokenAmount(income.amountCents, hidden: hidden))"
        return HStack(spacing: 12) {
            BankLogo(bank: income.bank, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(income.name)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                Text("\(income.bank.displayName) · ingreso habitual")
                    .titan(.meta)
                    .foregroundStyle(Theme.label3)
            }
            Spacer(minLength: 8)
            Text("+\(formatEUR(income.amountCents))")
                .titan(.option)
                .foregroundStyle(Theme.income)
                .privateAmount()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func shortfallActionButton(bank: BankID, day: UpcomingDay, shortfall: Shortfall?, hidden: Bool) -> some View {
        let floor = accountBook.book.floors[bank] ?? 0
        let projected = day.balanceAfter[bank] ?? 0
        let missing = max(0, floor - projected)
        let suggestedCents = shortfall?.suggestedCents ?? ((missing + 999) / 1_000 * 1_000)
        let suggestedFrom = shortfall?.suggestedFrom

        let title = suggestedCents > 0
            ? "Pasar \(formatEUR(suggestedCents)) a \(bank.displayName)"
            : "Mover dinero a \(bank.displayName)"
        let shownTitle = hidden ? maskingAmounts(title) : title
        let spokenTitle = hidden
            ? "Mover dinero a \(bank.displayName), saldo previsto por debajo del mínimo"
            : "\(title), saldo previsto por debajo del mínimo"

        return Button {
            onMoveMoney(MoveRequest(
                from: suggestedFrom,
                target: .own(bank),
                amountCents: suggestedCents > 0 ? suggestedCents : nil
            ))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
                Text(shownTitle)
                    .titan(.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTitle)
        .accessibilityAddTraits(.isButton)
    }

    private func balancesFooter(day: UpcomingDay, hidden: Bool) -> some View {
        let ordered = BankID.allCases.filter { day.balanceAfter[$0] != nil }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Saldo previsto al final del día")
                .titan(.caption)
                .foregroundStyle(Theme.label3)
            HStack(spacing: 12) {
                ForEach(ordered, id: \.self) { bank in
                    if let cents = day.balanceAfter[bank] {
                        let estimated = day.estimatedBanks.contains(bank)
                        let below = day.belowFloor.contains(bank)
                        let text = (estimated ? "≈\u{00A0}" : "") + formatEUR(cents).replacingOccurrences(of: "-", with: "\u{2212}")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bank.shortName)
                                .titan(.caption)
                                .foregroundStyle(Theme.label3)
                            Text(text)
                                .titan(.meta)
                                .fontWeight(.medium)
                                .foregroundStyle(below ? Theme.warning : Theme.label2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .privateAmount()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(bank.displayName): \(spokenAmount(cents, hidden: hidden))")
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func dayHeading(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Hoy" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Mañana"
        }
        let weekday = DateText.madridWeekday(date).capitalized
        return "\(weekday), \(DateText.madridDay(date))"
    }

    private func shortfallLookup(days: [UpcomingDay], now: Date, calendar: Calendar) -> [BankID: Shortfall] {
        var balances: [BankID: Int] = [:]
        var estimated = Set<BankID>()
        for bank in BankID.allCases {
            if let info = model.snapshot.balances[bank] {
                balances[bank] = info.cents
                if info.estimated { estimated.insert(bank) }
            }
        }
        let upcoming = days.flatMap(\.charges)
        let list = shortfalls(
            balances: balances,
            floors: accountBook.book.floors,
            upcoming: upcoming,
            now: now,
            calendar: calendar,
            estimated: estimated
        )
        var out: [BankID: Shortfall] = [:]
        for item in list where out[item.bank] == nil {
            out[item.bank] = item
        }
        return out
    }
}
