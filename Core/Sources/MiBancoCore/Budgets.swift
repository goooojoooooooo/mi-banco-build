import Foundation

/// Presupuestos mensuales: uno para todo el mes y, si se quiere, uno por categoría. Importes en céntimos.
public struct Budgets: Codable, Equatable, Sendable {
    public var monthlyCents: Int?
    public var byCategory: [SpendingCategory: Int]

    public init(monthlyCents: Int? = nil, byCategory: [SpendingCategory: Int] = [:]) {
        self.monthlyCents = monthlyCents
        self.byCategory = byCategory
    }

    private enum CodingKeys: String, CodingKey { case monthlyCents, byCategory }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthlyCents = try c.decodeIfPresent(Int.self, forKey: .monthlyCents)
        byCategory = try c.decodeIfPresent([SpendingCategory: Int].self, forKey: .byCategory) ?? [:]
    }
}

public enum BudgetScope: Hashable, Sendable {
    case month
    case category(SpendingCategory)
}

public enum BudgetLevel: String, Sendable {
    case ok, warning, exceeded
}

public struct BudgetStatus: Equatable, Sendable, Identifiable {
    public let scope: BudgetScope
    public let limitCents: Int
    public let spentCents: Int

    public init(scope: BudgetScope, limitCents: Int, spentCents: Int) {
        self.scope = scope
        self.limitCents = limitCents
        self.spentCents = spentCents
    }

    /// Gastado sobre el límite, en porcentaje entero hacia abajo.
    public var percent: Int { limitCents > 0 ? spentCents * 100 / limitCents : 0 }
    /// 100 % o más: superado; 80 % o más: aviso.
    public var level: BudgetLevel { percent >= 100 ? .exceeded : (percent >= 80 ? .warning : .ok) }
    public var remainingCents: Int { max(0, limitCents - spentCents) }

    public var id: String {
        switch scope {
        case .month: "month"
        case .category(let c): "cat-\(c.rawValue)"
        }
    }
}

/// Estado de cada presupuesto en `month`: primero el del mes, luego las categorías en el orden de `allCases`.
/// Quien lo llama varias veces calcula `ownTransferIDs(in:)` y `subscriptionKeys(...)` una vez y los pasa.
public func budgetStatuses(in state: LedgerState, month: Date, now: Date, calendar: Calendar,
                           ownTransferIDs ownTransfers: Set<UUID>? = nil,
                           subscriptionKeys keys: Set<String>? = nil) -> [BudgetStatus] {
    let budgets = state.budgets
    let monthLimit = budgets.monthlyCents.flatMap { $0 > 0 ? $0 : nil }
    let categoryLimits = SpendingCategory.allCases.compactMap { c in
        budgets.byCategory[c].flatMap { $0 > 0 ? (c, $0) : nil }
    }
    if monthLimit == nil && categoryLimits.isEmpty { return [] }
    let spending = monthSpending(in: state, month: month, now: now, calendar: calendar,
                                 ownTransferIDs: ownTransfers, subscriptionKeys: keys)
    var out: [BudgetStatus] = []
    if let monthLimit {
        out.append(BudgetStatus(scope: .month, limitCents: monthLimit, spentCents: spending.totalCents))
    }
    for (category, limit) in categoryLimits {
        let spent = spending.byCategory.first { $0.category == category }?.cents ?? 0
        out.append(BudgetStatus(scope: .category(category), limitCents: limit, spentCents: spent))
    }
    return out
}
