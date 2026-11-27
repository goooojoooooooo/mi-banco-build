import Foundation
import Observation
import SwiftUI
import MiBancoCore

extension Notification.Name {
    /// El motor de Nyx terminó una pasada y dejó decisiones (p. ej. un `.banner` para enseñar dentro de la app).
    static let nyxDidDecide = Notification.Name("com.mibanco.nyxDidDecide")
}

/// Momento de iOS en el que se despierta el motor de Nyx.
enum NyxMomentInput: Sendable {
    case notice(movementID: UUID, instantInsightIDs: [String] = [])
    case background
    case open(appActive: Bool)
}

/// Estado observable en primer plano de la memoria de Nyx (contador del punto, lista «Lo que he visto» y últimos avisos).
@MainActor @Observable
final class NyxState {
    static let shared = NyxState()

    private(set) var memory: NyxMemory = NyxMemory()
    var newCount: Int { memory.newCount }
    var entries: [NyxEntry] { memory.entries }
    private(set) var lastBannerDecision: NyxDecision?
    var guideStepVisibleCount = 0

    #if DEBUG
    private(set) var runs = 0
    private(set) var lastPostedNotification = "-"
    private(set) var lastDeliveries: [String] = []

    var probeSummary: String {
        let situations = memory.entries.map(\.observation.situation.rawValue).joined(separator: ",")
        let deliveries = lastDeliveries.isEmpty
            ? memory.entries.map(\.delivery.rawValue).joined(separator: ",")
            : lastDeliveries.joined(separator: ",")
        return [
            "corridas=\(runs)",
            "nuevas=\(memory.newCount)",
            "total=\(memory.entries.count)",
            "interrupciones=\(memory.interruptions.count)",
            "situaciones=\(situations.isEmpty ? "-" : situations)",
            "entregas=\(deliveries.isEmpty ? "-" : deliveries)",
            "aviso=\(lastPostedNotification)",
        ].joined(separator: ";")
    }
    #endif

    private init() {}

    func apply(memory: NyxMemory, decisions: [NyxDecision], posted: [NyxPostedAlert]) {
        self.memory = memory
        if let banner = decisions.first(where: { $0.delivery == .banner }) {
            self.lastBannerDecision = banner
        }
        #if DEBUG
        runs += 1
        if !decisions.isEmpty {
            lastDeliveries = decisions.map(\.delivery.rawValue)
        }
        if let first = posted.first {
            let combined = "\(first.title) · \(first.body)"
                .replacingOccurrences(of: ";", with: ",")
            lastPostedNotification = combined
        }
        #endif
    }

    func updateMemory(_ memory: NyxMemory) {
        self.memory = memory
    }

    func consumeBannerDecision() -> NyxDecision? {
        let current = lastBannerDecision
        lastBannerDecision = nil
        return current
    }

    func reloadFromStore() {
        #if DEBUG
        if DemoMode.isActive {
            if DemoMode.persistsNyxMemory {
                memory = NyxMemoryStore(directory: DemoMode.nyxDemoDirectory).loadRecovering()
            }
            return
        }
        #endif
        memory = SharedStore.makeNyxMemoryStore().loadRecovering()
    }
}

