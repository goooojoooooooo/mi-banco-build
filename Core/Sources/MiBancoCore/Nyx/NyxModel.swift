import Foundation

/// Nombre visible del asistente de Onyx. La app sigue llamándose `appDisplayName` («Onyx»).
public let assistantName = "Nyx"

/// Interruptores de la pestaña Avisos que Nyx respeta y sobre los que puede proponer cambios.
public enum NyxAlertSwitch: String, Codable, CaseIterable, Sendable {
    case largePayment
    case income
    case subscriptions
    case duplicateCharge
    case lowBalance
    case budgets

    public func isOn(in settings: AlertSettings) -> Bool {
        switch self {
        case .largePayment: settings.largePayment
        case .income: settings.income
        case .subscriptions: settings.subscriptions
        case .duplicateCharge: settings.duplicateCharge
        case .lowBalance: settings.lowBalance
        case .budgets: settings.budgets
        }
    }

    public func turnedOff(_ settings: AlertSettings) -> AlertSettings {
        var copy = settings
        switch self {
        case .largePayment: copy.largePayment = false
        case .income: copy.income = false
        case .subscriptions: copy.subscriptions = false
        case .duplicateCharge: copy.duplicateCharge = false
        case .lowBalance: copy.lowBalance = false
        case .budgets: copy.budgets = false
        }
        return copy
    }

    public var spanishName: String {
        switch self {
        case .largePayment: "pagos grandes"
        case .income: "ingresos"
        case .subscriptions: "suscripciones"
        case .duplicateCharge: "cobros duplicados"
        case .lowBalance: "saldo bajo"
        case .budgets: "presupuestos"
        }
    }
}

/// Situaciones que Nyx vigila (dinero, salud de la app y propuestas aprendidas).
public enum NyxSituation: String, Codable, CaseIterable, Sendable {
    case unusualPayment
    case largePayment
    case duplicateCharge
    case subscriptionUp
    case subscriptionDown
    case budgetNear
    case budgetExceeded
    case salary
    case largeIncome
    case lowBalance
    case shortfall
    case budgetOffPace
    case categoryAboveNormal
    case bankExpired
    case bankExpiring
    case bankStale
    case alertsSilent
    case alertsNeverArrived
    case notificationsOff
    case appExpiring
    case suggestMute
    case suggestAlertOff

    /// Tipo de aviso de `Insights.swift` del que esta situación es espejo, o nil si es propia de Nyx.
    public var mirrors: InsightKind? {
        switch self {
        case .unusualPayment: .unusualPayment
        case .largePayment: .largePayment
        case .duplicateCharge: .duplicateCharge
        case .subscriptionUp, .subscriptionDown: .subscriptionPriceChange
        case .budgetNear: .budgetWarning
        case .budgetExceeded: .budgetExceeded
        case .salary: .salary
        case .largeIncome: .largeIncome
        case .lowBalance: .lowBalance
        case .shortfall, .budgetOffPace, .categoryAboveNormal,
             .bankExpired, .bankExpiring, .bankStale, .alertsSilent, .alertsNeverArrived,
             .notificationsOff, .appExpiring, .suggestMute, .suggestAlertOff:
            nil
        }
    }

    /// Situaciones centradas en un comercio: respetan comercios silenciados y alimentan `merchantDismissals`.
    public var isMerchantCentric: Bool {
        switch self {
        case .unusualPayment, .largePayment, .duplicateCharge, .subscriptionUp, .subscriptionDown, .suggestMute:
            true
        default:
            false
        }
    }

    /// Interruptor de Avisos que controla esta situación espejo (nil para situaciones propias de Nyx).
    public var alertSwitch: NyxAlertSwitch? {
        switch self {
        case .unusualPayment, .largePayment: .largePayment
        case .salary, .largeIncome: .income
        case .subscriptionUp, .subscriptionDown: .subscriptions
        case .duplicateCharge: .duplicateCharge
        case .lowBalance: .lowBalance
        case .budgetNear, .budgetExceeded: .budgets
        default: nil
        }
    }

    /// true si la situación pertenece a la vigilancia de la salud de la app.
    public var isHealth: Bool {
        switch self {
        case .bankExpired, .bankExpiring, .bankStale, .alertsSilent, .alertsNeverArrived, .notificationsOff, .appExpiring:
            true
        default:
            false
        }
    }
}

