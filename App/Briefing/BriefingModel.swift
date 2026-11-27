import Foundation
import Observation
import MiBancoCore

/// Estado vivo del resumen diario y del asistente Onyx (Plan 4b, tareas 9, 10 y 13 ampliada A1–A6).
/// - El registro `BriefingRecord` vive en `UserDefaults` (`"briefingRecord"`); en modo demo, solo en memoria.
/// - Las preferencias de «Te puede interesar» viven en `AssistantPreferencesStore`; en modo demo, solo en memoria.
/// - Las preguntas y respuestas de «Pregúntame» NUNCA se guardan en disco (A2).
@MainActor @Observable
final class BriefingModel {
    nonisolated static let recordKey = "briefingRecord"

    private(set) var record: BriefingRecord?
    private(set) var briefing: Briefing?
    private(set) var dailyUpdate: NyxDailyUpdate?
    private(set) var input: BriefingInput?
    private(set) var openingText: String = ""
    private(set) var nyxEntries: [NyxEntry] = []
    private(set) var initialNewEntryIDs: Set<String> = []
    private(set) var seenSinceLastLookCount: Int = 0
    private(set) var cards: [InterestCard] = []
    private(set) var chips: [AssistantChip] = []
    private(set) var lastAnswer: AssistantAnswer?
    private(set) var lastReply: NyxReply?
    private(set) var conversation = NyxConversation()
    private(set) var lastQuestion: String = ""
    private(set) var isAnswering = false
    private(set) var assistantPreferences: AssistantPreferences

    private let preferencesStore: AssistantPreferencesStore
    private let nyxMemoryStore: NyxMemoryStore
    private let writer: any BriefingWriter
    private var prefetchedChoice: (situation: OpeningSituation, choice: Int)?
    private var prefetchedFocusChoice: (ids: [String], choice: Int)?
    private var prefetchTask: Task<Void, Never>?
    private var isSheetVisible = false
    private var askGeneration = 0
    #if DEBUG
    private var demoNyxMemory: NyxMemory?
    #endif

    init(preferencesStore: AssistantPreferencesStore = SharedStore.makeAssistantPreferencesStore(),
         nyxMemoryStore: NyxMemoryStore = SharedStore.makeNyxMemoryStore(),
         writer: any BriefingWriter = makeDefaultBriefingWriter()) {
        self.preferencesStore = preferencesStore
        self.nyxMemoryStore = nyxMemoryStore
        self.writer = writer
        #if DEBUG
        if DemoMode.isActive {
            self.record = nil
            self.assistantPreferences = AssistantPreferences()
            return
        }
        #endif
        self.record = Self.loadStoredRecord()
        self.assistantPreferences = preferencesStore.loadRecovering()
    }

    var shownToday: Bool {
        BriefingSchedule.due(previous: record, now: AppClock.now, calendar: DateText.madridCalendar) == nil
    }

    /// Lectura segura fuera del actor principal (para `BackgroundRefresh.run()`).
    nonisolated static func storedShownToday(now: Date = Date()) -> Bool {
        let stored = loadStoredRecord()
        return BriefingSchedule.due(previous: stored, now: now, calendar: DateText.madridCalendar) == nil
    }

    func dueRecord(now: Date = AppClock.now) -> BriefingRecord? {
        #if DEBUG
        if DemoMode.isActive {
            guard DemoMode.briefingMode != nil else { return nil }
            return BriefingSchedule.due(previous: record, now: now, calendar: DateText.madridCalendar)
        }
        #endif
        return BriefingSchedule.due(previous: record, now: now, calendar: DateText.madridCalendar)
    }

    func manualRecord(now: Date = AppClock.now) -> BriefingRecord {
        #if DEBUG
        if DemoMode.isActive {
            if let existing = record {
                return BriefingRecord(shownAt: now, since: existing.since)
            }
            return BriefingRecord(shownAt: now, since: now.addingTimeInterval(-86_400))
        }
        #endif
        return BriefingSchedule.manual(previous: record, now: now, calendar: DateText.madridCalendar)
    }

    func markShown(_ newRecord: BriefingRecord) {
        record = newRecord
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        if let data = try? JSONEncoder().encode(newRecord) {
            UserDefaults.standard.set(data, forKey: Self.recordKey)
        }
    }

