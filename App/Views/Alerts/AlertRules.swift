import SwiftUI
import MiBancoCore

/// "Qué quieres que te avise": un interruptor por regla (ligado a `alertSettings` por `LedgerModel`), cada uno con
/// una línea que lo explica. Saldo bajo y pago grande enseñan su umbral al encenderse (entra con un muelle sin rebote).
/// Debajo, los comercios silenciados.
struct AlertRules: View {
    let model: LedgerModel
    let settings: AlertSettings
    let mutedCount: Int
    var onMorningRuleChanged: () -> Void = {}

    @Environment(\.motion) private var motion
    @State private var errorTick = 0

    private var revealTransition: AnyTransition {
        // La fila del umbral entra con su muelle; al irse se apaga deprisa (0,12 s), antes de que la regla de debajo
        // suba a su sitio: nunca queda montada sobre ella (menor m-6).
        motion.reduce
            ? AnyTransition.opacity
            : AnyTransition.asymmetric(
                // Entra un instante después de que las reglas de debajo empiecen a hacerle sitio.
                insertion: AnyTransition.opacity.combined(with: AnyTransition.offset(y: -10))
                    .animation(motion.animation(.row).delay(motion.seconds(0.08))),
                removal: AnyTransition.opacity.animation(.easeOut(duration: motion.seconds(0.12))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader("Qué quieres que te avise")
                .padding(.top, Theme.Space.section)
            VStack(spacing: 0) {
                rule("Cada movimiento", "El aviso de siempre, con lo que te queda.", "bell", .everyMovement)
                RuleDivider()
                rule("Saldo bajo", "Si una cuenta baja de lo que tú digas.", "battery.25", .lowBalance)
                if settings.lowBalance {
                    ThresholdRow(title: "Avisar por debajo de", cents: settings.lowBalanceThresholdCents) { cents in
                        try model.updateAlertSettings { $0.lowBalanceThresholdCents = cents }
                    }
                    .transition(revealTransition)
                }
                RuleDivider()
                rule("Pago grande o poco habitual", "Si pagas mucho de golpe o más de lo normal en una tienda.",
                     "exclamationmark.circle", .largePayment)
                if settings.largePayment {
                    ThresholdRow(title: "Pago grande desde", cents: settings.largePaymentThresholdCents) { cents in
                        try model.updateAlertSettings { $0.largePaymentThresholdCents = cents }
                    }
                    .transition(revealTransition)
                }
                RuleDivider()
                rule("Nómina e ingresos grandes", "Cuando entra tu nómina o te llega un ingreso gordo.", "briefcase", .income)
                RuleDivider()
                rule("Suscripciones y subidas de precio", "Te avisa el día antes del cobro y si te suben la cuota.",
                     "calendar", .subscriptions)
                RuleDivider()
                rule("Cobro duplicado", "Dos cargos iguales en la misma tienda en pocos minutos.", "square.on.square",
                     .duplicateCharge)
                RuleDivider()
                rule("Resumen cada mañana", morningReminderSubtitle(minutes: settings.morningBriefingMinutes),
                     "sun.horizon", .morningBriefing, id: "alert-rule-morningBriefing")
                if settings.morningBriefing {
                    MorningTimeRow(minutes: settings.morningBriefingMinutes) { newMinutes in
                        try model.updateAlertSettings { $0.morningBriefingMinutes = newMinutes }
                        onMorningRuleChanged()
                    }
                    .transition(revealTransition)
                }
                RuleDivider()
                rule("Resumen semanal", "El domingo a las 20:00, lo que llevas gastado esa semana.", "doc.text", .weeklyDigest)
                RuleDivider()
                rule("Ritmo de gasto", "Si vas por encima o por debajo del mes pasado.", "gauge.with.dots.needle.33percent",
                     .spendingPace)
                RuleDivider()
                rule("Presupuestos", "Cuando llegas al 80 % y cuando te pasas.", "gauge.with.dots.needle.67percent", .budgets)
            }
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .padding(.horizontal, 16)

            NavigationLink(value: AlertsAnchor.muted) {
                HStack(spacing: Theme.Space.row) {
                    OptionLabel(title: "Comercios silenciados", detail: mutedDetail, systemImage: "speaker.slash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.passive)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle(background: Theme.raised))
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, Theme.Space.gutter)
        }
        .sensoryFeedback(.error, trigger: errorTick)
    }

    private var mutedDetail: String {
        switch mutedCount {
        case 0: "Ninguno. Se silencian desde un movimiento."
        case 1: "1 comercio que no te avisa"
        default: "\(mutedCount) comercios que no te avisan"
        }
    }

    @ViewBuilder
    private func rule(_ title: String, _ detail: String, _ symbol: String, _ key: AlertRule, id: String? = nil) -> some View {
        let toggle = Toggle(isOn: binding(key)) {
            OptionLabel(title: title, detail: detail, systemImage: symbol)
        }
        .toggleStyle(TitanToggleStyle())
        .padding(.horizontal, 16)
        if let id {
            toggle.accessibilityIdentifier(id)
        } else {
            toggle
        }
    }

    /// El interruptor escribe en el libro (Core) y el snapshot nuevo llega dentro de la animación:
    /// la fila del umbral aparece o se va con el muelle sin rebote.
    private func binding(_ key: AlertRule) -> Binding<Bool> {
        Binding(get: { key.isOn(in: settings) }, set: { on in
            // La fila del umbral aparece o se va con el muelle `row` del kit.
            withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
                do {
                    try model.updateAlertSettings { key.set(on, in: &$0) }
                    if key == .morningBriefing { onMorningRuleChanged() }
                } catch {
                    errorTick += 1
                }
            }
        })
    }
}

/// Cada interruptor de "Qué quieres que te avise" y el campo de `AlertSettings` que gobierna.
enum AlertRule: Sendable {
    case everyMovement, lowBalance, largePayment, income, subscriptions, duplicateCharge, morningBriefing, weeklyDigest, spendingPace, budgets

    func isOn(in s: AlertSettings) -> Bool {
        switch self {
        case .everyMovement: s.everyMovement
        case .lowBalance: s.lowBalance
        case .largePayment: s.largePayment
        case .income: s.income
        case .subscriptions: s.subscriptions
        case .duplicateCharge: s.duplicateCharge
        case .morningBriefing: s.morningBriefing
        case .weeklyDigest: s.weeklyDigest
        case .spendingPace: s.spendingPace
        case .budgets: s.budgets
        }
    }

    func set(_ on: Bool, in s: inout AlertSettings) {
        switch self {
        case .everyMovement: s.everyMovement = on
        case .lowBalance: s.lowBalance = on
        case .largePayment: s.largePayment = on
        case .income: s.income = on
        case .subscriptions: s.subscriptions = on
        case .duplicateCharge: s.duplicateCharge = on
        case .morningBriefing: s.morningBriefing = on
        case .weeklyDigest: s.weeklyDigest = on
        case .spendingPace: s.spendingPace = on
        case .budgets: s.budgets = on
        }
    }
}

/// Selector de hora del aviso matinal («Resumen cada mañana»), siempre en hora de Madrid.
/// Despliega una rueda en línea (nunca una ventana presentada de UIKit) y se pliega sola al bloquear o salir (U33).
private struct MorningTimeRow: View {
    let minutes: Int
    let save: (Int) throws -> Void

    @State private var expanded = false
    @State private var errorTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate

    private var validMinutes: Int {
        (0..<1_440).contains(minutes) ? minutes : defaultMorningBriefingMinutes
    }

    private var formattedTime: String {
        String(format: "%02d:%02d", validMinutes / 60, validMinutes % 60)
    }

    private var canShowWheel: Bool {
        expanded && scenePhase == .active && gate?.isLocked != true
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Self.date(fromMinutes: validMinutes) },
            set: { newDate in
                guard scenePhase == .active, gate?.isLocked != true else { return }
                let cal = DateText.madridCalendar
                let comps = cal.dateComponents([.hour, .minute], from: newDate)
                let total = (comps.hour ?? 8) * 60 + (comps.minute ?? 30)
                guard total != validMinutes else { return }
                do {
                    try save(total)
                } catch {
                    errorTick += 1
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard scenePhase == .active, gate?.isLocked != true else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Space.row) {
                    Text("Hora del resumen")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                    Spacer(minLength: Theme.Space.small)
                    Text(formattedTime)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.raised, in: Capsule())
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hora del resumen, \(formattedTime)")
            .accessibilityIdentifier("morning-briefing-time")

            if canShowWheel {
                DatePicker("Hora del resumen", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .environment(\.calendar, DateText.madridCalendar)
                    .environment(\.timeZone, DateText.madridCalendar.timeZone)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("morning-briefing-wheel")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 60)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: canShowWheel)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { expanded = false }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true { expanded = false }
        }
        .sensoryFeedback(.error, trigger: errorTick)
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        let cal = DateText.madridCalendar
        let valid = (0..<1_440).contains(minutes) ? minutes : defaultMorningBriefingMinutes
        let today = cal.startOfDay(for: Date())
        return cal.date(bySettingHour: valid / 60, minute: valid % 60, second: 0, of: today) ?? today
    }
}

private struct RuleDivider: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 60)
    }
}

