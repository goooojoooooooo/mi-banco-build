/// Qué avisos quiere el usuario. Los libros antiguos no traen alguna clave: cada una cae a su valor por defecto.
public struct AlertSettings: Codable, Equatable, Sendable {
    public var everyMovement: Bool
    public var lowBalance: Bool
    public var lowBalanceThresholdCents: Int
    public var largePayment: Bool
    public var largePaymentThresholdCents: Int
    public var income: Bool
    public var subscriptions: Bool
    public var duplicateCharge: Bool
    public var weeklyDigest: Bool
    public var spendingPace: Bool
    /// Avisos al llegar al 80 % y al 100 % de un presupuesto.
    public var budgets: Bool
    /// Aviso diario por la mañana para abrir el resumen (sin cifras).
    public var morningBriefing: Bool
    /// Minutos desde medianoche para el aviso de la mañana (por defecto 510 = 08:30; válido 0..<1440).
    public var morningBriefingMinutes: Int {
        didSet {
            if !(0..<1_440).contains(morningBriefingMinutes) {
                morningBriefingMinutes = defaultMorningBriefingMinutes
            }
        }
    }

    public init(everyMovement: Bool = true, lowBalance: Bool = true, lowBalanceThresholdCents: Int = 10_000,
                largePayment: Bool = true, largePaymentThresholdCents: Int = 15_000, income: Bool = true,
                subscriptions: Bool = true, duplicateCharge: Bool = true, weeklyDigest: Bool = true,
                spendingPace: Bool = true, budgets: Bool = true,
                morningBriefing: Bool = true, morningBriefingMinutes: Int = defaultMorningBriefingMinutes) {
        self.everyMovement = everyMovement
        self.lowBalance = lowBalance
        self.lowBalanceThresholdCents = lowBalanceThresholdCents
        self.largePayment = largePayment
        self.largePaymentThresholdCents = largePaymentThresholdCents
        self.income = income
        self.subscriptions = subscriptions
        self.duplicateCharge = duplicateCharge
        self.weeklyDigest = weeklyDigest
        self.spendingPace = spendingPace
        self.budgets = budgets
        self.morningBriefing = morningBriefing
        self.morningBriefingMinutes = (0..<1_440).contains(morningBriefingMinutes)
            ? morningBriefingMinutes : defaultMorningBriefingMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case everyMovement, lowBalance, lowBalanceThresholdCents, largePayment, largePaymentThresholdCents
        case income, subscriptions, duplicateCharge, weeklyDigest, spendingPace, budgets
        case morningBriefing, morningBriefingMinutes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSettings()
        everyMovement = try c.decodeIfPresent(Bool.self, forKey: .everyMovement) ?? d.everyMovement
        lowBalance = try c.decodeIfPresent(Bool.self, forKey: .lowBalance) ?? d.lowBalance
        lowBalanceThresholdCents = try c.decodeIfPresent(Int.self, forKey: .lowBalanceThresholdCents) ?? d.lowBalanceThresholdCents
        largePayment = try c.decodeIfPresent(Bool.self, forKey: .largePayment) ?? d.largePayment
        largePaymentThresholdCents = try c.decodeIfPresent(Int.self, forKey: .largePaymentThresholdCents) ?? d.largePaymentThresholdCents
        income = try c.decodeIfPresent(Bool.self, forKey: .income) ?? d.income
        subscriptions = try c.decodeIfPresent(Bool.self, forKey: .subscriptions) ?? d.subscriptions
        duplicateCharge = try c.decodeIfPresent(Bool.self, forKey: .duplicateCharge) ?? d.duplicateCharge
        weeklyDigest = try c.decodeIfPresent(Bool.self, forKey: .weeklyDigest) ?? d.weeklyDigest
        spendingPace = try c.decodeIfPresent(Bool.self, forKey: .spendingPace) ?? d.spendingPace
        budgets = try c.decodeIfPresent(Bool.self, forKey: .budgets) ?? d.budgets
        morningBriefing = (try? c.decodeIfPresent(Bool.self, forKey: .morningBriefing)) ?? d.morningBriefing
        let rawMinutes = (try? c.decodeIfPresent(Int.self, forKey: .morningBriefingMinutes)) ?? d.morningBriefingMinutes
        morningBriefingMinutes = (0..<1_440).contains(rawMinutes) ? rawMinutes : d.morningBriefingMinutes
    }
}
