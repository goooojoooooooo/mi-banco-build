import Foundation

/// Cuándo ocurrió un registro del banco. Los días van al mediodía de Madrid (no hay hora real).
public enum RecordTiming: Equatable, Sendable {
    case exact(Date)
    /// El día en que se hizo el pago (`transaction_date`).
    case transactionDay(Date)
    /// El día en que el banco lo apuntó (`booking_date` / `value_date`): puede ser varios días después del pago.
    case bookingDay(Date)

    public var date: Date {
        switch self {
        case let .exact(d), let .transactionDay(d), let .bookingDay(d): d
        }
    }

    public var isExact: Bool {
        if case .exact = self { return true }
        return false
    }
}

/// Un movimiento del banco ya traducido a lo que usa el libro. Solo euros.
public struct BankRecord: Equatable, Sendable {
    public var ref: String
    public var bank: BankID
    public var amountCents: Int
    public var timing: RecordTiming
    public var status: BankStatus
    public var merchant: String?
    public var isShop: Bool
    /// Saldo tras el movimiento, si el banco lo da (nadie lo consume todavía).
    public var balanceAfterCents: Int?
    /// true = operación de inversión (compra o venta de valores): mueve el saldo pero no es gasto.
    public var excludedFromSpending: Bool
    /// Claves con las que una versión anterior de la app guardó esta misma fila (solo los extractos). Un movimiento del
    /// libro que lleve una de ellas es esta fila: se reconoce y pasa a la clave nueva en lugar de duplicarse.
    public var legacyRefs: [String]
    /// Día en que el banco lo apuntó (`booking_date`, a mediodía), solo en los apuntados. `timing` prefiere el día del pago.
    public var bookedDay: Date?
    /// true = el banco o el extracto dicen que es un pago a una persona (código de comercio de transferencia, tipo
    /// «Transfer» de Revolut). Pasa a `Movement.personPayment`.
    public var personPayment: Bool
    /// true = `isShop` sale solo de que el nombre se parece a una marca del directorio (sin código de comercio). No se
    /// guarda: al enlazar, no le quita la señal de persona a un aviso de Bizum («Zara López» no es Zara).
    public var shopFromName: Bool
    /// Código MCC ISO 18245 (4 dígitos limpios) si el banco o el extracto lo trajo. Pasa a `Movement.merchantCategoryCode`.
    public var merchantCategoryCode: String?

    public init(ref: String, bank: BankID, amountCents: Int, timing: RecordTiming, status: BankStatus,
                merchant: String? = nil, isShop: Bool = false, balanceAfterCents: Int? = nil,
                excludedFromSpending: Bool = false, legacyRefs: [String] = [], bookedDay: Date? = nil,
                personPayment: Bool = false, shopFromName: Bool = false, merchantCategoryCode: String? = nil) {
        self.ref = ref
        self.bank = bank
        self.amountCents = amountCents
        self.timing = timing
        self.status = status
        self.merchant = merchant
        self.isShop = isShop
        self.balanceAfterCents = balanceAfterCents
        self.excludedFromSpending = excludedFromSpending
        self.legacyRefs = legacyRefs
        self.bookedDay = bookedDay
        self.personPayment = personPayment
        self.shopFromName = shopFromName
        self.merchantCategoryCode = merchantCategoryCode
    }
}

/// De dónde vienen los registros: la API del banco o un extracto importado.
public enum RecordChannel: Sendable { case bank, statement }

let nonShopMCC: Set<String> = ["4829", "6010", "6011", "6012", "6051", "6540"]
/// Códigos de comercio de un envío de dinero (4829: transferencia; 6540: envío o recarga de dinero): señal de pago a persona.
let transferMCC: Set<String> = ["4829", "6540"]

/// true si el tipo de operación es una transferencia emitida (familia ISO 20022 «ICDT») o su descripción lo dice.
func isTransferCode(_ code: EBBankTransactionCode) -> Bool {
    code.code?.uppercased() == "ICDT" || saysPersonPayment(code.description)
}

