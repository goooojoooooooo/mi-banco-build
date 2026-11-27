import SwiftUI
import MiBancoCore

/// "Gastado en 7 días" con su cifra, una tira de 7 barras (hoy en blanco, el pico rotulado) y, debajo,
/// el ritmo del mes ("Este mes 412,30 €, 85,70 € menos que en octubre") o, en un banco, el estado de su saldo.
struct WeekBlock: View {
    let card: AccountCard
    let week: WeekSpend
    let pace: PaceLine?
    let balance: BalanceInfo?

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.entrance) private var entrance
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var barArea: CGFloat = 40

    /// Cuenta desde 0 solo dentro del montaje de Inicio y con el ojo abierto; en un cambio de tarjeta, fuera de una
    /// entrada o con el ojo cerrado sale con su cifra (la máscara). Así, si el ojo se abre a mitad del montaje, la cifra
    /// aparece en el acto (barajado → cifra) y no se queda invisible esperando a una cuenta que no empezó.
    private var countsOnAssembly: Bool {
        var eyeOpen = !preferences.privateMode
        #if DEBUG
        if DemoMode.oldWeekCount { eyeOpen = true }
        #endif
        return entrance.active && entrance.scope == .assembly && eyeOpen
    }

    var body: some View {
        let hidden = preferences.privateMode
        let stacked = typeSize.isAccessibilitySize
        let headerLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.row))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: Theme.Space.row))
        VStack(alignment: .leading, spacing: 0) {
            headerLayout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.bank.map { "Gastado en 7 días · \($0.shortName)" } ?? "Gastado en 7 días")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .fixedSize(horizontal: false, vertical: true)
                    // Un importe por tarjeta (`.id(card)`): al cambiar de tarjeta se monta de nuevo y sale ya con el suyo,
                    // con la lista (nunca enseña un instante la cifra de la otra tarjeta, ni rueda de una a otra, ni un
                    // «0,00 €»). Al montarse Inicio (arranque o desbloqueo) cuenta desde 0 como las cifras de la tarjeta
                    // (su fila aún está oculta mientras el kit espera para rodar). Llega un movimiento: rueda a la cifra
                    // nueva. Con el ojo cerrado dibuja «•••,•• €».
                    RollingAmount(cents: week.totalCents, countsUp: countsOnAssembly)
                        .titan(.week)
                        .id(card)
                        #if DEBUG
                        // Sonda: un importe que espera a contar con el ojo cerrado se quedaría invisible al abrirlo.
                        .onChange(of: countsOnAssembly && preferences.privateMode, initial: true) { _, waitsHidden in
                            if waitsHidden { HomeProbe.shared.weekCountsWhileHidden += 1 }
                        }
                        #endif
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gastado en 7 días: \(spokenAmount(week.totalCents, hidden: hidden)). \(hidden ? "" : week.summary)")
                if !stacked { Spacer(minLength: 0) }
                WeekBars(week: week, barArea: barArea, stacked: stacked)
                    .accessibilityHidden(true)
            }
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.top, Theme.Space.row)
            footnote
                .titan(.subtitle)
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.row)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, Theme.Space.gutter)
        .padding(.bottom, Theme.Space.tight)
    }

    @ViewBuilder
    private var footnote: some View {
        if card == .all, let pace {
            PaceLineSwap(pace: pace)
        } else if card != .all {
            Text(balanceFootnote)
        }
    }

    private var balanceFootnote: String {
        guard let balance else { return "Sin saldo: escríbelo en Ajustes" }
        switch balance.origin {
        case .bank:
            return balance.estimated ? "Saldo estimado desde el banco" : "Saldo exacto del banco"
        case .statement:
            return balance.estimated ? "Saldo estimado desde el extracto" : "Saldo exacto del extracto"
        case .notice, .manual:
            return balance.estimated ? "Saldo estimado: corrígelo en Ajustes" : "Saldo exacto del último aviso"
        }
    }
}

/// La frase del mes cuando cambia (llega un movimiento): no cambia de golpe antes que nada se mueva. Espera a que la
/// fila nueva aterrice (0,2 s), se apaga en 0,1 s, cambia y vuelve en 0,1 s: nunca dos frases a la vez. Con Reducir
/// movimiento, el mismo fundido sin espera. Solo cambia la opacidad.
private struct PaceLineSwap: View {
    let pace: PaceLine
    @Environment(\.motion) private var motion
    @State private var shown: PaceLine?
    @State private var visible = true

    var body: some View {
        PaceSentence(pace: shown ?? pace)
            .opacity(visible ? 1 : 0)
            .onChange(of: pace) { _, new in
                let wait = motion.reduce ? 0 : motion.seconds(0.2)
                withAnimation(.easeIn(duration: motion.seconds(0.1)).delay(wait)) {
                    visible = false
                } completion: {
                    shown = new
                    withAnimation(.easeOut(duration: motion.seconds(0.1))) { visible = true }
                }
            }
            .onAppear { shown = pace }
    }
}

/// "Este mes 412,30 €, 85,70 € menos que en octubre": la diferencia en blanco. Con el ojo cerrado los dos importes son
/// su máscara («•••,•• €»): la cifra no se monta bajo un desenfoque. Va en un solo `Text` fluido para que, con texto
/// grande, salte por palabras completas sin partir ningún importe en columnas estrechas («287,5 / 2 €»).
private struct PaceSentence: View {
    let pace: PaceLine
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize

    private var usesLegacyColumns: Bool {
        #if DEBUG
        return DemoMode.oldHomeAX
        #else
        return false
        #endif
    }

