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
    private(set) var input: BriefingInput?
    private(set) var openingText: String = ""
    private(set) var cards: [InterestCard] = []
    private(set) var chips: [AssistantChip] = []
    private(set) var lastAnswer: AssistantAnswer?
    private(set) var lastQuestion: String = ""
    private(set) var isAnswering = false
    private(set) var assistantPreferences: AssistantPreferences

    private let preferencesStore: AssistantPreferencesStore
    private let writer: any BriefingWriter
    private var prefetchedChoice: (situation: OpeningSituation, choice: Int)?
    private var prefetchTask: Task<Void, Never>?
    private var isSheetVisible = false
    private var askGeneration = 0

    init(preferencesStore: AssistantPreferencesStore = SharedStore.makeAssistantPreferencesStore(),
         writer: any BriefingWriter = makeDefaultBriefingWriter()) {
        self.preferencesStore = preferencesStore
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
        BriefingSchedule.due(previous: record, now: Date(), calendar: DateText.madridCalendar) == nil
    }

    /// Lectura segura fuera del actor principal (para `BackgroundRefresh.run()`).
    nonisolated static func storedShownToday(now: Date = Date()) -> Bool {
        let stored = loadStoredRecord()
        return BriefingSchedule.due(previous: stored, now: now, calendar: DateText.madridCalendar) == nil
    }

    func dueRecord(now: Date = Date()) -> BriefingRecord? {
        #if DEBUG
        if DemoMode.isActive {
            guard DemoMode.briefingMode != nil, record == nil else { return nil }
            return BriefingRecord(shownAt: now, since: now.addingTimeInterval(-86_400))
        }
        #endif
        return BriefingSchedule.due(previous: record, now: now, calendar: DateText.madridCalendar)
    }

    func manualRecord(now: Date = Date()) -> BriefingRecord {
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
    func markOnboardingCompleted(now: Date = Date()) {
        markShown(BriefingRecord(shownAt: now, since: now))
    }

    func setSheetVisible(_ visible: Bool) {
        isSheetVisible = visible
        if !visible {
            askGeneration += 1
            isAnswering = false
            lastAnswer = nil
            lastQuestion = ""
        }
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
        let candidateBriefing = makeBriefing(computed, calendar: cal)
        if prefetchedChoice?.situation == candidateBriefing.situation { return }

        prefetchTask?.cancel()
        let situation = candidateBriefing.situation
        let currentWriter = writer
        prefetchTask = Task { [weak self] in
            let chosen = await currentWriter.openingChoice(for: candidateBriefing)
            guard !Task.isCancelled, let self, !self.isSheetVisible, let chosen else { return }
            self.prefetchedChoice = (situation, chosen)
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

        let built = makeBriefing(computedInput, calendar: cal)
        let candidateCount = openingCandidateCount(for: built.situation)
        let validModelChoice: Int?
        if !privateMode, let pre = prefetchedChoice,
           pre.situation == built.situation,
           candidateCount > 0, (1...candidateCount).contains(pre.choice) {
            validModelChoice = pre.choice
        } else {
            validModelChoice = nil
        }

        self.input = computedInput
        self.briefing = built
        self.openingText = openingLine(
            briefing: built, choice: validModelChoice, day: now, privateMode: privateMode
        )
        self.prefetchedChoice = nil
        self.prefetchTask?.cancel()
        self.prefetchTask = nil
        self.lastAnswer = nil
        self.lastQuestion = ""
        self.isAnswering = false
        self.cards = interestCards(
            state: state, portfolio: portfolio, book: book, now: now, calendar: cal,
            preferences: assistantPreferences
        )
        self.chips = suggestedAssistantChips(state: state, portfolio: portfolio, now: now, calendar: cal)
    }

    /// Responde a una pregunta con hechos calculados por Core (A2, A3, J21(d)). Nunca guarda la pregunta ni la respuesta.
    func ask(_ question: String, state: LedgerState, portfolio: Portfolio?, book: AccountBook,
             now: Date = Date()) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        askGeneration += 1
        let gen = askGeneration
        let cal = DateText.madridCalendar
        lastQuestion = trimmed
        isAnswering = true

        let routedIntent: AssistantIntent?
        if isAdviceRequest(trimmed, portfolio: portfolio) {
            routedIntent = nil
        } else {
            routedIntent = await writer.routeQuestion(trimmed, now: now, calendar: cal, portfolio: portfolio)
        }

        guard !Task.isCancelled, askGeneration == gen else { return }
        let answer = answerQuestion(
            trimmed,
            state: state,
            portfolio: portfolio,
            book: book,
            briefingInput: input,
            modelIntent: routedIntent,
            now: now,
            calendar: cal
        )
        lastAnswer = answer
        if !answer.chips.isEmpty {
            chips = answer.chips
        }
        isAnswering = false
    }

    func feedback(for cardID: String) -> CardFeedback? {
        assistantPreferences.feedback(for: cardID)
    }

    func recordCardFeedback(_ feedback: CardFeedback, for card: InterestCard,
                            state: LedgerState, portfolio: Portfolio?, book: AccountBook,
                            now: Date = Date()) {
        assistantPreferences.recordFeedback(feedback, for: card, now: now)
        #if DEBUG
        if !DemoMode.isActive {
            _ = try? preferencesStore.update { $0.recordFeedback(feedback, for: card, now: now) }
        }
        #else
        _ = try? preferencesStore.update { $0.recordFeedback(feedback, for: card, now: now) }
        #endif
        cards = interestCards(
            state: state, portfolio: portfolio, book: book, now: now,
            calendar: DateText.madridCalendar, preferences: assistantPreferences
        )
    }

    func isTopicEnabled(_ topic: AssistantTopic) -> Bool {
        assistantPreferences.isEnabled(topic)
    }

    func setTopicEnabled(_ enabled: Bool, for topic: AssistantTopic) {
        assistantPreferences.setEnabled(enabled, for: topic)
        #if DEBUG
        if !DemoMode.isActive {
            _ = try? preferencesStore.update { $0.setEnabled(enabled, for: topic) }
        }
        #else
        _ = try? preferencesStore.update { $0.setEnabled(enabled, for: topic) }
        #endif
        if !enabled {
            cards.removeAll { $0.topic == topic }
        }
    }

    private nonisolated static func loadStoredRecord() -> BriefingRecord? {
        guard let data = UserDefaults.standard.data(forKey: recordKey) else { return nil }
        return try? JSONDecoder().decode(BriefingRecord.self, from: data)
    }
}
