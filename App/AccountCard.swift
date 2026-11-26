import MiBancoCore

/// Las tarjetas del carrusel de Inicio, en orden: «Todo», una por banco y «Cartera» cuando hay inversiones.
/// La tarjeta elegida es también el filtro de la lista de movimientos (o de posiciones en «Cartera»).
enum AccountCard: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all, rev, ima, tr, investments

    /// Las cuatro tarjetas bancarias (sin la de inversiones).
    static let bankCards: [AccountCard] = [.all, .rev, .ima, .tr]

    static func visible(hasInvestments: Bool) -> [AccountCard] {
        hasInvestments ? Self.allCases : bankCards
    }

    var id: String { rawValue }

    init(bank: BankID) {
        switch bank {
        case .rev: self = .rev
        case .ima: self = .ima
        case .tr: self = .tr
        }
    }

    var bank: BankID? {
        switch self {
        case .all, .investments: nil
        case .rev: .rev
        case .ima: .ima
        case .tr: .tr
        }
    }

    /// Texto del control segmentado.
    var segmentTitle: String {
        switch self {
        case .all: "Todo"
        case .investments: "Cartera"
        case .rev, .ima, .tr: bank?.shortName ?? ""
        }
    }

    /// Para VoiceOver ("Todo", "Revolut", "Trade Republic", "Inversiones").
    var spokenName: String {
        switch self {
        case .all: "Todo"
        case .investments: "Inversiones"
        case .rev, .ima, .tr: bank?.displayName ?? ""
        }
    }

    var material: CardMaterial {
        switch self {
        case .all: .all
        case .investments: .investments
        case .rev, .ima, .tr: bank?.material ?? .all
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    func index(in cards: [AccountCard]) -> Int {
        cards.firstIndex(of: self) ?? 0
    }
}