    var body: some View {
        let hidden = preferences.privateMode
        let stacked = typeSize.isAccessibilitySize
        let monthText = hidden ? maskedEUR(pace.thisMonthCents, sign: false) : formatEUR(pace.thisMonthCents)
        let diffText = pace.differenceCents.map { diff in
            hidden ? maskedEUR(abs(diff), sign: false) : formatEUR(abs(diff))
        }
        Group {
            if usesLegacyColumns {
                legacyColumns
            } else {
                flowingText(monthText: monthText, diffText: diffText)
                    .contentTransition(.identity)
                    .privacySensitive()
                    .lineLimit(stacked ? nil : 2)
                    .minimumScaleFactor(stacked ? 1 : 0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .auditDrawnAmount(monthText, hidden: hidden)
                    .auditDrawnAmount(diffText, hidden: hidden)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(hidden: hidden))
        .accessibilityIdentifier("home-pace-sentence")
        #if DEBUG
        .onAppear { HomeProbe.shared.paceSingleBlock = !usesLegacyColumns }
        #endif
    }

    private func flowingText(monthText: String, diffText: String?) -> Text {
        if let diff = pace.differenceCents {
            if diff == 0 {
                return Text("Este mes \(Text(verbatim: monthText)), igual que en \(pace.previousMonthName)")
            }
            let shownDiff = diffText ?? ""
            let tail = diff < 0 ? " menos que en \(pace.previousMonthName)" : " más que en \(pace.previousMonthName)"
            return Text("Este mes \(Text(verbatim: monthText)), \(Text(verbatim: shownDiff).foregroundStyle(Theme.label))\(tail)")
        }
        return Text("Este mes \(Text(verbatim: monthText))")
    }

    /// Solo para `-MiBancoDemoOldHomeAX` (DEBUG): el `HStack` de antes que partía los importes en columnas estrechas.
    @ViewBuilder
    private var legacyColumns: some View {
        HStack(spacing: 0) {
            Text("Este mes ")
            MaskedAmountText(formatEUR(pace.thisMonthCents), masked: maskedEUR(pace.thisMonthCents, sign: false))
            if let diff = pace.differenceCents {
                if diff == 0 {
                    Text(", igual que en \(pace.previousMonthName)")
                } else {
                    Text(", ")
                    MaskedAmountText(formatEUR(abs(diff)), masked: maskedEUR(abs(diff), sign: false))
                        .foregroundStyle(Theme.label)
                    Text(diff < 0 ? " menos que en \(pace.previousMonthName)" : " más que en \(pace.previousMonthName)")
                }
            }
        }
        .lineLimit(2)
        .minimumScaleFactor(0.85)
    }

    private func spoken(hidden: Bool) -> String {
        var text = "Este mes, \(spokenAmount(pace.thisMonthCents, hidden: hidden))"
        if let diff = pace.differenceCents, diff != 0 {
            text += ", \(spokenAmount(abs(diff), hidden: hidden)) \(diff < 0 ? "menos" : "más") que en \(pace.previousMonthName) a estas alturas"
        }
        return text
    }
}

/// Siete barras de 10 pt (máx. 40 pt) con su inicial; hoy en blanco y el día que más, con su cifra encima (con el ojo
/// cerrado, «•••»: la cifra no se monta).
private struct WeekBars: View {
    let week: WeekSpend
    let barArea: CGFloat
    var stacked = false
    @Environment(\.motion) private var motion

    var body: some View {
        if stacked {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week.days) { day in
                    let isToday = day.id == 6
                    VStack(spacing: 6) {
                        Group {
                            if day.id == week.peakID {
                                MaskedAmountText(roundedEUR(day.cents), masked: "•••")
                                    .titan(.captionStrong)
                                    .foregroundStyle(Theme.label2)
                                    .lineLimit(1)
                                    .fixedSize()
                            } else {
                                Text(" ")
                                    .titan(.captionStrong)
                                    .hidden()
                            }
                        }
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(height: min(barArea, 64))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isToday ? Theme.label : Theme.barIdle)
                                .frame(width: 12, height: height(day, maxArea: min(barArea, 64)))
                        }
                        Text(day.initial)
                            .titan(.captionStrong)
                            .foregroundStyle(isToday ? Theme.label : Theme.label3)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .animation(motion.calmAnimation(.row), value: week)
        } else {
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(week.days) { day in
                    let isToday = day.id == 6
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            Color.clear.frame(width: 14, height: barArea)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isToday ? Theme.label : Theme.barIdle)
                                .frame(width: 10, height: height(day, maxArea: barArea))
                                .overlay(alignment: .top) {
                                    if day.id == week.peakID {
                                        MaskedAmountText(roundedEUR(day.cents), masked: "•••")
                                            .titan(.captionStrong)
                                            .foregroundStyle(Theme.label2)
                                            .fixedSize()
                                            .offset(y: -18)
                                    }
                                }
                        }
                        Text(day.initial)
                            .titan(.captionStrong)
                            .foregroundStyle(isToday ? Theme.label : Theme.label3)
                    }
                }
            }
            // Las barras cambian de alto con el muelle de fila, sin rebote (con Reducir movimiento, un fundido).
            .animation(motion.calmAnimation(.row), value: week)
        }
    }

    private func height(_ day: WeekSpend.Day, maxArea: CGFloat) -> CGFloat {
        guard week.maxCents > 0 else { return 3 }
        return max(3, maxArea * CGFloat(day.cents) / CGFloat(week.maxCents))
    }

    /// "73 €" (redondeado a partir de 10 €), "4,50 €" por debajo.
    private func roundedEUR(_ cents: Int) -> String {
        guard cents >= 1_000 else { return formatEUR(cents) }
        return "\((cents + 50) / 100)\u{00A0}€"
    }
}