/// Umbral en euros dentro de su regla. Misma validación que los saldos (`parseBalanceInput`); solo se guarda si el
/// usuario lo ha tocado y es mayor que 0. Al guardar, un ✓ se traza junto al campo.
private struct ThresholdRow: View {
    let title: String
    let cents: Int
    let save: (Int) throws -> Void

    @State private var text = ""
    @State private var dirty = false
    @State private var problem: String?
    @State private var saved = false
    @State private var saveTick = 0
    @State private var errorTick = 0
    @FocusState private var focused: Bool
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.presentationGate) private var gate

    /// Con el ojo cerrado (y sin editar) el umbral no se dibuja: en su sitio va la máscara del kit.
    private var masked: Bool { preferences.privateMode && !focused && !text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(spacing: Theme.Space.row) {
                Text(title)
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
                Spacer(minLength: Theme.Space.small)
                if saved {
                    SavedCheck()
                        .transition(.opacity)
                }
                MaskedAmountTextField(placeholder: "100,00 €", text: textBinding, masked: masked)
                    .titan(.option)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(commit)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 96, maxWidth: 128, minHeight: 40)
                    .background(Theme.fieldFill.opacity(focused ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.field))
                    .animation(motion.calmAnimation(.pressIn), value: focused)
                    .accessibilityLabel(title)
            }
            if let problem {
                Text(problem)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 60)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { text = formatEUR(cents) }
        .onChange(of: cents) { _, new in
            if !dirty && !focused { text = formatEUR(new) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .onDisappear { if dirty { commit() } }
        // Fuera de primer plano o al bloquear el teclado se va (y lo escrito se guarda): nunca queda encima del bloqueo.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focused = false }
        }
        .onChange(of: gate?.isLocked) { _, locked in
            if locked == true { focused = false }
        }
        // Al cerrarse el ojo (desde aquí o desde Inicio) un importe en edición suelta el foco en el acto y pasa a máscara, sin
        // animación: nunca queda una cifra a la vista con el ojo cerrado (lote de cierre, ronda 1, I-3). Lo escrito se
        // guarda como al soltar el foco.
        .onChange(of: preferences.privateMode) { _, on in
            guard on, focused else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { focused = false }
        }
        .sensoryFeedback(.success, trigger: saveTick)
        .sensoryFeedback(.error, trigger: errorTick)
    }

    private var textBinding: Binding<String> {
        Binding(get: { text }, set: { new in
            guard new != text else { return }
            text = new
            dirty = true
            problem = nil
        })
    }

    private func commit() {
        guard dirty else {
            text = formatEUR(cents)
            return
        }
        guard let value = parseBalanceInput(text), value > 0 else {
            withAnimation(motion.fade) { problem = "Escribe un importe como 100" }
            errorTick += 1
            return
        }
        dirty = false
        guard value != cents else {
            text = formatEUR(value)
            return
        }
        do {
            try save(value)
            text = formatEUR(value)
            flashSaved()
        } catch {
            dirty = true
            withAnimation(motion.fade) { problem = "No se pudo guardar. Inténtalo de nuevo." }
            errorTick += 1
        }
    }

    /// El ✓ se queda 1,4 s (del kit) junto al campo y se va con un fundido.
    private func flashSaved() {
        withAnimation(motion.fade) { saved = true }
        saveTick += 1
        let hold = motion.seconds(1.4)
        Task {
            try? await Task.sleep(for: .seconds(hold))
            withAnimation(motion.fade) { saved = false }
        }
    }
}