    /// Al terminar la bienvenida se guarda el registro de hoy para que no salga un resumen vacío justo detrás (Tarea 12).
    func markOnboardingCompleted(now: Date = AppClock.now) {
        markShown(BriefingRecord(shownAt: now, since: now))
    }

    func setSheetVisible(_ visible: Bool) {
        isSheetVisible = visible
        if !visible {
            resetConversation()
        }
    }

    /// Borra la memoria breve de la conversación (al cerrar la hoja, bloquear o pasar a segundo plano; nunca va a disco).
    func resetConversation() {
        askGeneration += 1
        isAnswering = false
        conversation.reset()
        lastReply = nil
        lastAnswer = nil
        lastQuestion = ""
    }

    func reloadPreferences() {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        record = Self.loadStoredRecord()
        assistantPreferences = preferencesStore.loadRecovering()
    }

    /// Precalienta la elección de frase de apertura en el modelo del dispositivo al pasar a `.active` (antes de mostrar
    /// la hoja). Nunca enseña nada por adelantado ni cambia la frase mientras la hoja está visible (J21, tarea 10).
    func prefetchOpeningIfNeeded(state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                                 privateMode: Bool, now: Date = Date()) {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        guard !privateMode, !isSheetVisible, let due = dueRecord(now: now) else { return }
        let cal = DateText.madridCalendar
        let computed = briefingInput(
            state: state, portfolio: portfolio, book: book, record: due,
            isFirst: record == nil, now: now, calendar: cal
        )
        let candidateBriefing = makeNyxBriefing(computed, calendar: cal)
        let memory = nyxMemoryStore.loadRecovering()
        let currentObs = nyxMoneyObservations(
            state: state, book: book,
            newMovementIDs: nyxNewMovementIDs(in: state, since: memory.lastLookAt, now: now),
            moment: .open, now: now, calendar: cal
        )
        let focusCandidates = nyxFocusCandidates(
            current: currentObs, memory: memory, briefing: candidateBriefing,
            input: computed, now: now, calendar: cal
        )
        let candidateIDs = focusCandidates.map(\.id)
        let needOpening = prefetchedChoice?.situation != candidateBriefing.situation
        let needFocus = focusCandidates.count >= 2 && prefetchedFocusChoice?.ids != candidateIDs
        if !needOpening && !needFocus { return }

        prefetchTask?.cancel()
        let situation = candidateBriefing.situation
        let currentWriter = writer
        prefetchTask = Task { [weak self] in
            if needOpening, let chosen = await currentWriter.openingChoice(for: candidateBriefing) {
                guard !Task.isCancelled, let self, !self.isSheetVisible else { return }
                self.prefetchedChoice = (situation, chosen)
            }
            if needFocus, let focusChosen = await currentWriter.focusChoice(for: focusCandidates) {
                guard !Task.isCancelled, let self, !self.isSheetVisible else { return }
                self.prefetchedFocusChoice = (candidateIDs, focusChosen)
            }
        }
    }