/// "2026-11-18" (o "2026-11-18T10:00:00...") -> ese día al mediodía en `calendar`; nil si no es una fecha válida.
func noonOfDay(_ text: String, calendar: Calendar) -> (day: String, date: Date)? {
    let day = String(text.prefix(10))
    let parts = day.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = 12
    guard let date = calendar.date(from: c) else { return nil }
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == y, back.month == mo, back.day == d else { return nil }
    return (day, date)
}

func fnv1aHex(_ s: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
}

/// Registros del libro a partir de la respuesta de la API. Se descartan CNCL, RJCT y SCHD, lo que no está en euros
/// (o no tiene importe legible) y lo que no trae ninguna fecha.
public func bankRecords(from transactions: [EBTransaction], bank: BankID, calendar: Calendar) -> [BankRecord] {
    var out: [BankRecord] = []
    var occurrences: [String: Int] = [:]
    for t in transactions {
        let status: BankStatus
        switch t.status {
        case .book, .othr: status = .booked
        case .pdng, .hold: status = .pending
        case .cncl, .rjct, .schd: continue
        }
        guard let cents = t.signedCents else { continue }

        var timing: RecordTiming?
        var dayText = ""
        if let text = t.transactionDate, let day = noonOfDay(text, calendar: calendar) {
            timing = .transactionDay(day.date); dayText = day.day
        } else if let text = t.bookingDate, let day = noonOfDay(text, calendar: calendar) {
            timing = .bookingDay(day.date); dayText = day.day
        } else if let text = t.valueDate, let day = noonOfDay(text, calendar: calendar) {
            timing = .bookingDay(day.date); dayText = day.day
        }
        guard let timing else { continue }

        let isDebit = t.creditDebitIndicator == "DBIT"
        let remittance = (t.remittanceInformation ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let party = (isDebit ? t.creditor?.name : t.debtor?.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = (party?.isEmpty == false ? party : nil) ?? remittance.first { !$0.isEmpty }
        let cleaned = raw.map(cleanBankMerchant)
        let merchant = (cleaned?.isEmpty == false) ? cleaned : nil

        // El concepto («BIZUM ENVIADO», «TRANSFERENCIA A FAVOR DE…») y el tipo de operación también dicen si es un envío,
        // aunque el comercio guardado sea el acreedor (el concepto no se guarda).
        let saysTransfer = remittance.contains { saysPersonPayment($0) } || t.bankTransactionCode.map(isTransferCode) == true
        let mcc = cleanMCC(t.merchantCategoryCode)
        let isShop: Bool
        var shopFromName = false
        if !isDebit {
            isShop = false
        } else if let mcc {
            isShop = !nonShopMCC.contains(mcc)
        } else {
            // Sin código: el parecido con una marca no tapa un envío («Bizum» a «Zara López»).
            isShop = !saysTransfer && (merchant.map { merchantDomain(for: $0) != nil } ?? false)
            shopFromName = isShop
        }

        let personPayment = isDebit && !isShop && (mcc.map { transferMCC.contains($0) } == true || saysTransfer)
            && !mentionsOwnAccount(merchant)

        var ref = (t.entryReference?.isEmpty == false ? t.entryReference : nil)
            ?? (t.transactionID?.isEmpty == false ? t.transactionID : nil)
        if ref == nil {
            let key = [bank.rawValue, status.rawValue, dayText, String(cents), remittance.joined(separator: "\u{1F}")]
                .joined(separator: "|")
            let n = occurrences[key, default: 0]
            occurrences[key] = n + 1
            ref = "s|" + fnv1aHex(key) + "|" + String(n)
        }
        out.append(BankRecord(
            ref: ref ?? "", bank: bank, amountCents: cents, timing: timing, status: status, merchant: merchant,
            isShop: isShop, balanceAfterCents: t.balanceAfterTransaction?.euroCents,
            bookedDay: status == .booked ? t.bookingDate.flatMap { noonOfDay($0, calendar: calendar)?.date } : nil,
            personPayment: personPayment, shopFromName: shopFromName, merchantCategoryCode: mcc))
    }
    return out
}
