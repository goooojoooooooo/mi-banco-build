/// `estimated`: el saldo sale de sumar movimientos a un saldo puesto a mano (o ya no es el que dio el banco);
/// entonces el cuerpo dice "unos" para no presentarlo como exacto.
public func alertText(for m: Movement, balance: Int?, estimated: Bool) -> (title: String, body: String) {
    let amount = formatEUR(abs(m.amountCents))
    var title: String
    switch m.kind {
    case .payment:
        title = "Has pagado \(amount)"
        if let merchant = m.merchant { title += " en \(merchant)" }
    case .income:
        title = "Has recibido \(amount)"
        if let merchant = m.merchant { title += ": \(merchant)" }
    }
    let name = m.bank.displayName
    let body = balance.map { "Te quedan \(estimated ? "unos " : "")\(formatEUR($0)) en \(name)" } ?? "Saldo de \(name) sin configurar"
    return (title, body)
}