    /// Prepara el resumen, las tarjetas de «Te puede interesar» y las fichas de «Pregúntame».
    /// Llamar antes de `markShown` para conservar correctamente `isFirst` en el primer resumen.
    func prepare(record activeRecord: BriefingRecord, isFirst: Bool, state: LedgerState,
                 portfolio: Portfolio?, book: AccountBook, privateMode: Bool, now: Date = Date()) {
        let cal = DateText.madridCalendar
        let computedInput: BriefingInput
        #if DEBUG
        if DemoMode.isActive, let mode = DemoMode.briefingMode {
            computedInput = DemoMode.briefingInput(
                mode: mode,
                shortfall: DemoMode.briefingShortfall,
                state: state,
                now: now
            )
        } else {
            computedInput = briefingInput(
                state: state, portfolio: portfolio, book: book, record: activeRecord,
                isFirst: isFirst, now: now, calendar: cal
            )
        }
        #else
        computedInput = briefingInput(
            state: state, portfolio: portfolio, book: book, record: activeRecord,
            isFirst: isFirst, now: now, calendar: cal
        )
        #endif

        let nyxNow = computedInput.now
        var memory = loadCurrentNyxMemory(state: state, now: nyxNow, calendar: cal)
        let focusCandidates: [NyxObservation]
        #if DEBUG
        if DemoMode.isActive {
            switch DemoMode.nyxScenario {
            case .dailyFocus:
                focusCandidates = [DemoMode.nyxDemoShortfallObservation(now: nyxNow, calendar: cal)]
            case .seenList:
                let baseBriefing = makeNyxBriefing(computedInput, calendar: cal)
                focusCandidates = nyxFocusCandidates(
                    current: [], memory: memory, briefing: baseBriefing,
                    input: computedInput, now: nyxNow, calendar: cal
                )
            case .shortfall, .shortfallBg, .banner:
                let baseBriefing = makeNyxBriefing(computedInput, calendar: cal)
                focusCandidates = nyxFocusCandidates(
                    current: [], memory: memory, briefing: baseBriefing,
                    input: computedInput, now: nyxNow, calendar: cal
                )
            case nil:
                focusCandidates = []
            }
        } else {
            let baseBriefing = makeNyxBriefing(computedInput, calendar: cal)
            let currentObs = nyxMoneyObservations(
                state: state, book: book,
                newMovementIDs: nyxNewMovementIDs(in: state, since: memory.lastLookAt, now: now),
                moment: .open, now: now, calendar: cal
            ) + nyxLearningObservations(
                memory: memory, alertSettings: state.alertSettings,
                mutedMerchants: state.mutedMerchants, now: now, calendar: cal
            )
            focusCandidates = nyxFocusCandidates(
                current: currentObs, memory: memory, briefing: baseBriefing,
                input: computedInput, now: now, calendar: cal
            )
        }
        #else
        let baseBriefing = makeNyxBriefing(computedInput, calendar: cal)
        let currentObs = nyxMoneyObservations(
            state: state, book: book,
            newMovementIDs: nyxNewMovementIDs(in: state, since: memory.lastLookAt, now: now),
            moment: .open, now: now, calendar: cal
        ) + nyxLearningObservations(
            memory: memory, alertSettings: state.alertSettings,
            mutedMerchants: state.mutedMerchants, now: now, calendar: cal
        )
        focusCandidates = nyxFocusCandidates(
            current: currentObs, memory: memory, briefing: baseBriefing,
            input: computedInput, now: now, calendar: cal
        )
        #endif

        let preliminaryBriefing = makeNyxBriefing(computedInput, calendar: cal)
        let candidateCount = openingCandidateCount(for: preliminaryBriefing.situation)
        let validModelChoice: Int?
        if !privateMode, let pre = prefetchedChoice,
           pre.situation == preliminaryBriefing.situation,
           candidateCount > 0, (1...candidateCount).contains(pre.choice) {
            validModelChoice = pre.choice
        } else {
            validModelChoice = nil
        }

        let candidateIDs = focusCandidates.map(\.id)
        let validFocusChoice: Int?
        if !privateMode, let preFocus = prefetchedFocusChoice,
           preFocus.ids == candidateIDs,
           (1...max(1, focusCandidates.count)).contains(preFocus.choice) {
            validFocusChoice = preFocus.choice
        } else {
            validFocusChoice = nil
        }

        let newIDsBeforeOpen = Set(memory.entries.filter { $0.status == .new }.map(\.id))
        let newCountBeforeOpen = newIDsBeforeOpen.count

        let builtUpdate = nyxDailyUpdate(
            input: computedInput,
            candidates: focusCandidates,
            focusChoice: validFocusChoice,
            openingChoice: validModelChoice,
            seenSinceLastLook: newCountBeforeOpen,
            privateMode: privateMode,
            calendar: cal
        )

        if newCountBeforeOpen > 0 {
            memory.markAllSeen(now: nyxNow)
            persistNyxMemory(memory)
        }

        self.input = computedInput
        self.dailyUpdate = builtUpdate
        self.briefing = builtUpdate.briefing
        self.openingText = builtUpdate.opening
        self.initialNewEntryIDs = newIDsBeforeOpen
        self.seenSinceLastLookCount = newCountBeforeOpen
        self.nyxEntries = memory.entries
        self.prefetchedChoice = nil
        self.prefetchedFocusChoice = nil
        self.prefetchTask?.cancel()
        self.prefetchTask = nil
        self.conversation.reset()
        self.lastReply = nil
        self.lastAnswer = nil
        self.lastQuestion = ""
        self.isAnswering = false
        self.cards = interestCards(
            state: state, portfolio: portfolio, book: book, now: now, calendar: cal,
            preferences: assistantPreferences
        )
        self.chips = suggestedAssistantChips(state: state, portfolio: portfolio, now: now, calendar: cal)
    }

