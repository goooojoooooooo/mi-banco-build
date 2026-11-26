import Foundation

/// Nivel de proactividad de Nyx (Ajustes → Nyx → «Cuánto te hablo»).
public enum NyxTalkLevel: String, Codable, CaseIterable, Sendable {
    case whenItMatters
    case urgentOnly
    case listOnly

    public var displayName: String {
        switch self {
        case .whenItMatters: "Cuando importe"
        case .urgentOnly: "Solo lo urgente"
        case .listOnly: "Nunca, solo la lista"
        }
    }
}

/// Máximo de interrupciones propias de Nyx por día (el día empieza a las 05:00, como el resumen).
public let nyxDailyInterruptionCap = 3

/// Pausa mínima entre dos interrupciones no urgentes de la misma situación (4 horas).
public let nyxSituationCooldown: TimeInterval = 14_400

private let nyxDemoteWindowSeconds: TimeInterval = 30 * 86_400
private let nyxMuteDismissalWindowSeconds: TimeInterval = 60 * 86_400
private let nyxSuggestionCooldownSeconds: TimeInterval = 30 * 86_400

/// Horas de silencio de Nyx (23:00–08:00): los avisos propios llegan sin sonido.
public func nyxIsQuietHour(_ date: Date, calendar: Calendar) -> Bool {
    let hour = calendar.component(.hour, from: date)
    return hour >= 23 || hour < 8
}

/// true si el dueño ha descartado esta situación ≥ 3 veces en los últimos 30 días sin atender ninguna después.
public func nyxIsDemoted(_ s: NyxSituation, memory: NyxMemory, now: Date) -> Bool {
    let cutoff = now.addingTimeInterval(-nyxDemoteWindowSeconds)
    let recentDismissals = (memory.dismissals[s.rawValue] ?? [])
        .filter { $0 >= cutoff && $0 <= now }
        .sorted()
    guard recentDismissals.count >= 3 else { return false }
    let earliestOfThree = recentDismissals[recentDismissals.count - 3]
    let actedAfter = (memory.actions[s.rawValue] ?? []).contains { $0 >= earliestOfThree && $0 <= now }
    return !actedAfter
}

/// Decisión de entrega para una observación concreta.
public struct NyxDecision: Equatable, Sendable {
    public let observation: NyxObservation
    public let delivery: NyxDelivery

    public init(observation: NyxObservation, delivery: NyxDelivery) {
        self.observation = observation
        self.delivery = delivery
    }
}

/// Decide qué observaciones se guardan y cómo se entregan, aplicando en orden las reglas de diseño §6.5.
/// Las observaciones descartadas (ya conocidas o de comercio silenciado) no aparecen en el resultado.
public func nyxDecide(_ observations: [NyxObservation], memory: NyxMemory, talk: NyxTalkLevel, moment: NyxMoment,
                      appActive: Bool, mutedMerchants: Set<String>, alertSettings: AlertSettings,
                      now: Date, calendar: Calendar) -> [NyxDecision] {
    let sorted = observations.sorted { a, b in
        if a.priority != b.priority { return a.priority < b.priority }
        if a.observedAt != b.observedAt { return a.observedAt < b.observedAt }
        return a.id < b.id
    }

    var seenIDs = Set(memory.entries.map(\.id))
    let today = BriefingSchedule.briefingDay(of: now, calendar: calendar)
    var interruptionsToday = memory.interruptions.reduce(0) { count, date in
        guard date <= now, BriefingSchedule.briefingDay(of: date, calendar: calendar) == today else { return count }
        return count + 1
    }
    var lastBySituation = memory.lastInterruption.filter { $0.value <= now }
    var decisions: [NyxDecision] = []

    for obs in sorted {
        // 1. Ya la conoce → nada.
        guard seenIDs.insert(obs.id).inserted else { continue }

        // 2. Comercio silenciado (en las situaciones de comercio) → nada.
        if obs.situation.isMerchantCentric, let merchant = obs.facts.merchant {
            let key = normalizeMerchant(merchant)
            if !key.isEmpty, mutedMerchants.contains(key) { continue }
        }

        // 3. Vino por Avisos en el momento «aviso» → solo se apunta como `viaAvisos`.
        if moment == .notice, obs.viaInstantAlert {
            decisions.append(NyxDecision(observation: obs, delivery: .viaAvisos))
            continue
        }

        // 4. Interruptor de Avisos apagado (situaciones espejo) → solo lista.
        if let alertSwitch = obs.situation.alertSwitch, !alertSwitch.isOn(in: alertSettings) {
            decisions.append(NyxDecision(observation: obs, delivery: .list))
            continue
        }

        // 5. Aprendido que no le importa (≥ 3 descartes en 30 días sin atender) → solo lista.
        if nyxIsDemoted(obs.situation, memory: memory, now: now) {
            decisions.append(NyxDecision(observation: obs, delivery: .list))
            continue
        }

        // 6. Cuánto habla Nyx.
        let allowedByTalk: Bool = switch talk {
        case .whenItMatters: obs.priority == .urgent || obs.priority == .normal
        case .urgentOnly: obs.priority == .urgent
        case .listOnly: false
        }
        guard allowedByTalk else {
            decisions.append(NyxDecision(observation: obs, delivery: .list))
            continue
        }

        // 7. Pausa por situación (4 h para no urgentes).
        if obs.priority != .urgent, let last = lastBySituation[obs.situation.rawValue],
           last <= now, now.timeIntervalSince(last) < nyxSituationCooldown {
            decisions.append(NyxDecision(observation: obs, delivery: .list))
            continue
        }

        // 8. Tope diario (3 interrupciones propias al día; las urgentes no se paran pero cuentan).
        if obs.priority != .urgent, interruptionsToday >= nyxDailyInterruptionCap {
            decisions.append(NyxDecision(observation: obs, delivery: .list))
            continue
        }

        // 9. Forma de entrega.
        let delivery: NyxDelivery
        if obs.situation == .notificationsOff {
            delivery = appActive ? .banner : .list
        } else if appActive {
            delivery = .banner
        } else if nyxIsQuietHour(now, calendar: calendar) {
            delivery = .silentNotification
        } else {
            delivery = .notification
        }

        decisions.append(NyxDecision(observation: obs, delivery: delivery))
        if delivery.interrupts {
            interruptionsToday += 1
            lastBySituation[obs.situation.rawValue] = now
        }
    }

    return decisions
}