/// Prioridad de una observación de Nyx (menor valor numérico = más prioritaria).
public enum NyxPriority: Int, Codable, Comparable, Sendable {
    case urgent = 1
    case normal = 2
    case quiet = 3

    public static func < (lhs: NyxPriority, rhs: NyxPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// En cuál de los tres momentos de iOS trabaja Nyx.
public enum NyxMoment: String, Codable, Sendable {
    case notice
    case background
    case open
}

/// Datos con tipo de una observación (también importes en céntimos; protegidos en disco como el libro).
public struct NyxFacts: Codable, Equatable, Sendable {
    public var merchant: String?
    public var bank: BankID?
    public var otherBank: BankID?
    public var movementID: UUID?
    public var cents: Int?
    public var usualCents: Int?
    public var differenceCents: Int?
    public var balanceCents: Int?
    public var suggestedCents: Int?
    public var spentCents: Int?
    public var limitCents: Int?
    public var remainingCents: Int?
    public var percent: Int?
    public var budgetScope: String?
    public var category: SpendingCategory?
    public var day: Date?
    public var days: Int?
    public var track: String?
    public var alertSwitch: NyxAlertSwitch?

    public init(merchant: String? = nil, bank: BankID? = nil, otherBank: BankID? = nil, movementID: UUID? = nil,
                cents: Int? = nil, usualCents: Int? = nil, differenceCents: Int? = nil, balanceCents: Int? = nil,
                suggestedCents: Int? = nil, spentCents: Int? = nil, limitCents: Int? = nil, remainingCents: Int? = nil,
                percent: Int? = nil, budgetScope: String? = nil, category: SpendingCategory? = nil,
                day: Date? = nil, days: Int? = nil, track: String? = nil, alertSwitch: NyxAlertSwitch? = nil) {
        self.merchant = merchant
        self.bank = bank
        self.otherBank = otherBank
        self.movementID = movementID
        self.cents = cents
        self.usualCents = usualCents
        self.differenceCents = differenceCents
        self.balanceCents = balanceCents
        self.suggestedCents = suggestedCents
        self.spentCents = spentCents
        self.limitCents = limitCents
        self.remainingCents = remainingCents
        self.percent = percent
        self.budgetScope = budgetScope
        self.category = category
        self.day = day
        self.days = days
        self.track = track
        self.alertSwitch = alertSwitch
    }

    private enum CodingKeys: String, CodingKey {
        case merchant, bank, otherBank, movementID, cents, usualCents, differenceCents, balanceCents
        case suggestedCents, spentCents, limitCents, remainingCents, percent, budgetScope, category
        case day, days, track, alertSwitch
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        merchant = try? c.decode(String.self, forKey: .merchant)
        bank = try? c.decode(BankID.self, forKey: .bank)
        otherBank = try? c.decode(BankID.self, forKey: .otherBank)
        movementID = try? c.decode(UUID.self, forKey: .movementID)
        cents = try? c.decode(Int.self, forKey: .cents)
        usualCents = try? c.decode(Int.self, forKey: .usualCents)
        differenceCents = try? c.decode(Int.self, forKey: .differenceCents)
        balanceCents = try? c.decode(Int.self, forKey: .balanceCents)
        suggestedCents = try? c.decode(Int.self, forKey: .suggestedCents)
        spentCents = try? c.decode(Int.self, forKey: .spentCents)
        limitCents = try? c.decode(Int.self, forKey: .limitCents)
        remainingCents = try? c.decode(Int.self, forKey: .remainingCents)
        percent = try? c.decode(Int.self, forKey: .percent)
        budgetScope = try? c.decode(String.self, forKey: .budgetScope)
        category = try? c.decode(SpendingCategory.self, forKey: .category)
        day = try? c.decode(Date.self, forKey: .day)
        days = try? c.decode(Int.self, forKey: .days)
        track = try? c.decode(String.self, forKey: .track)
        alertSwitch = try? c.decode(NyxAlertSwitch.self, forKey: .alertSwitch)
    }
}

/// Algo que un vigilante de Nyx ha detectado. Su identificador estable es `situación|sujeto`.
public struct NyxObservation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let situation: NyxSituation
    public let priority: NyxPriority
    public let observedAt: Date
    public let facts: NyxFacts
    public let viaInstantAlert: Bool

    public init(situation: NyxSituation, subject: String, priority: NyxPriority, observedAt: Date,
                facts: NyxFacts, viaInstantAlert: Bool = false) {
        self.id = "\(situation.rawValue)|\(subject)"
        self.situation = situation
        self.priority = priority
        self.observedAt = observedAt
        self.facts = facts
        self.viaInstantAlert = viaInstantAlert
    }

    private enum CodingKeys: String, CodingKey {
        case id, situation, priority, observedAt, facts, viaInstantAlert
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        situation = try c.decode(NyxSituation.self, forKey: .situation)
        priority = try c.decode(NyxPriority.self, forKey: .priority)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
        facts = (try? c.decode(NyxFacts.self, forKey: .facts)) ?? NyxFacts()
        viaInstantAlert = (try? c.decode(Bool.self, forKey: .viaInstantAlert)) ?? false
    }
}

/// Cómo se entregó una observación al dueño.
public enum NyxDelivery: String, Codable, Sendable {
    case notification
    case silentNotification
    case banner
    case list
    case viaAvisos