    /// Cambia el estado de una entrada de «Lo que he visto» (`dismissed`, `done`, `seen` al deshacer) y lo guarda.
    func markNyxEntry(_ id: String, status: NyxEntryStatus, now: Date = AppClock.now) {
        #if DEBUG
        if DemoMode.isActive && !DemoMode.persistsNyxMemory {
            var current = demoNyxMemory ?? NyxState.shared.memory
            current.mark(id, status, now: now)
            demoNyxMemory = current
            nyxEntries = current.entries
            NyxState.shared.updateMemory(current)
            return
        }
        #endif
        let store = activeNyxMemoryStore()
        if let updated = try? store.update({ memory -> NyxMemory in
            memory.mark(id, status, now: now)
            return memory
        }) {
            nyxEntries = updated.entries
            NyxState.shared.updateMemory(updated)
        } else {
            var fallback = store.loadRecovering()
            fallback.mark(id, status, now: now)
            nyxEntries = fallback.entries
            NyxState.shared.updateMemory(fallback)
        }
    }

    /// Borra por completo la memoria de Nyx («Olvidar lo que he aprendido»).
    func forgetNyxMemory() {
        #if DEBUG
        if DemoMode.isActive {
            demoNyxMemory = NyxMemory()
            if DemoMode.persistsNyxMemory {
                try? NyxMemoryStore(directory: DemoMode.nyxDemoDirectory).delete()
            }
            nyxEntries = []
            initialNewEntryIDs = []
            seenSinceLastLookCount = 0
            NyxState.shared.updateMemory(NyxMemory())
            return
        }
        #endif
        try? nyxMemoryStore.delete()
        nyxEntries = []
        initialNewEntryIDs = []
        seenSinceLastLookCount = 0
        NyxState.shared.updateMemory(NyxMemory())
    }

    private func activeNyxMemoryStore() -> NyxMemoryStore {
        #if DEBUG
        if DemoMode.isActive && DemoMode.persistsNyxMemory {
            return NyxMemoryStore(directory: DemoMode.nyxDemoDirectory)
        }
        #endif
        return nyxMemoryStore
    }

    private func loadCurrentNyxMemory(state: LedgerState, now: Date, calendar: Calendar) -> NyxMemory {
        #if DEBUG
        if DemoMode.isActive {
            if let existing = demoNyxMemory { return existing }
            if DemoMode.persistsNyxMemory {
                return NyxMemoryStore(directory: DemoMode.nyxDemoDirectory).loadRecovering()
            }
            switch DemoMode.nyxScenario {
            case .seenList:
                let seeded = DemoMode.nyxSeenListMemory(state: state, now: now, calendar: calendar)
                demoNyxMemory = seeded
                NyxState.shared.updateMemory(seeded)
                return seeded
            case .shortfall, .shortfallBg, .banner:
                return NyxState.shared.memory
            case .dailyFocus, nil:
                return NyxMemory()
            }
        }
        #endif
        return nyxMemoryStore.loadRecovering()
    }

    private func persistNyxMemory(_ memory: NyxMemory) {
        #if DEBUG
        if DemoMode.isActive && !DemoMode.persistsNyxMemory {
            demoNyxMemory = memory
            NyxState.shared.updateMemory(memory)
            return
        }
        #endif
        try? activeNyxMemoryStore().save(memory)
        NyxState.shared.updateMemory(memory)
    }