/// Motor de Nyx para los tres momentos de iOS (aviso, segundo plano, abrir la app).
/// Nunca ejecuta el modelo de lenguaje y nunca registra datos.
actor NyxEngine {
    static let shared = NyxEngine()
    static let bannerDecisionsKey = "bannerDecisions"

    #if DEBUG
    private var demoMemory = NyxMemory()
    private var demoResetDone = false
    #endif

    /// Ejecuta una pasada completa de Nyx: carga memoria, fija `firstUseAt` una vez, recoge observaciones desde
    /// `lastLookAt`, decide con `nyxDecide`, publica avisos, actualiza memoria (`lastLookAt = now`) y avisa a la UI.
    @discardableResult
    func run(_ input: NyxMomentInput) async -> [NyxDecision] {
        let now = AppClock.now
        let calendar = DateText.madridCalendar
        let hidden = AlertPoster.eyeClosed

        #if DEBUG
        if DemoMode.isActive {
            return await runDemo(input, now: now, calendar: calendar, hidden: hidden)
        }
        #endif

        guard let state = try? SharedStore.make().load() else { return [] }
        let book = AccountBookStore.load()
        let prefs = SharedStore.makeAssistantPreferencesStore().loadRecovering()
        let health = await NyxHealthProbe.current()
        let memoryStore = SharedStore.makeNyxMemoryStore()

        let outcome: (decisions: [NyxDecision], memory: NyxMemory)
        do {
            outcome = try memoryStore.update { memory in
                Self.evaluate(
                    input: input,
                    state: state,
                    book: book,
                    prefs: prefs,
                    health: health,
                    memory: &memory,
                    now: now,
                    calendar: calendar
                )
            }
        } catch {
            var fallback = memoryStore.loadRecovering()
            outcome = Self.evaluate(
                input: input,
                state: state,
                book: book,
                prefs: prefs,
                health: health,
                memory: &fallback,
                now: now,
                calendar: calendar
            )
        }

        let posted = await NyxNotifier.post(outcome.decisions, hidden: hidden, now: now, calendar: calendar)
        await NyxNotifier.scheduleExpiryReminder(expiresAt: health.appExpiresAt, hidden: hidden, now: now, calendar: calendar)
        await publish(memory: outcome.memory, decisions: outcome.decisions, posted: posted)
        return outcome.decisions
    }

    private static func evaluate(
        input: NyxMomentInput,
        state: LedgerState,
        book: AccountBook,
        prefs: AssistantPreferences,
        health: NyxAppHealth,
        memory: inout NyxMemory,
        now: Date,
        calendar: Calendar
    ) -> (decisions: [NyxDecision], memory: NyxMemory) {
        if memory.firstUseAt == nil {
            memory.firstUseAt = now
        }

        let moment: NyxMoment
        let appActive: Bool
        let newMovementIDs: [UUID]
        switch input {
        case .notice(let movementID, _):
            moment = .notice
            appActive = false
            newMovementIDs = [movementID]
        case .background:
            moment = .background
            appActive = false
            newMovementIDs = nyxNewMovementIDs(in: state, since: memory.lastLookAt, now: now)
        case .open(let active):
            moment = .open
            appActive = active
            newMovementIDs = nyxNewMovementIDs(in: state, since: memory.lastLookAt, now: now)
        }

        let moneyObs = nyxMoneyObservations(
            state: state,
            book: book,
            newMovementIDs: newMovementIDs,
            moment: moment,
            now: now,
            calendar: calendar
        )
        let healthObs = nyxHealthObservations(
            state: state,
            health: health,
            memory: memory,
            now: now,
            calendar: calendar
        )
        let learningObs = nyxLearningObservations(
            memory: memory,
            alertSettings: state.alertSettings,
            mutedMerchants: state.mutedMerchants,
            now: now,
            calendar: calendar
        )

        let decisions = nyxDecide(
            moneyObs + healthObs + learningObs,
            memory: memory,
            talk: prefs.nyxTalkLevel,
            moment: moment,
            appActive: appActive,
            notificationsAllowed: health.notificationsAllowed == true,
            mutedMerchants: state.mutedMerchants,
            alertSettings: state.alertSettings,
            now: now,
            calendar: calendar
        )

        memory.apply(decisions, now: now)
        memory.lastLookAt = now
        return (decisions, memory)
    }

    private func publish(memory: NyxMemory, decisions: [NyxDecision], posted: [NyxPostedAlert]) async {
        let banners = decisions.filter { $0.delivery == .banner }
        await MainActor.run {
            NyxState.shared.apply(memory: memory, decisions: decisions, posted: posted)
            NotificationCenter.default.post(
                name: .nyxDidDecide,
                object: nil,
                userInfo: [Self.bannerDecisionsKey: banners]
            )
        }
    }

    #if DEBUG
    private func runDemo(
        _ input: NyxMomentInput,
        now: Date,
        calendar: Calendar,
        hidden: Bool
    ) async -> [NyxDecision] {
        guard let scenario = DemoMode.nyxScenario else { return [] }
        let state: LedgerState
        let effectiveInput: NyxMomentInput
        switch scenario {
        case .shortfall:
            state = DemoMode.nyxShortfallLedger(now: now, calendar: calendar)
            effectiveInput = input
        case .shortfallBg:
            state = DemoMode.nyxShortfallLedger(now: now, calendar: calendar)
            effectiveInput = .background
        case .banner:
            state = DemoMode.nyxShortfallLedger(now: now, calendar: calendar)
            effectiveInput = .open(appActive: true)
        case .seenList:
            if demoMemory.entries.isEmpty {
                demoMemory = DemoMode.nyxSeenListMemory(state: DemoMode.state(now: now), now: now, calendar: calendar)
            }
            await publish(memory: demoMemory, decisions: [], posted: [])
            return []
        case .dailyFocus:
            await publish(memory: demoMemory, decisions: [], posted: [])
            return []
        }

        let book = DemoMode.accountBook()
        let prefs = AssistantPreferences()
        let health = DemoMode.nyxHealth

        let outcome: (decisions: [NyxDecision], memory: NyxMemory)
        if DemoMode.persistsNyxMemory {
            let store = NyxMemoryStore(directory: DemoMode.nyxDemoDirectory)
            if DemoMode.resetsNyxMemory && !demoResetDone {
                try? store.delete()
                demoResetDone = true
            }
            do {
                outcome = try store.update { memory in
                    Self.evaluate(
                        input: effectiveInput,
                        state: state,
                        book: book,
                        prefs: prefs,
                        health: health,
                        memory: &memory,
                        now: now,
                        calendar: calendar
                    )
                }
            } catch {
                var fallback = store.loadRecovering()
                outcome = Self.evaluate(
                    input: effectiveInput,
                    state: state,
                    book: book,
                    prefs: prefs,
                    health: health,
                    memory: &fallback,
                    now: now,
                    calendar: calendar
                )
            }
        } else {
            outcome = Self.evaluate(
                input: effectiveInput,
                state: state,
                book: book,
                prefs: prefs,
                health: health,
                memory: &demoMemory,
                now: now,
                calendar: calendar
            )
        }

        let posted = await NyxNotifier.post(outcome.decisions, hidden: hidden, now: now, calendar: calendar)
        await publish(memory: outcome.memory, decisions: outcome.decisions, posted: posted)
        return outcome.decisions
    }
    #endif
}

#if DEBUG
/// Elemento invisible de pruebas de interfaz para observar el estado del motor de Nyx (`nyx-engine-probe`).
struct NyxEngineProbeView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("nyx-engine-probe")
            .accessibilityValue(NyxState.shared.probeSummary)
            .allowsHitTesting(false)
    }
}
#endif