    /// true si esta entrega cuenta como una interrupción propia de Nyx.
    public var interrupts: Bool {
        switch self {
        case .notification, .silentNotification, .banner: true
        case .list, .viaAvisos: false
        }
    }
}

/// Estado de una entrada en «Lo que he visto».
public enum NyxEntryStatus: String, Codable, Sendable {
    case new
    case seen
    case dismissed
    case done
}

/// Una fila de «Lo que he visto».
public struct NyxEntry: Codable, Equatable, Sendable, Identifiable {
    public let observation: NyxObservation
    public let delivery: NyxDelivery
    public var status: NyxEntryStatus
    public var statusAt: Date
    public var id: String { observation.id }

    public init(observation: NyxObservation, delivery: NyxDelivery, status: NyxEntryStatus = .new, statusAt: Date) {
        self.observation = observation
        self.delivery = delivery
        self.status = status
        self.statusAt = statusAt
    }
}

private struct NyxLossyDecodable<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}

/// Memoria de Nyx en el dispositivo (`nyx-memory.json`). Decodificación tolerante: claves o valores desconocidos se ignoran.
public struct NyxMemory: Codable, Equatable, Sendable {
    public static let maxEntries = 100
    public static let entryRetentionDays = 30
    public static let historyRetentionDays = 60
    private static let interruptionRetentionSeconds: TimeInterval = 48 * 3_600

    /// «Lo que he visto», lo más reciente primero.
    public var entries: [NyxEntry]
    /// Fechas de descartes por situación (`NyxSituation.rawValue`).
    public var dismissals: [String: [Date]]
    /// Fechas de acciones atendidas por situación (`NyxSituation.rawValue`).
    public var actions: [String: [Date]]
    /// Fechas de descartes por comercio (`normalizeMerchant`).
    public var merchantDismissals: [String: [Date]]
    /// Fechas de acciones atendidas por comercio (`normalizeMerchant`).
    public var merchantActions: [String: [Date]]
    /// Instantes en los que Nyx interrumpió por su cuenta (últimas 48 h).
    public var interruptions: [Date]
    /// Última interrupción propia por situación (`NyxSituation.rawValue`).
    public var lastInterruption: [String: Date]
    /// Cuándo propuso silenciar un comercio o apagar un aviso.
    public var suggestedAt: [String: Date]
    public var lastLookAt: Date?
    public var firstUseAt: Date?

    public init() {
        self.entries = []
        self.dismissals = [:]
        self.actions = [:]
        self.merchantDismissals = [:]
        self.merchantActions = [:]
        self.interruptions = []
        self.lastInterruption = [:]
        self.suggestedAt = [:]
        self.lastLookAt = nil
        self.firstUseAt = nil
    }

    public func knows(_ id: String) -> Bool {
        entries.contains { $0.id == id }
    }

    public func entry(_ id: String) -> NyxEntry? {
        entries.first { $0.id == id }
    }

    public var newCount: Int {
        entries.reduce(0) { $0 + ($1.status == .new ? 1 : 0) }
    }

    public mutating func record(_ o: NyxObservation, delivery: NyxDelivery, now: Date) {
        guard !knows(o.id) else { return }
        entries.insert(NyxEntry(observation: o, delivery: delivery, status: .new, statusAt: now), at: 0)
        if delivery.interrupts {
            interruptions.append(now)
            lastInterruption[o.situation.rawValue] = now
        }
    }