    /// Responde a una pregunta con hechos calculados por Core (`nyxAnswer`), recordando la última intención solo en
    /// memoria mientras la hoja sigue abierta y respetando `privateMode` (`m-11`). Nunca guarda preguntas ni respuestas.
    func ask(_ question: String, state: LedgerState, portfolio: Portfolio?, book: AccountBook,
             privateMode: Bool = false, now: Date = AppClock.now) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        askGeneration += 1
        let gen = askGeneration
        let cal = DateText.madridCalendar
        lastQuestion = trimmed
        isAnswering = true

        let knownMerchants = Set(
            state.movements.flatMap { [$0.merchant, $0.bankMerchant].compactMap { $0 }.map(normalizeMerchant) }
        )
        let preRouted = nyxRouteQuestion(
            trimmed,
            conversation: conversation,
            state: state,
            portfolio: portfolio,
            now: now,
            calendar: cal
        )
        let routedIntent: AssistantIntent?
        if isAdviceRequest(trimmed, portfolio: portfolio, knownMerchants: knownMerchants) {
            routedIntent = nil
        } else if case .assistant(.unknown) = preRouted {
            routedIntent = await writer.routeQuestion(
                trimmed, now: now, calendar: cal, portfolio: portfolio, knownMerchants: knownMerchants
            )
        } else {
            routedIntent = nil
        }

        let health = await NyxHealthProbe.current()
        guard !Task.isCancelled, askGeneration == gen else { return }

        let currentMemory = loadCurrentNyxMemory(state: state, now: now, calendar: cal)
        let healthObs = nyxHealthObservations(state: state, health: health, memory: currentMemory, now: now, calendar: cal)
        var nextConversation = conversation
        let reply = nyxAnswer(
            trimmed,
            conversation: &nextConversation,
            modelIntent: routedIntent,
            memory: currentMemory,
            health: healthObs,
            state: state,
            portfolio: portfolio,
            book: book,
            privateMode: privateMode,
            now: now,
            calendar: cal
        )
        conversation = nextConversation
        lastReply = reply
        lastAnswer = reply.answer
        if !reply.answer.chips.isEmpty {
            chips = reply.answer.chips
        }
        isAnswering = false
    }

    func feedback(for cardID: String) -> CardFeedback? {
        assistantPreferences.feedback(for: cardID)
    }

    @discardableResult
    func recordCardFeedback(_ feedback: CardFeedback, for card: InterestCard,
                            state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                            now: Date = Date()) -> Bool {
        #if DEBUG
        if DemoMode.isActive {
            if DemoMode.prefsFail { return false }
            assistantPreferences.recordFeedback(feedback, for: card, now: now)
            cards = interestCards(
                state: state, portfolio: portfolio, book: book, now: now,
                calendar: DateText.madridCalendar, preferences: assistantPreferences
            )
            return true
        }
        #endif
        guard let updated = try? preferencesStore.update({ current -> AssistantPreferences in
            current.recordFeedback(feedback, for: card, now: now)
            return current
        }) else {
            return false
        }
        assistantPreferences = updated
        cards = interestCards(
            state: state, portfolio: portfolio, book: book, now: now,
            calendar: DateText.madridCalendar, preferences: assistantPreferences
        )
        return true
    }

    func isTopicEnabled(_ topic: AssistantTopic) -> Bool {
        assistantPreferences.isEnabled(topic)
    }

    @discardableResult
    func setTopicEnabled(_ enabled: Bool, for topic: AssistantTopic) -> Bool {
        #if DEBUG
        if DemoMode.isActive {
            if DemoMode.prefsFail { return false }
            assistantPreferences.setEnabled(enabled, for: topic)
            if !enabled {
                cards.removeAll { $0.topic == topic }
            }
            return true
        }
        #endif
        guard let updated = try? preferencesStore.update({ current -> AssistantPreferences in
            current.setEnabled(enabled, for: topic)
            return current
        }) else {
            return false
        }
        assistantPreferences = updated
        if !enabled {
            cards.removeAll { $0.topic == topic }
        }
        return true
    }

    private nonisolated static func loadStoredRecord() -> BriefingRecord? {
        guard let data = UserDefaults.standard.data(forKey: recordKey) else { return nil }
        return try? JSONDecoder().decode(BriefingRecord.self, from: data)
    }
}