// MARK: - Comercios silenciados

/// Los comercios que no avisan (salvo el saldo bajo, que avisa siempre). Cada uno se puede volver a oír:
/// el botón se transforma en ✓ y la fila se va.
struct MutedMerchantsView: View {
    let model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var errorTick = 0

    var body: some View {
        let list = model.snapshot.mutedList
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if list.isEmpty {
                    VStack(spacing: Theme.Space.row) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(Theme.passive)
                            .accessibilityHidden(true)
                        Text("No has silenciado ningún comercio.")
                            .titan(.callout)
                            .foregroundStyle(Theme.label2)
                        Text("Desde un movimiento puedes silenciar su tienda: se sigue guardando, pero no te avisa.")
                            .titan(.meta)
                            .foregroundStyle(Theme.label3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 100)
                    .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, merchant in
                            MutedRow(merchant: merchant, isLast: index == list.count - 1) { unmute(merchant) }
                                .staggeredEntrance(index)
                                .transition(reduceMotion
                                    ? AnyTransition.opacity
                                    : AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.96)))
                        }
                    }
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, Theme.Space.small)
                    Text("Sus movimientos se siguen guardando. El saldo bajo te avisa igualmente.")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                        .padding(.horizontal, 36)
                        .padding(.top, 8)
                }
            }
            .animation(reduceMotion ? Animation.easeOut(duration: 0.2) : Theme.Motion.reveal, value: list.map(\.id))
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Comercios silenciados")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: errorTick)
    }

    private func unmute(_ merchant: MutedMerchant) {
        do {
            try model.unmute(merchant)
        } catch {
            errorTick += 1
        }
    }
}

