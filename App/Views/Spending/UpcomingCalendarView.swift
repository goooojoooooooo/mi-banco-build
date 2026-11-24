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
    @Environment(MerchantLogos.self) private var logos
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum CalendarBlock: Identifiable {
        case day(UpcomingDay)
        case quietSpan(first: Date, nextActive: Date?)

        var id: String {
            switch self {
            case .day(let day): "day-\(day.day.timeIntervalSince1970)"
            case .quietSpan(let first, _): "quiet-\(first.timeIntervalSince1970)"
            }
        }
    }

    var body: some View {
        let now = AppClock.now
        let cal = DateText.madridCalendar
        let days = upcomingCalendar(state: model.state, book: accountBook.book, now: now, calendar: cal)
        let topUps = calendarTopUps(days: days, floors: accountBook.book.floors)
        let topUpsByDay = Dictionary(grouping: topUps, by: \.firstDay)
        let hasAnyActivity = days.contains { !$0.isEmpty || !($0.belowFloor.isEmpty) }
        let blocks = buildBlocks(days: days)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Previsión de los próximos 14 días según tus suscripciones activas y tus ingresos habituales. No estima el gasto diario.")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .motionEntrance(0, rise: 8)

                if !hasAnyActivity {
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
                    .motionEntrance(1)
                } else {
                    // La entrada de siempre: cada día sube y aparece tras el anterior (los que pasan del tope, ya colocados).
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        Group {
                            switch block {
                            case .day(let day):
                                daySection(day, allDays: days, topUps: topUpsByDay[day.day] ?? [], now: now, calendar: cal)
                            case .quietSpan(let first, let nextActive):
                                quietSpanRow(first: first, nextActive: nextActive, now: now, calendar: cal)
                            }
                        }
                        .motionEntrance(1 + index)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("upcoming-calendar-scroll")
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Próximos cobros")
        .navigationBarTitleDisplayMode(.inline)
        .assemblesOnFirstAppear()
    }

    private func buildBlocks(days: [UpcomingDay]) -> [CalendarBlock] {
        var result: [CalendarBlock] = []
        var quietStart: Date?
        for day in days {
            let isQuiet = day.isEmpty && day.belowFloor.isEmpty
            if isQuiet {
                if quietStart == nil { quietStart = day.day }
            } else {
                if let start = quietStart {
                    result.append(.quietSpan(first: start, nextActive: day.day))
                    quietStart = nil
                }
                result.append(.day(day))
            }
        }
        if let start = quietStart {
            result.append(.quietSpan(first: start, nextActive: nil))
        }
        return result
    }

    private func quietSpanRow(first: Date, nextActive: Date?, now: Date, calendar: Calendar) -> some View {
        let text: String
        if let next = nextActive {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(next, inSameDayAs: tomorrow) {
                text = "Sin cobros hasta mañana"
            } else {
                let weekday = DateText.madridWeekday(next)
                let dayNumber = calendar.component(.day, from: next)
                text = "Sin cobros hasta el \(weekday) \(dayNumber)"
            }
        } else {
            text = "Sin cobros el resto de los 14 días"
        }
        return Text(text)
            .titan(.meta)
            .foregroundStyle(Theme.label3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }

    private func daySection(
        _ day: UpcomingDay,
        allDays: [UpcomingDay],
        topUps: [CalendarTopUp],
        now: Date,
        calendar: Calendar
    ) -> some View {
        let hidden = preferences.privateMode
        let title = dayHeading(day.day, now: now, calendar: calendar)
        let hasWarning = !day.belowFloor.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
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
            .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 0) {
                if day.isEmpty {
                    Text("Sin cobros ni ingresos previstos")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ForEach(Array(day.expectedIncome.enumerated()), id: \.offset) { idx, income in
                        incomeRow(income, divided: idx > 0, hidden: hidden)
                    }
                    ForEach(Array(day.charges.enumerated()), id: \.offset) { idx, charge in
                        chargeRow(charge, calendar: calendar, divided: idx > 0 || !day.expectedIncome.isEmpty, hidden: hidden)
                    }
                }

                ForEach(topUps, id: \.bank) { topUp in
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    shortfallRow(topUp: topUp, day: day, allDays: allDays, hidden: hidden)
                }

                if !day.balanceAfter.isEmpty && (!day.isEmpty || hasWarning) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
                    balancesFooter(day: day, hidden: hidden)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        }
    }

    private func chargeRow(_ charge: UpcomingCharge, calendar: Calendar, divided: Bool, hidden: Bool) -> some View {
        let overdue = overdueNote(charge, calendar: calendar)
        let domain = merchantDomain(for: charge.name)
        let logo = logos.image(merchant: charge.name, domain: domain, isShop: true)
        let spoken = "\(charge.name), \(charge.bank.displayName), \(spokenAmount(charge.cents, hidden: hidden))"
            + (overdue.map { ", \($0)" } ?? "")
        return HStack(spacing: 12) {
            MerchantTile(image: logo, symbol: "repeat", size: 28)
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
                .privateAmount(spoken: "\u{2212}\(formatEUR(charge.cents))")
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
        let spoken = "\(income.name), ingreso estimado en \(income.bank.displayName), \(spokenAmount(income.cents, hidden: hidden))"
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
            Text("+\(formatEUR(income.cents))")
                .titan(.option)
                .foregroundStyle(Theme.income)
                .privateAmount()
                .accessibilityLabel(hidden ? "importe oculto" : "+\(formatEUR(income.cents))")
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

    @ViewBuilder
    private func shortfallRow(topUp: CalendarTopUp, day: UpcomingDay, allDays: [UpcomingDay], hidden: Bool) -> some View {
        let bank = topUp.bank
        if let waiting = waitingPendingMove(to: bank) {
            let shown = hidden
                ? "Ya tienes preparado un traspaso a \(bank.displayName)."
                : "Ya tienes preparado un traspaso de \(formatEUR(waiting.amountCents)) a \(bank.displayName)."
            let spoken = hidden
                ? "Ya tienes preparado un traspaso a \(bank.displayName)."
                : "Ya tienes preparado un traspaso de \(spokenAmount(waiting.amountCents, hidden: false)) a \(bank.displayName)."
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label2)
                    .accessibilityHidden(true)
                Text(shown)
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitive()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        } else {
            shortfallActionButton(topUp: topUp, day: day, allDays: allDays, hidden: hidden)
        }
    }

    private func waitingPendingMove(to bank: BankID) -> PendingMove? {
        model.pendingMoves.first { move in
            guard move.target == .own(bank) else { return false }
            if case .done = model.pendingMoveStates[move.id] { return false }
            return true
        }
    }

    private func shortfallActionButton(topUp: CalendarTopUp, day: UpcomingDay, allDays: [UpcomingDay], hidden: Bool) -> some View {
        let bank = topUp.bank
        let suggestedCents = topUp.suggestedCents
        let estimated = day.estimatedBanks.contains(bank) || (model.snapshot.balances[bank]?.estimated == true)
        let suggestedFrom = suggestedSource(for: bank, amountCents: suggestedCents, allDays: allDays)

        let approx = estimated ? "≈ " : ""
        let title = suggestedCents > 0
            ? "Pasar \(approx)\(formatEUR(suggestedCents)) a \(bank.displayName)"
            : "Mover dinero a \(bank.displayName)"
        let shownTitle = hidden ? maskingAmounts(title) : title
        let spokenTitle: String = {
            if hidden || suggestedCents <= 0 {
                return "Mover dinero a \(bank.displayName), saldo previsto por debajo del mínimo"
            }
            let spokenApprox = estimated ? "aproximadamente " : ""
            return "Pasar \(spokenApprox)\(spokenAmount(suggestedCents, hidden: false)) a \(bank.displayName), saldo previsto por debajo del mínimo"
        }()

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
                    .privacySensitive()
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(background: Theme.raised))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenTitle)
        .accessibilityAddTraits(.isButton)
    }

    private func balancesFooter(day: UpcomingDay, hidden: Bool) -> some View {
        let ordered = BankID.allCases.filter { day.balanceAfter[$0] != nil }
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            Text("Saldo previsto al final del día")
                .titan(.caption)
                .foregroundStyle(Theme.label3)
            layout {
                ForEach(ordered, id: \.self) { bank in
                    if let cents = day.balanceAfter[bank] {
                        let estimated = day.estimatedBanks.contains(bank)
                        let below = day.belowFloor.contains(bank)
                        let text = (estimated ? "≈\u{00A0}" : "") + formatEUR(cents).replacingOccurrences(of: "-", with: "\u{2212}")
                        let spokenParts = [
                            bank.displayName,
                            spokenAmount(cents, hidden: hidden),
                            estimated ? "estimado" : nil,
                            below ? "por debajo del mínimo" : nil,
                        ].compactMap { $0 }
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
                                .accessibilityLabel(hidden ? "importe oculto" : text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(spokenParts.joined(separator: ", "))
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

    private func suggestedSource(for destination: BankID, amountCents: Int, allDays: [UpcomingDay]) -> BankID? {
        guard amountCents > 0 else { return nil }
        var balances: [BankID: Int] = [:]
        var estimated = Set<BankID>()
        for bank in BankID.allCases where bank != destination {
            if let info = model.snapshot.balances[bank] {
                balances[bank] = info.cents
                if info.estimated { estimated.insert(bank) }
            }
        }
        // Misma ventana de 7 días que usa `MoveMoneySheet` para que el origen sugerido nunca salga «no llega» en la hoja (U21).
        let charges = Array(allDays.prefix(7).flatMap(\.charges))
        return whereToPay(
            amountCents: amountCents,
            balances: balances,
            floors: accountBook.book.floors,
            upcoming: charges,
            included: Set(BankID.allCases.filter { $0 != destination }),
            estimated: estimated
        ).first(where: \.fits)?.bank
    }
}
