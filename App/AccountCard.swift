import MiBancoCore

/// Las cuatro tarjetas del carrusel de Inicio, en orden: «Todo» y una por banco.
/// La tarjeta elegida es también el filtro de la lista de movimientos.
enum AccountCard: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all, rev, ima, tr

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
        case .all: nil
        case .rev: .rev
        case .ima: .ima
        case .tr: .tr
        }
    }

    /// Texto del control segmentado.
    var segmentTitle: String {
        bank?.shortName ?? "Todo"
    }

    /// Para VoiceOver ("Todo", "Revolut", "Trade Republic").
    var spokenName: String {
        bank?.displayName ?? "Todo"
    }

    var material: CardMaterial {
        bank?.material ?? .all
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
