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
    var entry: NyxSheetEntry = .dailyUpdate
    let onAction: (BriefingAction) -> Void
    var onNyxAction: (NyxAction, String) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(AppPreferences.self) private var preferences

    /// B1: cada entrada de la hoja estrena número; cada bloque entra solo (120 ms × 0,92ⁿ) y `entranceCompleted` llega
    /// cuando ha entrado el último bloque (`finishEntranceLater`), o antes con un toque.
    @State private var entranceToken = 0
    @State private var entranceCompleted = false
    /// true solo si el dueño tocó durante la entrada para terminarla al instante (corta también la cuenta de 0,9 s).
    @State private var userSkippedEntrance = false
    @State private var dailyUpdateExpanded: Bool
    @State private var undoStates: [String: NyxUndoState] = [:]
    @State private var undoTasks: [String: Task<Void, Never>] = [:]
    @State private var questionDraft = ""
    @State private var askTask: Task<Void, Never>?
    @State private var feedbackTick = 0
    @State private var errorTick = 0
    @FocusState private var questionFocused: Bool
    /// m-7: las barras de voz ocupan su sitio (`waveInLayout`) y se ven (`waveShown`); al parar, primero se apagan y,
    /// acabado el fundido, dejan el sitio.
    /// I-5, solo demo (`-MiBancoDemoBriefingDelay`): el resumen aún no ha «llegado» a la hoja.
    @State private var demoBriefingHeld: Bool = {
        #if DEBUG
        return DemoMode.briefingDelaySeconds != nil
        #else
        return false
        #endif
    }()
    @State private var waveInLayout = false
    @State private var waveShown = false

    init(
        model: LedgerModel,
        portfolio: PortfolioModel,
        accountBook: AccountBookModel,
        briefingModel: BriefingModel,
        speaker: BriefingSpeaker,
        entry: NyxSheetEntry = .dailyUpdate,
        onAction: @escaping (BriefingAction) -> Void,
        onNyxAction: @escaping (NyxAction, String) -> Void = { _, _ in }
    ) {
        self.model = model
        self.portfolio = portfolio
        self.accountBook = accountBook
        self.briefingModel = briefingModel
        self.speaker = speaker
        self.entry = entry
        self.onAction = onAction
        self.onNyxAction = onNyxAction
        _dailyUpdateExpanded = State(initialValue: entry == .dailyUpdate)
    }

    /// El resumen que enseña la hoja (en la demo, retenido mientras `-MiBancoDemoBriefingDelay` lo diga).
    private var shownBriefing: Briefing? { demoBriefingHeld ? nil : briefingModel.briefing }

    private var highlightedEntryID: String? {
        if case .message(let id) = entry, !id.isEmpty { return id }
        return nil
    }

    private var demoKeepsVisible: Bool {
        #if DEBUG
        return DemoMode.isActive && (DemoMode.briefingMode != nil || DemoMode.nyxScenario != nil)
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if let briefing = shownBriefing {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header(for: briefing)

                            if !briefingModel.openingText.isEmpty {
                                openingBlock
                                    .modifier(BriefingReveal(stage: 1, completed: entranceCompleted, token: entranceToken))
                            }

                            if dailyUpdateExpanded {
                                BriefingLineView(
                                    parts: briefing.headline,
                                    role: .sheetTitle,
                                    color: Theme.label
                                )
                                .modifier(SpokenHighlight(id: "headline", current: speaker.currentLine))
                                .modifier(BriefingReveal(stage: 2, completed: entranceCompleted, token: entranceToken))

                                ForEach(Array(briefing.sections.enumerated()), id: \.element.id) { index, section in
                                    sectionCard(section)
                                        .modifier(BriefingReveal(stage: 3 + min(index, 5), completed: entranceCompleted, token: entranceToken))
                                }

                                if let focus = briefingModel.dailyUpdate?.focus {
                                    focusBlock(focus)
                                        .modifier(SpokenHighlight(id: "nyx-focus", current: speaker.currentLine))
                                        .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))
                                } else if let tip = briefing.tip {
                                    tipCard(tip)
                                        .modifier(SpokenHighlight(id: tip.id, current: speaker.currentLine))
                                        .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))
                                }

                                if let seenText = nyxSeenLine(briefingModel.seenSinceLastLookCount, hidden: preferences.privateMode) {
                                    seenSummaryRow(text: seenText, scrollProxy: proxy)
                                        .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))
                                }
                            } else {
                                collapsedDailyUpdateButton
                                    .modifier(BriefingReveal(stage: 2, completed: entranceCompleted, token: entranceToken))
                            }

                            NyxSeenList(
                                entries: briefingModel.nyxEntries,
                                initialNewIDs: briefingModel.initialNewEntryIDs,
                                state: model.state,
                                hidden: preferences.privateMode,
                                undoStates: undoStates,
                                highlightedEntryID: highlightedEntryID,
                                now: briefingModel.input?.now ?? AppClock.now,
                                onAction: { action, entry in
                                    handleMessageAction(action, entryID: entry.id, previousStatus: entry.status)
                                },
                                onDismiss: { entry in
                                    dismissEntry(entry)
                                },
                                onUndo: { id in
                                    performUndo(for: id)
                                }
                            )
                            .id("nyx-seen-list")
                            .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))

                            if !briefingModel.cards.isEmpty {
                                interestCardsBlock
                                    .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))
                            }

                            askBlock(scrollProxy: proxy)
                                .modifier(BriefingReveal(stage: 8, completed: entranceCompleted, token: entranceToken))
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
                    .task(id: entry) {
                        guard entry != .dailyUpdate else { return }
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        completeEntrance()
                        withAnimation(motion.reduce ? nil : motion.animation(.enter)) {
                            switch entry {
                            case .dailyUpdate:
                                break
                            case .ask:
                                proxy.scrollTo("assistant-input-anchor", anchor: .center)
                            case .seen:
                                proxy.scrollTo("nyx-seen-list", anchor: .top)
                            case .message(let id):
                                proxy.scrollTo(id.isEmpty ? "nyx-seen-list" : "nyx-row-\(id)", anchor: .center)
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
        #if DEBUG
        // Para las pruebas (lote final): qué línea dibuja su resalte, dentro de la hoja (el fondo no se ve con ella).
        .overlay(alignment: .topLeading) { DrawnLineProbe(entranceToken: entranceToken) }
        .task {
            guard let seconds = DemoMode.briefingDelaySeconds else { return }
            try? await Task.sleep(for: .seconds(seconds))
            demoBriefingHeld = false
        }
        #endif
        // B1: la entrada se da por acabada cuando ha entrado el último bloque (o antes, con un toque).
        .task(id: entranceToken) { await finishEntranceLater(token: entranceToken) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(Haptics.detent, trigger: feedbackTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .onAppear {
            briefingModel.setSheetVisible(true)
        }
        // m-13: la entrada (y su reloj) empieza cuando HAY resumen: al abrir si ya está, o cuando llega. Antes contaba
        // desde que se abría la hoja y un resumen que llegaba tarde aparecía de golpe, sin entrada.
        .onChange(of: shownBriefing != nil, initial: true) { _, has in
            if has, entranceToken == 0 { startEntrance() }
        }
        .onDisappear {
            askTask?.cancel()
            for task in undoTasks.values { task.cancel() }
            undoTasks.removeAll()
            undoStates.removeAll()
            speaker.stop()
            briefingModel.setSheetVisible(false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                questionFocused = false
                speaker.stop()
            }
        }
        .onChange(of: speaker.activeTarget == .briefing) { _, speaking in
            if speaking {
                waveInLayout = true
                withAnimation(motion.fade) { waveShown = true }
            } else {
                withAnimation(motion.fade) { waveShown = false }
            }
        }
        .task(id: waveShown) {
            guard !waveShown, waveInLayout else { return }
            try? await Task.sleep(for: .seconds(motion.fadeDuration))
            guard !Task.isCancelled, !waveShown else { return }
            waveInLayout = false
        }
        #if DEBUG
        // Para las pruebas (B2): qué línea suena.
        .onChange(of: speaker.currentLine, initial: true) { _, line in LaunchProbe.shared.spokenLine = line ?? "-" }
        #endif
    }

    // MARK: - Cabecera

    private func header(for briefing: Briefing) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    AppMark(size: 28)
                    Text(assistantName)
                        .titan(.captionStrong)
                        .foregroundStyle(Theme.label2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(assistantName)
                .accessibilityIdentifier("nyx-sheet-title")

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
                #if DEBUG
                // Solo DEBUG, para las pruebas (B2): qué línea suena (el fondo de la hoja no se ve con ella delante).
                .accessibilityValue(DemoMode.isActive ? (speaker.currentLine ?? "-") : "")
                #endif

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
                .modifier(BriefingReveal(stage: 1, completed: entranceCompleted, token: entranceToken))
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
        // B2: la línea que suena ahora (solo en el resumen, no en las respuestas): se resalta y su importe rueda otra vez
        // desde 0 mientras se lee (con el ojo cerrado no hay cifra que rodar: `BriefingLineView` dibuja la máscara).
        let spokenNow = idPrefix == "briefing-line" && speaker.currentLine == line.id
        let content = HStack(alignment: .center, spacing: 10) {
            BriefingLineView(
                parts: line.parts,
                role: .row,
                color: Theme.label,
                countsFirstAmount: isHeroTotal || spokenNow,
                snapCountImmediately: userSkippedEntrance && !spokenNow
            )
            .id(spokenNow ? "leyendo-\(line.id)" : line.id)
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
        .modifier(SpokenHighlight(id: line.id, current: idPrefix == "briefing-line" ? speaker.currentLine : nil))

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

    // MARK: - Foco de Nyx («Para tener en cuenta») y novedades

    private func focusBlock(_ focus: NyxMessage) -> some View {
        let available = nyxAvailableActions(focus, state: model.state)
        let titles = NyxActionHandler.titles(for: available, in: focus, hidden: preferences.privateMode)
        return VStack(alignment: .leading, spacing: 8) {
            Text(nyxFocusHeader)
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)

            NyxMessageRow(
                entryID: focus.id,
                message: focus,
                delivery: nil,
                hidden: preferences.privateMode,
                actions: available,
                actionTitles: titles,
                undoState: undoStates[focus.id],
                showDismiss: false,
                isHighlighted: true,
                containerID: "nyx-focus",
                onAction: { action in
                    handleMessageAction(action, entryID: focus.id, previousStatus: .seen)
                },
                onDismiss: {},
                onUndo: { performUndo(for: focus.id) }
            )
        }
    }

    private func seenSummaryRow(text: String, scrollProxy: ScrollViewProxy) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(text)
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.identity)
                .accessibilityLabel(text)
                .accessibilityIdentifier("nyx-seen-line")

            Button {
                withAnimation(motion.reduce ? nil : motion.animation(.enter)) {
                    scrollProxy.scrollTo("nyx-seen-list", anchor: .top)
                }
            } label: {
                Text("Ver lo que he visto")
                    .titan(.captionStrong)
                    .foregroundStyle(Theme.label)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(Theme.raised, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Ver lo que he visto")
            .accessibilityIdentifier("nyx-see-what-i-saw")
        }
        .padding(16)
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private var collapsedDailyUpdateButton: some View {
        Button {
            withAnimation(motion.reduce ? motion.fade : motion.animation(.enter)) {
                dailyUpdateExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Text("Ver la puesta al día de hoy")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("nyx-expand-daily-update")
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
                .accessibilityIdentifier("card-open-\(card.topic.rawValue)")
            } else {
                interestCardHeaderAndBody(card, hasChevron: false)
            }

            actionsLayout {
                Button {
                    let saved = briefingModel.recordCardFeedback(
                        .interested,
                        for: card,
                        state: model.state,
                        portfolio: portfolio.portfolioForBackup,
                        book: accountBook.book
                    )
                    if saved { feedbackTick += 1 } else { errorTick += 1 }
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
                .accessibilityLabel("Me interesa: \(card.title)")
                .accessibilityAddTraits(liked ? [.isSelected] : [])
                .accessibilityIdentifier("card-like-\(card.topic.rawValue)")

                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal) {
                        let saved = briefingModel.recordCardFeedback(
                            .notInterested,
                            for: card,
                            state: model.state,
                            portfolio: portfolio.portfolioForBackup,
                            book: accountBook.book
                        )
                        if saved { feedbackTick += 1 } else { errorTick += 1 }
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
                .accessibilityLabel("No me interesa: \(card.title)")
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
            if let footer = card.footer {
                // U89: la nota de inversiones es el pie de la tarjeta, no un prefijo del texto.
                footnote(footer)
                    .accessibilityIdentifier("card-footer-\(card.topic.rawValue)")
            }
        }
        .contentShape(Rectangle())
    }

    /// Pie en estilo secundario (letra pequeña, gris).
    private func footnote(_ text: String) -> some View {
        Text(text)
            .titan(.meta)
            .foregroundStyle(Theme.label2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - «Pregúntame» (A1–A3, A5)

    private func askBlock(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Pregúntame algo de tu dinero…", text: $questionDraft)
                    .titan(.body)
                    .foregroundStyle(Theme.label)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.sentences)
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
                    Text("Estoy mirando tus datos…")
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
            // U89: la nota de inversiones va al final, como pie en estilo secundario, sin separador ni flecha.
            let rows = answer.lines.filter { $0.id != investmentDataOnlyLineID }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, line in
                briefingRow(line, idPrefix: "answer-line")
                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
            if let note = answer.lines.first(where: { $0.id == investmentDataOnlyLineID }) {
                footnote(BriefingLineView.accessibleText(for: note.parts, hidden: false))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .accessibilityIdentifier("answer-note-\(investmentDataOnlyLineID)")
            }
        }
        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-answer-card")
    }

    // MARK: - Botón inferior «Vale»

    private var bottomDoneBar: some View {
        VStack(spacing: 0) {
            // B2: mientras Onyx lee en voz alta, las 28 barras van encima de «Vale», DENTRO de la barra de abajo: la
            // lista reserva su alto (m-7: antes flotaban encima de «Lo que viene» y del borde de la fila siguiente).
            if waveInLayout {
                VoiceWave(speaking: true)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                    // Solo las barras se funden. m-7 (lote final): al parar se apagan EN SU SITIO y solo después la barra
                    // de abajo recupera su alto, de golpe: nunca se ven a medio apagar encima de la fila de arriba.
                    .opacity(waveShown ? 1 : 0)
                    .transition(.identity)
            }
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

    /// B1: los bloques entran uno detrás de otro, desde 0,12 s, 120 ms × 0,92ⁿ (prototipo `briefHTML`), subiendo
    /// 20 pt con el muelle `enter`; lo lee cada bloque (`BriefingReveal`), sin `Task.sleep`. Con Reducir movimiento,
    /// todos se funden a la vez. La entrada se da por acabada al final de su propio reloj (o con un toque).
    private func startEntrance() {
        userSkippedEntrance = false
        entranceCompleted = false
        entranceToken += 1
    }

    /// La entrada se da por acabada cuando ha entrado el último bloque: su espera lee `\.motion` (intensidad,
    /// Reducir movimiento y cámara lenta). Un toque la acaba antes.
    private func finishEntranceLater(token: Int) async {
        guard token > 0 else { return }
        let total = motion.reduce ? motion.pause(0.25) : motion.seconds(0.12) + motion.stagger(7, firstGap: 0.12, decay: 0.92)
            + motion.seconds(0.5)
        try? await Task.sleep(for: .seconds(total))
        guard !Task.isCancelled, entranceToken == token else { return }
        entranceCompleted = true
    }

    private func completeEntrance() {
        guard !entranceCompleted else { return }
        userSkippedEntrance = true
        withAnimation(motion.animation(.snap)) {
            entranceCompleted = true
        }
    }

    private func toggleBriefingSpeech(_ briefing: Briefing) {
        guard let input = briefingModel.input else { return }
        // El mismo texto de siempre, con dónde está cada línea dentro de él (B2: resaltar la que suena).
        let spoken = spokenBriefingLines(
            briefing,
            input: input,
            privateMode: preferences.privateMode,
            calendar: DateText.madridCalendar
        )
        speaker.toggle(spoken, target: .briefing)
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
        AccessibilityNotification.Announcement("Estoy mirando tus datos…").post()
        askTask = Task {
            await briefingModel.ask(
                question,
                state: model.state,
                portfolio: portfolio.portfolioForBackup,
                book: accountBook.book
            )
            guard !Task.isCancelled else { return }
            // U85: se anuncia el dato pedido, no la nota fija ni la negativa.
            if let answer = briefingModel.lastAnswer, let announced = assistantAnnouncedLine(answer) {
                let spoken = BriefingLineView.accessibleText(for: announced.parts, hidden: preferences.privateMode)
                AccessibilityNotification.Announcement(spoken).post()
            }
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                scrollProxy.scrollTo("assistant-answer-anchor", anchor: .bottom)
            }
        }
    }

    private func trigger(_ action: BriefingAction) {
        speaker.stop()
        onAction(action)
    }

    private func handleMessageAction(_ action: NyxAction, entryID: String, previousStatus: NyxEntryStatus) {
        if NyxActionHandler.isInline(action) {
            applyInlineAction(action, entryID: entryID, previousStatus: previousStatus)
            return
        }
        speaker.stop()
        briefingModel.markNyxEntry(entryID, status: .done)
        onNyxAction(action, entryID)
    }

    private func applyInlineAction(_ action: NyxAction, entryID: String, previousStatus: NyxEntryStatus) {
        let undoState: NyxUndoState
        do {
            switch action {
            case .markNotMine(let movementID):
                try model.setFlaggedNotMine(true, for: movementID)
                undoState = NyxUndoState(
                    entryID: entryID,
                    confirmationText: "Marcado como no es mío",
                    outcome: .markedNotMine(entryID: entryID, movementID: movementID, previousStatus: previousStatus)
                )
            case .muteMerchant(let merchant):
                try model.setMuted(true, merchant: merchant)
                undoState = NyxUndoState(
                    entryID: entryID,
                    confirmationText: "Comercio silenciado",
                    outcome: .mutedMerchant(entryID: entryID, merchant: merchant, previousStatus: previousStatus)
                )
            case .turnOffAlert(let alertSwitch):
                let previous = model.state.alertSettings
                try model.updateAlertSettings { $0 = alertSwitch.turnedOff($0) }
                undoState = NyxUndoState(
                    entryID: entryID,
                    confirmationText: "Aviso apagado",
                    outcome: .turnedOffAlert(entryID: entryID, previousSettings: previous, previousStatus: previousStatus)
                )
            default:
                return
            }
        } catch {
            errorTick += 1
            return
        }
        feedbackTick += 1
        briefingModel.markNyxEntry(entryID, status: .done)
        startUndoWindow(undoState)
    }

    private func dismissEntry(_ entry: NyxEntry) {
        feedbackTick += 1
        briefingModel.markNyxEntry(entry.id, status: .dismissed)
        startUndoWindow(NyxUndoState(
            entryID: entry.id,
            confirmationText: "Descartado",
            outcome: .dismissed(entryID: entry.id, previousStatus: entry.status)
        ))
    }

    private func startUndoWindow(_ state: NyxUndoState) {
        let id = state.entryID
        undoTasks[id]?.cancel()
        withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
            undoStates[id] = state
        }
        undoTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
                undoStates.removeValue(forKey: id)
            }
            undoTasks.removeValue(forKey: id)
        }
    }

    private func performUndo(for entryID: String) {
        guard let state = undoStates[entryID] else { return }
        undoTasks[entryID]?.cancel()
        undoTasks.removeValue(forKey: entryID)
        do {
            switch state.outcome {
            case .dismissed(let id, let previous):
                briefingModel.markNyxEntry(id, status: previous)
            case .markedNotMine(let id, let movementID, let previous):
                try model.setFlaggedNotMine(false, for: movementID)
                briefingModel.markNyxEntry(id, status: previous)
            case .mutedMerchant(let id, let merchant, let previous):
                try model.setMuted(false, merchant: merchant)
                briefingModel.markNyxEntry(id, status: previous)
            case .turnedOffAlert(let id, let previousSettings, let previous):
                try model.updateAlertSettings { $0 = previousSettings }
                briefingModel.markNyxEntry(id, status: previous)
            }
            feedbackTick += 1
            withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
                undoStates.removeValue(forKey: entryID)
            }
        } catch {
            errorTick += 1
        }
    }
}

/// B1: un bloque del resumen. Entra en su turno (`stage` 1…8: desde 0,12 s, 120 ms × 0,92ⁿ), sube 20 pt con el muelle
/// `enter` y aparece; con Reducir movimiento solo se funde. Con la entrada acabada (o saltada con un toque), está.
private struct BriefingReveal: ViewModifier {
    let stage: Int
    let completed: Bool
    let token: Int
    @Environment(\.motion) private var motion
    @State private var landed = -1

    /// Con `token` 0 la entrada aún no ha empezado (no hay resumen): nada se ve hasta que empieza.
    private var visible: Bool { completed || landed == token }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || motion.reduce ? 0 : motion.distance(20))
            .onAppear(perform: land)
            .onChange(of: token) { _, _ in land() }
    }

    private func land() {
        let token = token
        guard token > 0 else { return }
        let delay = motion.reduce ? 0 : motion.seconds(0.12) + motion.stagger(max(stage - 1, 0), firstGap: 0.12, decay: 0.92)
        withAnimation(motion.animation(.enter).delay(delay)) { landed = token }
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
        case .unusualPayment: "Si un pago es mucho mayor de lo habitual en ese comercio"
        case .subscriptionPriceChange: "Si te suben o te bajan una cuota fija"
        case .budgetClose: "Cuando un presupuesto llega al 80 % o se pasa"
        case .shortfall: "Si un próximo cobro deja una cuenta justa o corta"
        case .spendingPace: "Cómo vas este mes frente al mes anterior"
        case .portfolioMover: "Qué ha subido o bajado más en tu cartera (sin consejos)"
        }
    }
}

