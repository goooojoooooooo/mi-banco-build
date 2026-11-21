import SwiftUI
import MiBancoCore

/// Hoja de «Tu resumen» y el asistente Onyx (Plan 4b, tareas 9, 10 y 13 ampliada A1–A6).
/// Orden exacto (A1):
/// 1. Resumen del día (saludo, apertura del catálogo, titular, secciones, consejo).
/// 2. «Te puede interesar» (hasta 3 tarjetas con «Me interesa» / «No me interesa»).
/// 3. «Pregúntame» (campo, fichas sugeridas y respuesta factual de Onyx).
/// Vive en `RootSheet`: nunca aparece encima del bloqueo y se cierra al bloquear o salir de primer plano.
struct BriefingSheet: View {
    let model: LedgerModel
    let portfolio: PortfolioModel
    let accountBook: AccountBookModel
    let briefingModel: BriefingModel
    let speaker: BriefingSpeaker
    let onAction: (BriefingAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppPreferences.self) private var preferences

    @State private var revealedStage = 0
    @State private var entranceCompleted = false
    /// true solo si el dueño tocó durante la entrada para terminarla al instante (corta también la cuenta de 0,9 s).
    @State private var userSkippedEntrance = false
    @State private var entranceTask: Task<Void, Never>?
    @State private var questionDraft = ""
    @State private var askTask: Task<Void, Never>?
    @State private var feedbackTick = 0
    @FocusState private var questionFocused: Bool