private struct MutedRow: View {
    let merchant: MutedMerchant
    let isLast: Bool
    let onUnmute: () -> Void

    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            MerchantTile(image: logo, symbol: "storefront", size: 34)
            Text(merchant.name)
                .titan(.option)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: tap) {
                ZStack {
                    if done {
                        DrawnCheck(lineWidth: 2, color: Theme.canvas)
                            .frame(width: 14, height: 14)
                            .transition(.opacity)
                    } else {
                        Text("Volver a avisar")
                            .titan(.captionStrong)
                            .foregroundStyle(Theme.canvas)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, done ? 0 : 14)
                .frame(width: done ? 32 : nil, height: 32)
                .background(Theme.label, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(done)
            .accessibilityLabel("Volver a avisar de \(merchant.name)")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 64).opacity(isLast ? 0 : 1)
        }
        .sensoryFeedback(.success, trigger: done) { _, new in new }
    }

    private var logo: UIImage? {
        logoDomain(merchant: merchant.raw, isShop: false, isIncome: false).flatMap { BundledLogos.image(domain: $0) }
    }

    /// Cápsula -> círculo con ✓ -> la fila se va.
    private func tap() {
        withAnimation(reduceMotion ? nil : Theme.Motion.morph) { done = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 650))
            onUnmute()
        }
    }
}
