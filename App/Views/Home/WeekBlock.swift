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
    @ScaledMetric(relativeTo: .caption) private var barArea: CGFloat = 40

    var body: some View {
        let hidden = preferences.privateMode
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Theme.Space.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.bank.map { "Gastado en 7 días · \($0.shortName)" } ?? "Gastado en 7 días")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                    // Rueda al cambiar de tarjeta o al llegar un movimiento; con el ojo cerrado dibuja «•••,•• €».
                    RollingAmount(cents: week.totalCents)
                        .titan(.week)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Gastado en 7 días: \(spokenAmount(week.totalCents, hidden: hidden)). \(hidden ? "" : week.summary)")
                Spacer(minLength: 0)
                WeekBars(week: week, barArea: barArea)
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
/// su máscara («•••,•• €»): la cifra no se monta bajo un desenfoque.
private struct PaceSentence: View {
    let pace: PaceLine
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let hidden = preferences.privateMode
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(hidden: hidden))
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
    @Environment(\.motion) private var motion

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            ForEach(week.days) { day in
                let isToday = day.id == 6
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(width: 14, height: barArea)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isToday ? Theme.label : Theme.barIdle)
                            .frame(width: 10, height: height(day))
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

    private func height(_ day: WeekSpend.Day) -> CGFloat {
        guard week.maxCents > 0 else { return 3 }
        return max(3, barArea * CGFloat(day.cents) / CGFloat(week.maxCents))
    }

    /// "73 €" (redondeado a partir de 10 €), "4,50 €" por debajo.
    private func roundedEUR(_ cents: Int) -> String {
        guard cents >= 1_000 else { return formatEUR(cents) }
        return "\((cents + 50) / 100)\u{00A0}€"
    }
}