    public mutating func mark(_ id: String, _ status: NyxEntryStatus, now: Date) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        entries[index].statusAt = now
        let obs = entries[index].observation
        let situationKey = obs.situation.rawValue
        var merchantKey: String?
        if obs.situation.isMerchantCentric, let merchant = obs.facts.merchant {
            let key = normalizeMerchant(merchant)
            if !key.isEmpty { merchantKey = key }
        }
        switch status {
        case .dismissed:
            dismissals[situationKey, default: []].append(now)
            if let merchantKey { merchantDismissals[merchantKey, default: []].append(now) }
        case .done:
            actions[situationKey, default: []].append(now)
            if let merchantKey { merchantActions[merchantKey, default: []].append(now) }
        case .new, .seen:
            break
        }
    }

    public mutating func markAllSeen(now: Date) {
        for index in entries.indices where entries[index].status == .new {
            entries[index].status = .seen
            entries[index].statusAt = now
        }
    }

    public mutating func prune(now: Date) {
        let entryCutoff = now.addingTimeInterval(-Double(Self.entryRetentionDays) * 86_400)
        let historyCutoff = now.addingTimeInterval(-Double(Self.historyRetentionDays) * 86_400)
        let interruptionCutoff = now.addingTimeInterval(-Self.interruptionRetentionSeconds)

        entries = Array(entries.filter { $0.observation.observedAt >= entryCutoff }.prefix(Self.maxEntries))

        func pruneHistory(_ map: [String: [Date]]) -> [String: [Date]] {
            var out: [String: [Date]] = [:]
            for (key, dates) in map {
                let kept = dates.filter { $0 >= historyCutoff && $0 <= now }
                if !kept.isEmpty { out[key] = kept }
            }
            return out
        }

        dismissals = pruneHistory(dismissals)
        actions = pruneHistory(actions)
        merchantDismissals = pruneHistory(merchantDismissals)
        merchantActions = pruneHistory(merchantActions)
        interruptions = interruptions.filter { $0 >= interruptionCutoff && $0 <= now }
        lastInterruption = lastInterruption.filter { $0.value >= interruptionCutoff && $0.value <= now }
        suggestedAt = suggestedAt.filter { $0.value >= historyCutoff && $0.value <= now }
        if let lastLook = lastLookAt, lastLook > now { lastLookAt = nil }
        if let firstUse = firstUseAt, firstUse > now { firstUseAt = nil }
    }

    private enum CodingKeys: String, CodingKey {
        case entries, dismissals, actions, merchantDismissals, merchantActions
        case interruptions, lastInterruption, suggestedAt, lastLookAt, firstUseAt
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let rawEntries = try? c.decode([NyxLossyDecodable<NyxEntry>].self, forKey: .entries) {
            entries = rawEntries.compactMap(\.value)
        }
        func decodeDateLists(_ key: CodingKeys) -> [String: [Date]] {
            guard let raw = try? c.decode([String: [NyxLossyDecodable<Date>]].self, forKey: key) else { return [:] }
            var out: [String: [Date]] = [:]
            for (k, list) in raw {
                let valid = list.compactMap(\.value)
                if !valid.isEmpty { out[k] = valid }
            }
            return out
        }
        dismissals = decodeDateLists(.dismissals)
        actions = decodeDateLists(.actions)
        merchantDismissals = decodeDateLists(.merchantDismissals)
        merchantActions = decodeDateLists(.merchantActions)
        if let rawInterruptions = try? c.decode([NyxLossyDecodable<Date>].self, forKey: .interruptions) {
            interruptions = rawInterruptions.compactMap(\.value)
        }
        if let rawLast = try? c.decode([String: NyxLossyDecodable<Date>].self, forKey: .lastInterruption) {
            lastInterruption = rawLast.compactMapValues(\.value)
        }
        if let rawSuggested = try? c.decode([String: NyxLossyDecodable<Date>].self, forKey: .suggestedAt) {
            suggestedAt = rawSuggested.compactMapValues(\.value)
        }
        lastLookAt = try? c.decode(Date.self, forKey: .lastLookAt)
        firstUseAt = try? c.decode(Date.self, forKey: .firstUseAt)
    }
}
