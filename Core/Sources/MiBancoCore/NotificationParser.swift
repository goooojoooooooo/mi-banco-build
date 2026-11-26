import Foundation

public enum MovementKind: String, Codable, Sendable { case payment, income }

public struct ParsedMovement: Equatable, Sendable {
    public let kind: MovementKind
    public let amountCents: Int
    public let merchant: String?
    /// Saldo que el propio banco escribe en el aviso; nil si no lo trae.
    public let reportedBalanceCents: Int?
    /// true solo si es un PAGO en una tienda: el comercio va tras " en "/" at " ("Has pagado 12,50 € en Mercadona"),
    /// o es el título de un pago con tarjeta sin destinatario. Falso para ingresos, envíos ("a Laura"), "de Carlos"
    /// y sin comercio. Es la señal positiva que permite buscar su logo en internet.
    public let merchantIsShop: Bool

    public init(kind: MovementKind, amountCents: Int, merchant: String?, reportedBalanceCents: Int? = nil,
                merchantIsShop: Bool = false) {
        self.kind = kind
        self.amountCents = amountCents
        self.merchant = merchant
        self.reportedBalanceCents = reportedBalanceCents
        self.merchantIsShop = merchantIsShop
    }
}

public enum ParseResult: Equatable, Sendable {
    case movement(ParsedMovement)
    /// Sin importe, rechazado, código o aprobación pendiente: no es un movimiento y no se guarda nada.
    case ignore
    /// Hay un importe pero no se sabe si es pago o ingreso, o no está en euros.
    case unreadable
}

private func fold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

/// Palabras enteras que indican que el aviso no es un movimiento hecho (código, 3-D Secure, aprobación, pendiente).
private let ignoredWords: Set<Substring> = [
    "code", "codigo", "confirma", "aprueba", "autoriza", "approve", "confirm", "pendiente", "pending",
]

/// Palabras enteras (ya plegadas) de un envío a otra persona; también vale cualquier palabra que empiece por "transfer".
private let transferWords: Set<Substring> = [
    "enviado", "enviada", "enviaste", "envio", "send", "sent", "bizum", "traspaso",
]

/// Frases de pago explícitas: ganan a cualquier palabra de ingreso ("recibo de" es una factura, no "recibido").
private let explicitPaymentStems = ["has pagado", "has enviado", "recibo de", "cargado", "pago con tarjeta"]
private let incomeStems = [
    "has recibido", "recibido", "recibiste", "received", "te han enviado", "te ha enviado", "bizum de",
    "ingreso", "reembolso", "devoluci", "devuelto", "refund", "abono de",
]
private let genericPaymentStems = ["pagado", "pago en", "paid", "compra", "cargo", "retirada", "retirado", "spent", "payment"]

/// Signo según el texto (ya plegado), o nil si no dice nada.
private func sign(of text: String) -> MovementKind? {
    if explicitPaymentStems.contains(where: { text.contains($0) }) { return .payment }
    if incomeStems.contains(where: { text.contains($0) }) { return .income }
    if genericPaymentStems.contains(where: { text.contains($0) }) { return .payment }
    return nil
}

/// Importe marcado como euros (junto a `€`/`EUR`): para las líneas que también mencionan otra moneda.
private func explicitEuroAmount(in text: String) -> (cents: Int, range: Range<String.Index>)? {
    let n = #"\d+(?:[.,]\d+)*"#
    let sp = "[ \u{00A0}\u{202F}]?"
    let pattern = "(?:€|EUR)" + sp + n + "|" + n + sp + "(?:€|EUR)"
    guard let match = text.firstMatch(of: try! Regex(pattern)),
          let cents = parseAmountToCents(text[match.range]) else { return nil }
    return (cents, match.range)
}

/// shortcut: reglas iguales para los tres bancos (`bank` no se usa aún); separar por banco solo si un aviso real lo exige.
public func parseNotification(bank: BankID, title: String?, subtitle: String?, body: String?) -> ParseResult {
    func split(_ s: String?) -> [String] {
        (s ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    let titleLines = split(title)
    let lines = titleLines + split(subtitle) + split(body)
    let folded = lines.map(fold)

    let everything = folded.joined(separator: "\n")
    // Palabras enteras: "Barcode" no es un código y "confirmado" no es una petición de confirmar.
    let words = everything.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    if ["rechaz", "deneg", "declin"].contains(where: { everything.contains($0) })
        || words.contains(where: { ignoredWords.contains($0) }) { return .ignore }

    var payment: (index: Int, line: String, cents: Int, range: Range<String.Index>)?
    var balance: Int?
    var sawForeignAmount = false
    var signCandidates: [Int] = []
    for (index, (line, f)) in zip(lines, folded).enumerated() {
        if f.contains("gastado hoy") || f.contains("spent today") { continue }
        if ["saldo", "balance", "disponible", "available", "te quedan"].contains(where: { f.hasPrefix($0) }) {
            if balance == nil, !containsForeignAmount(line) { balance = firstAmount(in: line)?.cents }
            continue
        }
        signCandidates.append(index)
        guard payment == nil else { continue }
        if containsForeignAmount(line) {
            // "5,40 € (6,00 USD)" vale; "$5.00" o "5,00 USD" solos no se cuentan como euros.
            if let a = explicitEuroAmount(in: line) { payment = (index, line, a.cents, a.range) } else { sawForeignAmount = true }
        } else if let a = firstAmount(in: line) {
            payment = (index, line, a.cents, a.range)
        }
    }
    guard let pay = payment else { return sawForeignAmount ? .unreadable : .ignore }

    // El signo sale de la línea del importe; si no dice nada, de las demás líneas que no son saldo.
    // El título solo cuenta si es la línea del importe.
    let titleCount = titleLines.count
    let others = signCandidates
        .filter { $0 != pay.index && $0 >= titleCount }
        .map { folded[$0] }
        .joined(separator: "\n")
    guard let kind = sign(of: folded[pay.index]) ?? sign(of: others) else { return .unreadable }

    // Un envío a alguien (en cualquier línea del aviso, sin contar el título) nunca es una compra en tienda.
    let bodyWords = folded[titleCount...].joined(separator: "\n")
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    let isTransfer = bodyWords.contains { word in
        transferWords.contains(word) || word.hasPrefix("transfer")
    }

    var merchant: String?
    var isShop = false
    let after = String(pay.line[pay.range.upperBound...])
    let hit = [" at ", " en ", " a ", " de "]
        .compactMap { word in after.range(of: word, options: .caseInsensitive).map { (word, $0) } }
        .min { $0.1.lowerBound < $1.1.lowerBound }
    if let hit {
        var m = after[hit.1.upperBound...]
        if let stop = m.range(of: ". ") { m = m[..<stop.lowerBound] }
        let name = m.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        merchant = name.isEmpty ? nil : name
        isShop = merchant != nil && kind == .payment && !isTransfer && (hit.0 == " en " || hit.0 == " at ")
    }
    if merchant == nil, let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty, firstAmount(in: t) == nil {
        merchant = t
        // Título de un pago con tarjeta ("Mercadona" + "Has pagado 12,50 €"): tienda solo si el directorio la conoce.
        // Un título puede ser una persona ("Aitziber Zubizarreta"): de un título nunca se adivina una web.
        isShop = kind == .payment && hit == nil && !isTransfer && merchantDomain(for: t, isShop: true) != nil
    }

    return .movement(ParsedMovement(kind: kind, amountCents: pay.cents, merchant: merchant, reportedBalanceCents: balance,
                                    merchantIsShop: isShop))
}