    private var demoKeepsVisible: Bool {
        #if DEBUG
        return DemoMode.isActive && DemoMode.briefingMode != nil
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if let briefing = briefingModel.briefing {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header(for: briefing)

                            if !briefingModel.openingText.isEmpty {
                                openingBlock
                                    .modifier(BriefingReveal(visible: isVisible(stage: 1), reduceMotion: reduceMotion))
                            }

                            BriefingLineView(
                                parts: briefing.headline,
                                role: .sheetTitle,
                                color: Theme.label
                            )
                            .modifier(BriefingReveal(visible: isVisible(stage: 2), reduceMotion: reduceMotion))

                            ForEach(Array(briefing.sections.enumerated()), id: \.element.id) { index, section in
                                sectionCard(section)
                                    .modifier(BriefingReveal(
                                        visible: isVisible(stage: 3 + min(index, 5)),
                                        reduceMotion: reduceMotion
                                    ))
                            }

                            if let tip = briefing.tip {
                                tipCard(tip)
                                    .modifier(BriefingReveal(visible: isVisible(stage: 8), reduceMotion: reduceMotion))
                            }

                            if !briefingModel.cards.isEmpty {
                                interestCardsBlock
                                    .modifier(BriefingReveal(visible: isVisible(stage: 8), reduceMotion: reduceMotion))
                            }

                            askBlock(scrollProxy: proxy)
                                .modifier(BriefingReveal(visible: isVisible(stage: 8), reduceMotion: reduceMotion))
                        }
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, 20)
                        .padding(.bottom, 110)
                    }
                    .accessibilityIdentifier("briefing-scroll")
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !questionFocused {
                            bottomDoneBar
                        }
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            completeEntrance()
                        },
                        including: entranceCompleted ? .subviews : .all
                    )
                    .onChange(of: questionFocused) { _, focused in
                        guard focused else { return }
                        Task {
                            try? await Task.sleep(for: .milliseconds(180))
                            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                                proxy.scrollTo("assistant-input-anchor", anchor: .center)
                            }
                        }
                    }
                }
            }

            // Segunda línea de defensa frente a capturas en segundo plano.
            if scenePhase != .active && !demoKeepsVisible {
                Theme.canvas
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(Haptics.detent, trigger: feedbackTick)
        .onAppear {
            briefingModel.setSheetVisible(true)
            startEntrance()
        }
        .onDisappear {
            entranceTask?.cancel()
            askTask?.cancel()
            speaker.stop()
            briefingModel.setSheetVisible(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                questionFocused = false
                speaker.stop()
            }
        }
    }

    // MARK: - Cabecera

    private func header(for briefing: Briefing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    AppMark(size: 28)
                    Text("Onyx")
                        .titan(.captionStrong)
                        .foregroundStyle(Theme.label2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Onyx")

                Spacer(minLength: 8)

                let speakingBriefing = speaker.activeTarget == .briefing
                Button {
                    toggleBriefingSpeech(briefing)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speakingBriefing ? "stop.fill" : "speaker.wave.2")
                            .font(.system(size: 14, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(speakingBriefing ? "Parar" : "Escuchar")
                            .titan(.captionStrong)
                    }
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.raised, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(speakingBriefing ? "Parar" : "Escuchar")
                .accessibilityIdentifier("briefing-listen")

                Button {
                    speaker.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                        .frame(width: 44, height: 44)
                        .background(Theme.raised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Cerrar")
                .accessibilityIdentifier("briefing-close")
            }

            Text(briefing.greeting)
                .titan(.largeTitle)
                .foregroundStyle(Theme.label)
                .accessibilityAddTraits(.isHeader)
                .modifier(BriefingReveal(visible: isVisible(stage: 1), reduceMotion: reduceMotion))
        }
    }

    private var openingBlock: some View {
        Text(briefingModel.openingText)
            .titan(.body)
            .foregroundStyle(Theme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Secciones del resumen

    private func sectionCard(_ section: BriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(section.lines.enumerated()), id: \.element.id) { index, line in
                    briefingRow(line, idPrefix: "briefing-line")
                    if index < section.lines.count - 1 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        }
    }

    @ViewBuilder
    private func briefingRow(_ line: BriefingLine, idPrefix: String) -> some View {
        let isHeroTotal = idPrefix == "briefing-line" && line.id == "money-total"
        let content = HStack(alignment: .center, spacing: 10) {
            BriefingLineView(
                parts: line.parts,
                role: .row,
                color: Theme.label,
                countsFirstAmount: isHeroTotal,
                snapCountImmediately: userSkippedEntrance
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if line.action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.passive)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let action = line.action {
            Button {
                trigger(action)
            } label: {
                content
            }
            .buttonStyle(RowPressStyle(background: Theme.raised))
            .accessibilityIdentifier("\(idPrefix)-\(line.id)")
        } else {
            content
        }
    }

    // MARK: - Consejo

    private func tipCard(_ tip: BriefingLine) -> some View {
        let isShortfall = tip.id == "tip-shortfall"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isShortfall ? Theme.warning : Theme.label)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                BriefingLineView(
                    parts: tip.parts,
                    role: .callout,
                    color: Theme.label
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let action = tip.action {
                let title = tipActionTitle(for: action, privateMode: preferences.privateMode)
                Button {
                    trigger(action)
                } label: {
                    Text(title)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.canvas)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.label, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(title)
                .accessibilityIdentifier("briefing-tip-action")
            }
        }
        .padding(16)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private func tipActionTitle(for action: BriefingAction, privateMode: Bool) -> String {
        switch action {
        case .moveMoney(_, _, let cents):
            if !privateMode, let cents {
                return "Pasar \(formatEUR(cents))"
            }
            return "Preparar traspaso"
        case .openBudgets:
            return "Ver presupuestos"
        case .openInvestments:
            return "Ver inversiones"
        case .openBankSettings:
            return "Renovar"
        case .openMovement:
            return "Ver movimiento"
        }
    }

    // MARK: - «Te puede interesar» (A4)

    private var interestCardsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Te puede interesar")
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                ForEach(briefingModel.cards) { card in
                    interestCardView(card)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal, value: briefingModel.cards.map(\.id))
        }
    }

    private func interestCardView(_ card: InterestCard) -> some View {
        let liked = briefingModel.feedback(for: card.id) == .interested
        let actionsLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))

        return VStack(alignment: .leading, spacing: 10) {
            if let action = card.action {
                Button {
                    trigger(action)
                } label: {
                    interestCardHeaderAndBody(card, hasChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                interestCardHeaderAndBody(card, hasChevron: false)
            }

            actionsLayout {
                Button {
                    feedbackTick += 1
                    briefingModel.recordCardFeedback(
                        .interested,
                        for: card,
                        state: model.state,
                        portfolio: portfolio.portfolioForBackup,
                        book: accountBook.book
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 13, weight: .medium))
                            .accessibilityHidden(true)
                        Text("Me interesa")
                            .titan(.captionStrong)
                    }
                    .foregroundStyle(liked ? Theme.canvas : Theme.label)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(liked ? Theme.label : Theme.raised, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(liked ? [.isSelected] : [])
                .accessibilityIdentifier("card-like-\(card.topic.rawValue)")

                Button {
                    feedbackTick += 1
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal) {
                        briefingModel.recordCardFeedback(
                            .notInterested,
                            for: card,
                            state: model.state,
                            portfolio: portfolio.portfolioForBackup,
                            book: accountBook.book
                        )
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 13, weight: .medium))
                            .accessibilityHidden(true)
                        Text("No me interesa")
                            .titan(.captionStrong)
                    }
                    .foregroundStyle(Theme.label2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.raised, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("card-dislike-\(card.topic.rawValue)")
            }
        }
        .padding(16)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private func interestCardHeaderAndBody(_ card: InterestCard, hasChevron: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: card.topic.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(card.topic == .shortfall ? Theme.warning : Theme.label2)
                    .accessibilityHidden(true)
                Text(card.title)
                    .titan(.cardTitle)
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.passive)
                        .accessibilityHidden(true)
                }
            }
            BriefingLineView(parts: card.parts, role: .callout, color: Theme.label2)
        }
        .contentShape(Rectangle())
    }

    // MARK: - «Pregúntame» (A1–A3, A5)

    private func askBlock(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Pregúntame algo de tu dinero…", text: $questionDraft)
                    .titan(.body)
                    .foregroundStyle(Theme.label)
                    .focused($questionFocused)
                    .submitLabel(.send)
                    .onSubmit { submitQuestion(scrollProxy: scrollProxy) }
                    .padding(.leading, 14)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("assistant-question-field")

                let canSend = !questionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !briefingModel.isAnswering
                Button {
                    submitQuestion(scrollProxy: scrollProxy)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(canSend ? Theme.label : Theme.passive)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .disabled(!canSend)
                .accessibilityLabel("Preguntar")
                .accessibilityIdentifier("assistant-send")
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .id("assistant-input-anchor")

            if !briefingModel.chips.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(briefingModel.chips) { chip in
                            Button {
                                submit(question: chip.question, scrollProxy: scrollProxy)
                            } label: {
                                Text(chip.label)
                                    .titan(.captionStrong)
                                    .foregroundStyle(Theme.label)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .background(Theme.raised, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.pressable)
                            .accessibilityIdentifier("assistant-chip-\(chip.id)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("assistant-chips-scroll")
            }

            if briefingModel.isAnswering {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.label2)
                    Text("Onyx está mirando tus datos…")
                        .titan(.callout)
                        .foregroundStyle(Theme.label2)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .id("assistant-answer-anchor")
            } else if let answer = briefingModel.lastAnswer {
                answerCard(answer)
                    .id("assistant-answer-anchor")
            }
        }
    }

    private func answerCard(_ answer: AssistantAnswer) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(answer.lines.enumerated()), id: \.element.id) { index, line in
                briefingRow(line, idPrefix: "answer-line")
                if index < answer.lines.count - 1 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
        }
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .accessibilityIdentifier("assistant-answer-card")
    }

    // MARK: - Botón inferior «Vale»

    private var bottomDoneBar: some View {
        VStack(spacing: 0) {
            Button {
                speaker.stop()
                dismiss()
            } label: {
                Text("Vale")
                    .titan(.cardTitle)
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.label, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("briefing-done")
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.canvas.opacity(0), location: 0),
                    .init(color: Theme.canvas.opacity(0.94), location: 0.25),
                    .init(color: Theme.canvas, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Interacción y entrada

    private func isVisible(stage: Int) -> Bool {
        entranceCompleted || revealedStage >= stage
    }

    private func startEntrance() {
        userSkippedEntrance = false
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) {
                revealedStage = 8
                entranceCompleted = true
            }
            return
        }
        revealedStage = 0
        entranceCompleted = false
        entranceTask?.cancel()
        entranceTask = Task {
            withAnimation(Theme.Motion.assemble) { revealedStage = 1 }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, !entranceCompleted else { return }
            withAnimation(Theme.Motion.assemble) { revealedStage = 2 }
            for step in 3...8 {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled, !entranceCompleted else { return }
                withAnimation(Theme.Motion.assemble) { revealedStage = step }
            }
            entranceCompleted = true
        }
    }

    private func completeEntrance() {
        guard !entranceCompleted else { return }
        entranceTask?.cancel()
        userSkippedEntrance = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.quick) {
            revealedStage = 8
            entranceCompleted = true
        }
    }

    private func toggleBriefingSpeech(_ briefing: Briefing) {
        guard let input = briefingModel.input else { return }
        let text = spokenBriefing(
            briefing,
            input: input,
            privateMode: preferences.privateMode,
            calendar: DateText.madridCalendar
        )
        speaker.toggle(text, target: .briefing)
    }

    private func submitQuestion(scrollProxy: ScrollViewProxy) {
        let q = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        questionDraft = ""
        submit(question: q, scrollProxy: scrollProxy)
    }

    private func submit(question: String, scrollProxy: ScrollViewProxy) {
        questionFocused = false
        speaker.stop()
        askTask?.cancel()
        askTask = Task {
            await briefingModel.ask(
                question,
                state: model.state,
                portfolio: portfolio.portfolioForBackup,
                book: accountBook.book
            )
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                scrollProxy.scrollTo("assistant-answer-anchor", anchor: .bottom)
            }
        }
    }

    private func trigger(_ action: BriefingAction) {
        speaker.stop()
        onAction(action)
    }
}

private struct BriefingReveal: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: (visible || reduceMotion) ? 0 : 12)
    }
}

extension AssistantTopic {
    var symbol: String {
        switch self {
        case .unusualPayment: "waveform.path.ecg"
        case .subscriptionPriceChange: "arrow.up.right"
        case .budgetClose: "gauge.with.dots.needle.67percent"
        case .shortfall: "exclamationmark.triangle"
        case .spendingPace: "chart.line.uptrend.xyaxis"
        case .portfolioMover: "chart.xyaxis.line"
        }
    }

    var settingsDetail: String {
        switch self {
        case .unusualPayment: "Si un pago es mucho mayor de lo habitual en esa tienda"
        case .subscriptionPriceChange: "Si te suben o te bajan una cuota fija"
        case .budgetClose: "Cuando un presupuesto llega al 80 % o se pasa"
        case .shortfall: "Si un próximo cobro deja una cuenta justa o corta"
        case .spendingPace: "Cómo vas este mes frente al mes anterior"
        case .portfolioMover: "Qué ha subido o bajado más en tu cartera (sin consejos)"
        }
    }
}
