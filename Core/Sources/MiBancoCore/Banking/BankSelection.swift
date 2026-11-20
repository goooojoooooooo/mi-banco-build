import Foundation

/// Texto que debe contener el nombre del banco en la lista de Enable Banking.
public func aspspSearchKey(for bank: BankID) -> String {
    switch bank {
    case .rev: "revolut"
    case .ima: "imagin"
    case .tr: "trade republic"
    }
}

private func folded(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

/// Busca el banco por nombre normalizado (subcadena); prefiere el país ES y, si no hay, cualquiera.
public func matchASPSP(for bank: BankID, in list: [EBASPSP]) -> EBASPSP? {
    let key = aspspSearchKey(for: bank)
    let matches = list.filter { folded($0.name).contains(key) }
    return matches.first { $0.country.uppercased() == BankingConstants.country } ?? matches.first
}

/// Consentimiento: lo que permite el banco (90 días si no lo dice o si da 0 o menos), máximo 180 días, menos 1 hora de margen.
/// Nunca queda en el pasado: al menos 1 día desde `now`, y nunca más de lo que el banco permite
/// (si el banco permite menos de un día, manda el banco, con 1 s como mínimo).
public func consentValidUntil(for aspsp: EBASPSP, now: Date) -> Date {
    let day: TimeInterval = 86_400
    // 0 o negativo no es un plazo real: se trata como desconocido.
    let stated = aspsp.maximumConsentValidity.flatMap { $0 > 0 ? $0 : nil }
    let allowed = min(TimeInterval(stated ?? Int(90 * day)), 180 * day)
    let seconds = min(max(allowed - 3600, day), max(allowed, 1))
    return now.addingTimeInterval(seconds)
}

/// Solo cuentas corrientes en euros (tipo CACC o sin tipo).
public func selectAccounts(_ accounts: [EBAccount]) -> [EBAccount] {
    accounts.filter {
        ($0.currency ?? "").uppercased() == "EUR" && ($0.cashAccountType == nil || $0.cashAccountType == "CACC")
    }
}

/// Saldo en céntimos entre los de euros, por orden de preferencia.
public func pickBalanceCents(_ balances: [EBBalance]) -> Int? {
    let order = ["ITAV", "CLAV", "XPCD", "OPAV", "ITBD", "CLBD"]
    let euros = balances.compactMap { b -> (rank: Int, cents: Int)? in
        guard let cents = b.balanceAmount.euroCents else { return nil }
        return (order.firstIndex(of: b.balanceType) ?? order.count, cents)
    }
    guard let best = euros.map(\.rank).min() else { return nil }
    return euros.first { $0.rank == best }?.cents
}
