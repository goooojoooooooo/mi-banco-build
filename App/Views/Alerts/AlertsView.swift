import SwiftUI
import MiBancoCore

/// Avisos: arriba lo que merece tu atención (`insights` del snapshot), debajo qué quieres que te avise
/// (un interruptor por regla, con su umbral cuando lo tiene) y los comercios silenciados.
/// Todo lee del snapshot y escribe por `LedgerModel` (mutaciones de Core).
struct AlertsView: View {
    let model: LedgerModel
    var isVisible = false
    /// Abre la hoja de un movimiento (la presenta `RootView`).
    let onOpen: (UUID) -> Void
    var onMorningRuleChanged: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Al entrar en la pestaña, los avisos llegan uno tras otro.
    @State private var entrance = Entrance()

    var body: some View {
        let snapshot = model.snapshot
        let insights = snapshot.insights
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if insights.isEmpty {
                            AlertsEmptyState()
                                .staggeredEntrance(0)
                        } else {
                            GroupHeader("Novedades")
                                .staggeredEntrance(0)
                            VStack(spacing: 0) {
                                ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                                    InsightRow(insight: insight, isLast: index == insights.count - 1, onOpen: onOpen)
                                        .staggeredEntrance(1 + index)
                                        .transition(reduceMotion
                                            ? AnyTransition.opacity
                                            : AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .top).combined(with: .opacity),
                                                                       removal: AnyTransition.opacity))
                                }
                            }
                            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                            .padding(.horizontal, 16)
                        }

                        AlertRules(
                            model: model,
                            settings: snapshot.alertSettings,
                            mutedCount: snapshot.mutedList.count,
                            onMorningRuleChanged: onMorningRuleChanged
                        )
                            .id(AlertsAnchor.rules)
                            .staggeredEntrance(min(1 + insights.count, 8))

                        Text("Todo se calcula en tu iPhone con tus movimientos. Nada sale del teléfono.")
                            .titan(.meta)
                            .foregroundStyle(Theme.label3)
                            .padding(.horizontal, 36)
                            .padding(.top, 8)
                    }
                    // Solo la lista corta de avisos (≤ 12) anima su cambio; los avisos nuevos entran desde arriba.
                    .animation(reduceMotion ? Animation.easeOut(duration: 0.2) : Theme.Motion.reveal, value: insights.map(\.id))
                    .padding(.bottom, Theme.Space.section)
                }
                .scrollIndicators(.hidden)
                .background(Theme.canvas.ignoresSafeArea())
                .navigationTitle("Avisos")
                .navigationDestination(for: AlertsAnchor.self) { _ in
                    MutedMerchantsView(model: model)
                }
                #if DEBUG
                .task {
                    guard DemoMode.isActive, DemoMode.showsAlertRules else { return }
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(Theme.Motion.reveal) { proxy.scrollTo(AlertsAnchor.rules, anchor: .top) }
                }
                #endif
            }
        }
        .environment(\.entrance, entrance)
        .onChange(of: isVisible) { _, visible in
            guard visible, !reduceMotion else { return }
            let token = entrance.token + 1
            entrance = Entrance(token: token, active: true, scope: .assembly)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if entrance.token == token { entrance.active = false }
            }
        }
    }
}

/// Anclas de la pantalla: el bloque de reglas (para desplazarse hasta él) y la pantalla de comercios silenciados.
enum AlertsAnchor: Hashable {
    case rules, muted
}

/// Cabecera de grupo ("Novedades", "Qué quieres que te avise").
struct GroupHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .titan(.header)
            .foregroundStyle(Theme.label3)
            .padding(.horizontal, 36)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Un aviso

/// Un aviso: icono con el color de su gravedad (ámbar = atención, verde = dinero que entra), título (su importe cuenta),
/// detalle y cuándo. Con un movimiento detrás, tocarlo abre su hoja.
private struct InsightRow: View {
    let insight: Insight
    let isLast: Bool
    let onOpen: (UUID) -> Void

    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        if let id = insight.movementID {
            Button { onOpen(id) } label: { content(chevron: true) }
                .buttonStyle(RowPressStyle(background: Theme.raised))
                .accessibilityHint("Abre el movimiento")
        } else {
            content(chevron: false)
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(insight.severity == .info ? 0 : 0.14), in: .rect(cornerRadius: 9, style: .continuous))
                .background(Theme.raised, in: .rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                CountingSentence(text: insight.title, hidden: preferences.privateMode)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = insight.detail {
                    Text(preferences.privateMode ? maskingAmounts(detail) : detail)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label3)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(when)
                    .titan(.meta)
                    .foregroundStyle(Theme.label3)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.passive)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 64).opacity(isLast ? 0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let hidden = preferences.privateMode
        let title = hidden ? maskingAmounts(insight.title, with: "importe oculto") : insight.title
        let detail = insight.detail.map { hidden ? maskingAmounts($0, with: "importe oculto") : $0 }
        return [severityWord, title, detail, when].compactMap { $0 }.joined(separator: ". ")
    }

    private var tint: Color {
        switch insight.severity {
        case .warning: Theme.warning
        case .positive: Theme.income
        case .info: Theme.monogram
        }
    }

    private var severityWord: String? {
        switch insight.severity {
        case .warning: "Atención"
        case .positive, .info: nil
        }
    }

    private var symbol: String { insight.kind.symbol }

    /// "hoy", "ayer", "mañana", "17 nov".
    private var when: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(insight.date) { return "hoy" }
        if calendar.isDateInYesterday(insight.date) { return "ayer" }
        if calendar.isDateInTomorrow(insight.date) { return "mañana" }
        return DateText.day(insight.date)
    }
}