/// Observaciones de aprendizaje (siempre tranquilas, solo lista): proponer silenciar un comercio o apagar un interruptor de Avisos.
public func nyxLearningObservations(memory: NyxMemory, alertSettings: AlertSettings, mutedMerchants: Set<String>,
                                    now: Date, calendar: Calendar) -> [NyxObservation] {
    let monthKey = nyxMonthKey(now, calendar)
    let cutoff60 = now.addingTimeInterval(-nyxMuteDismissalWindowSeconds)
    let cutoff30 = now.addingTimeInterval(-nyxSuggestionCooldownSeconds)
    var out: [NyxObservation] = []

    // 1. ¿Silencio este comercio? (≥ 2 descartes en 60 días sin atender ninguno después, no silenciado, no propuesto en 30 días).
    for merchantKey in memory.merchantDismissals.keys.sorted() {
        guard !merchantKey.isEmpty, !mutedMerchants.contains(merchantKey) else { continue }
        if let lastSuggested = memory.suggestedAt["mute|\(merchantKey)"],
           lastSuggested <= now, lastSuggested >= cutoff30 { continue }

        let recentDismissals = (memory.merchantDismissals[merchantKey] ?? [])
            .filter { $0 >= cutoff60 && $0 <= now }
            .sorted()
        guard recentDismissals.count >= 2 else { continue }
        let earliestOfTwo = recentDismissals[recentDismissals.count - 2]
        let actedAfter = (memory.merchantActions[merchantKey] ?? []).contains { $0 >= earliestOfTwo && $0 <= now }
        guard !actedAfter else { continue }

        let displayName = memory.entries.first { entry in
            guard let m = entry.observation.facts.merchant else { return false }
            return normalizeMerchant(m) == merchantKey
        }?.observation.facts.merchant ?? merchantKey

        out.append(NyxObservation(
            situation: .suggestMute,
            subject: "\(merchantKey)|\(monthKey)",
            priority: .quiet,
            observedAt: now,
            facts: NyxFacts(merchant: displayName)))
    }

    // 2. ¿Dejo estos avisos? (≥ 3 descartes en 30 días del mismo interruptor sin atender ninguno, interruptor encendido, no propuesto en 30 días).
    for alertSwitch in NyxAlertSwitch.allCases {
        guard alertSwitch.isOn(in: alertSettings) else { continue }
        if let lastSuggested = memory.suggestedAt["alert|\(alertSwitch.rawValue)"],
           lastSuggested <= now, lastSuggested >= cutoff30 { continue }

        let matchingSituations = NyxSituation.allCases.filter { $0.alertSwitch == alertSwitch }
        let recentDismissals = matchingSituations.flatMap { situation in
            (memory.dismissals[situation.rawValue] ?? []).filter { $0 >= cutoff30 && $0 <= now }
        }.sorted()
        guard recentDismissals.count >= 3 else { continue }

        let earliestOfThree = recentDismissals[recentDismissals.count - 3]
        let actedAfter = matchingSituations.contains { situation in
            (memory.actions[situation.rawValue] ?? []).contains { $0 >= earliestOfThree && $0 <= now }
        }
        guard !actedAfter else { continue }

        out.append(NyxObservation(
            situation: .suggestAlertOff,
            subject: "\(alertSwitch.rawValue)|\(monthKey)",
            priority: .quiet,
            observedAt: now,
            facts: NyxFacts(alertSwitch: alertSwitch)))
    }

    return out
}

extension NyxMemory {
    /// Registra las decisiones tomadas, anota las propuestas hechas y poda fechas antiguas o futuras.
    public mutating func apply(_ decisions: [NyxDecision], now: Date) {
        for decision in decisions {
            record(decision.observation, delivery: decision.delivery, now: now)
            switch decision.observation.situation {
            case .suggestMute:
                if let merchant = decision.observation.facts.merchant {
                    let key = normalizeMerchant(merchant)
                    if !key.isEmpty { suggestedAt["mute|\(key)"] = now }
                }
            case .suggestAlertOff:
                if let alertSwitch = decision.observation.facts.alertSwitch {
                    suggestedAt["alert|\(alertSwitch.rawValue)"] = now
                }
            default:
                break
            }
        }
        prune(now: now)
    }
}
