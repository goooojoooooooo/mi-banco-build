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

/// Consentimiento: lo que permite el banco (90 días si no lo dice), máximo 180 días, menos 1 hora de margen.
public func consentValidUntil(for aspsp: EBASPSP, now: Date) -> Date {
    let day: TimeInterval = 86_400
    let seconds = min(TimeInterval(aspsp.maximumConsentValidity ?? Int(90 * day)), 180 * day)
    return now.addingTimeInterval(seconds - 3600)
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
        guard b.balanceAmount.currency.uppercased() == "EUR",
              let cents = centsFromDecimalString(b.balanceAmount.amount) else { return nil }
        return (order.firstIndex(of: b.balanceType) ?? order.count, cents)
    }
    guard let best = euros.map(\.rank).min() else { return nil }
    return euros.first { $0.rank == best }?.cents
}
