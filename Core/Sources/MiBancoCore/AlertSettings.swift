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

    public init(everyMovement: Bool = true, lowBalance: Bool = true, lowBalanceThresholdCents: Int = 10_000,
                largePayment: Bool = true, largePaymentThresholdCents: Int = 15_000, income: Bool = true,
                subscriptions: Bool = true, duplicateCharge: Bool = true, weeklyDigest: Bool = true,
                spendingPace: Bool = true, budgets: Bool = true) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case everyMovement, lowBalance, lowBalanceThresholdCents, largePayment, largePaymentThresholdCents
        case income, subscriptions, duplicateCharge, weeklyDigest, spendingPace, budgets
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
    }
}