/// B2: mientras Onyx lee en voz alta, la línea que suena va resaltada (un fondo suave) y las demás del resumen se
/// apagan un poco; al callar, todas vuelven. Solo opacidad y color de fondo, con el fundido de `\.motion`. Con el ojo
/// cerrado el resalte no añade nada que leer: la línea ya es su máscara.
#if DEBUG
/// Solo DEBUG: publica dentro de la hoja `LaunchProbe.drawnLine` (identificador `briefing-drawn-line`) y el número de
/// la entrada en curso (`briefing-entrance`: 0 = aún no ha empezado).
/// m-6: `briefing-drawn-line` es un SUSTITUTO de lo dibujado: lo escribe el modificador que pinta el resalte con su
/// misma condición (`current == id`), no el píxel. Si el fondo dejara de pintarse (p. ej. el color a opacidad 0), esta
/// sonda seguiría diciendo la línea: eso solo lo ve una hoja de capturas.
private struct DrawnLineProbe: View {
    let entranceToken: Int

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("briefing-drawn-line")
                .accessibilityValue(LaunchProbe.shared.drawnLine)
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("briefing-entrance")
                .accessibilityValue(String(entranceToken))
        }
        .allowsHitTesting(false)
    }
}
#endif

private struct SpokenHighlight: ViewModifier {
    let id: String
    let current: String?
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let isCurrent = current == id
        content
            .opacity(current == nil || isCurrent ? 1 : 0.45)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.raised.opacity(isCurrent ? 1 : 0))
                    .padding(-6))
            .animation(motion.fade, value: current)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
            #if DEBUG
            // Para las pruebas (lote final): qué línea DIBUJA ahora su resalte (la vista que lo pinta, no el modelo).
            .onChange(of: isCurrent, initial: true) { _, now in
                if now {
                    LaunchProbe.shared.drawnLine = id
                } else if LaunchProbe.shared.drawnLine == id {
                    LaunchProbe.shared.drawnLine = "-"
                }
            }
            #endif
    }
}