extension InsightKind {
    /// Símbolo del aviso (fila de Avisos).
    var symbol: String {
        switch self {
        case .lowBalance: "battery.25"
        case .largePayment: "exclamationmark.circle"
        case .unusualPayment: "waveform.path.ecg"
        case .salary: "briefcase"
        case .largeIncome: "arrow.down.circle"
        case .duplicateCharge: "square.on.square"
        case .subscriptionUpcoming: "calendar"
        case .subscriptionPriceChange: "arrow.up.right"
        case .spendingPace: "gauge.with.dots.needle.33percent"
        case .weeklyDigest: "doc.text"
        case .budgetWarning: "gauge.with.dots.needle.67percent"
        case .budgetExceeded: "exclamationmark.triangle"
        }
    }
}

/// Una frase con un importe dentro ("Pago grande: 320,00 € en MediaMarkt"): el importe cuenta desde 0 la primera vez
/// que se ve y al entrar en la pestaña (desaceleración de 1 s); el resto del texto no se mueve. Con el modo privado,
/// el importe pasa a "•••". Con Reducir movimiento, no cuenta.
private struct CountingSentence: View {
    let text: String
    let hidden: Bool

    @State private var shown: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.entrance) private var entrance

    var body: some View {
        let split = AmountSplit(text)
        Group {
            if hidden {
                Text(maskingAmounts(text))
            } else if let split {
                SentenceFigure(value: shown ?? (reduceMotion ? Double(split.cents) : 0), split: split)
            } else {
                Text(text)
            }
        }
        .contentTransition(.opacity)
        .onAppear(perform: start)
        .onChange(of: entrance.token) { _, _ in recount() }
        .onChange(of: text) { _, _ in
            guard let cents = AmountSplit(text)?.cents else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.roll) { shown = Double(cents) }
        }
    }

    private func start() {
        guard shown == nil, let cents = AmountSplit(text)?.cents else { return }
        guard !reduceMotion else {
            shown = Double(cents)
            return
        }
        shown = 0
        withAnimation(Theme.Motion.countUp.delay(0.1)) { shown = Double(cents) }
    }

    private func recount() {
        guard entrance.active, !reduceMotion, let cents = AmountSplit(text)?.cents else { return }
        shown = 0
        let target = Double(cents)
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(Theme.Motion.countUp.delay(0.12)) { shown = target }
        }
    }
}

/// Dibuja la frase con el importe animado en su sitio (cifras tabulares: nada tiembla).
private struct SentenceFigure: View, Animatable {
    var value: Double
    let split: AmountSplit

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(split.prefix + formatEUR(Int(value.rounded())) + split.suffix)
    }
}

/// El primer importe de una frase ("1.450,00 €"), separado del texto de antes y de después.
struct AmountSplit: Equatable {
    let prefix: String
    let cents: Int
    let suffix: String

    init?(_ text: String) {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i].isASCII, chars[i].isNumber else {
                i += 1
                continue
            }
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." || chars[j] == "," { j += 1 }
            let run = String(chars[i..<j])
            let followedByEuro = j + 1 < chars.count && (chars[j] == "\u{00A0}" || chars[j] == " ") && chars[j + 1] == "€"
            if followedByEuro, let comma = run.lastIndex(of: ","), run.distance(from: comma, to: run.endIndex) == 3 {
                let digits = run.filter { $0 != "." && $0 != "," }
                if let cents = Int(digits) {
                    prefix = String(chars[..<i])
                    self.cents = cents
                    suffix = String(chars[(j + 2)...])
                    return
                }
            }
            i = j
        }
        return nil
    }
}

/// "Pago grande: 320,00 € en MediaMarkt" -> "Pago grande: ••• € en MediaMarkt" (modo privado).
/// Con `replacement`, sustituye también el "€" (para VoiceOver: "importe oculto").
/// `everyNumber`: para textos de banco sin formato conocido ("12,50EUR", "-12.50 €"): oculta cualquier cifra.
func maskingAmounts(_ text: String, with replacement: String? = nil, everyNumber: Bool = false) -> String {
    let chars = Array(text)
    var out = ""
    var i = 0
    while i < chars.count {
        guard chars[i].isASCII, chars[i].isNumber else {
            out.append(chars[i])
            i += 1
            continue
        }
        var j = i
        while j < chars.count, chars[j].isASCII, chars[j].isNumber || chars[j] == "." || chars[j] == "," { j += 1 }
        let followedByEuro = j + 1 < chars.count && (chars[j] == "\u{00A0}" || chars[j] == " ") && chars[j + 1] == "€"
        if everyNumber && !followedByEuro {
            out += replacement ?? "•••"
        } else if followedByEuro {
            if let replacement {
                out += replacement
                j += 2
            } else {
                out += "•••"
            }
        } else {
            out += String(chars[i..<j])
        }
        i = j
    }
    return out
}

private struct AlertsEmptyState: View {
    var body: some View {
        VStack(spacing: Theme.Space.row) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.passive)
                .accessibilityHidden(true)
            Text("Todo en orden. Aquí verás lo que merece tu atención.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
        .padding(.top, 56)
        .padding(.bottom, 40)
    }
}
