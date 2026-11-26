import Foundation

/// Decimal de la API ("12.50", "-1234.56", "12.500") -> céntimos.
/// Solo punto decimal; más de 2 decimales solo si lo sobrante son ceros.
public func centsFromDecimalString(_ raw: String) -> Int? {
    var chars = Array(raw.utf8)
    var negative = false
    if let first = chars.first, first == UInt8(ascii: "-") || first == UInt8(ascii: "+") {
        negative = first == UInt8(ascii: "-")
        chars.removeFirst()
    }
    guard !chars.isEmpty else { return nil }
    let dot = UInt8(ascii: ".")
    let parts = chars.split(separator: dot, omittingEmptySubsequences: false)
    guard parts.count <= 2 else { return nil }
    let intPart = parts[0]
    let fracPart = parts.count == 2 ? parts[1] : []
    func allDigits(_ s: ArraySlice<UInt8>) -> Bool { s.allSatisfy { $0 >= 48 && $0 <= 57 } }
    guard !intPart.isEmpty, intPart.count <= 15, allDigits(intPart), allDigits(fracPart) else { return nil }
    if parts.count == 2 && fracPart.isEmpty { return nil }
    var frac = Array(fracPart)
    if frac.count > 2 {
        guard frac[2...].allSatisfy({ $0 == 48 }) else { return nil }
        frac = Array(frac[0..<2])
    }
    while frac.count < 2 { frac.append(48) }
    var euros = 0
    for d in intPart { euros = euros * 10 + Int(d - 48) }
    let cents = euros * 100 + Int(frac[0] - 48) * 10 + Int(frac[1] - 48)
    return negative ? -cents : cents
}

public struct EBAmount: Codable, Equatable, Sendable {
    public let currency: String
    public let amount: String
    public init(currency: String, amount: String) {
        self.currency = currency
        self.amount = amount
    }

    /// Céntimos solo si la divisa es EUR; con cualquier otra no se interpreta el número como euros.
    public var euroCents: Int? {
        guard currency.uppercased() == "EUR" else { return nil }
        return centsFromDecimalString(amount)
    }
}

public enum EBTransactionStatus: String, Codable, Sendable {
    case book = "BOOK", pdng = "PDNG", hold = "HOLD", cncl = "CNCL", rjct = "RJCT", schd = "SCHD", othr = "OTHR"

    /// Un estado desconocido no rompe la descarga: cuenta como `.othr`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EBTransactionStatus(rawValue: raw) ?? .othr
    }
}

public struct EBParty: Codable, Equatable, Sendable {
    public let name: String?
    public init(name: String?) { self.name = name }
}

/// Tipo de operación del banco (`bank_transaction_code`, ISO 20022): familia (`code`, p. ej. «ICDT», transferencia
/// emitida) y subfamilia (`sub_code`), con su descripción. Todo opcional: muchos bancos no lo mandan.
public struct EBBankTransactionCode: Codable, Equatable, Sendable {
    public let description: String?
    public let code: String?
    public let subCode: String?

    enum CodingKeys: String, CodingKey {
        case description, code
        case subCode = "sub_code"
    }

    public init(description: String?, code: String?, subCode: String?) {
        self.description = description
        self.code = code
        self.subCode = subCode
    }
}

public struct EBTransaction: Codable, Equatable, Sendable {
    public let entryReference: String?
    public let transactionID: String?
    public let transactionAmount: EBAmount
    public let creditDebitIndicator: String
    public let status: EBTransactionStatus
    public let bookingDate: String?
    public let valueDate: String?
    public let transactionDate: String?
    public let remittanceInformation: [String]?
    public let creditor: EBParty?
    public let debtor: EBParty?
    public let merchantCategoryCode: String?
    public let balanceAfterTransaction: EBAmount?
    public let bankTransactionCode: EBBankTransactionCode?

    enum CodingKeys: String, CodingKey {
        case entryReference = "entry_reference"
        case transactionID = "transaction_id"
        case transactionAmount = "transaction_amount"
        case creditDebitIndicator = "credit_debit_indicator"
        case status
        case bookingDate = "booking_date"
        case valueDate = "value_date"
        case transactionDate = "transaction_date"
        case remittanceInformation = "remittance_information"
        case creditor, debtor
        case merchantCategoryCode = "merchant_category_code"
        case balanceAfterTransaction = "balance_after_transaction"
        case bankTransactionCode = "bank_transaction_code"
    }

    public init(
        transactionAmount: EBAmount, creditDebitIndicator: String, status: EBTransactionStatus,
        entryReference: String? = nil, transactionID: String? = nil, bookingDate: String? = nil,
        valueDate: String? = nil, transactionDate: String? = nil, remittanceInformation: [String]? = nil,
        creditor: EBParty? = nil, debtor: EBParty? = nil, merchantCategoryCode: String? = nil,
        balanceAfterTransaction: EBAmount? = nil, bankTransactionCode: EBBankTransactionCode? = nil
    ) {
        self.entryReference = entryReference
        self.transactionID = transactionID
        self.transactionAmount = transactionAmount
        self.creditDebitIndicator = creditDebitIndicator
        self.status = status
        self.bookingDate = bookingDate
        self.valueDate = valueDate
        self.transactionDate = transactionDate
        self.remittanceInformation = remittanceInformation
        self.creditor = creditor
        self.debtor = debtor
        self.merchantCategoryCode = merchantCategoryCode
        self.balanceAfterTransaction = balanceAfterTransaction
        self.bankTransactionCode = bankTransactionCode
    }

    /// DBIT negativo, CRDT positivo, siempre sobre el valor absoluto del importe.
    /// Solo importes en euros: otra divisa da `nil` y nunca se casa ni se cuenta.
    public var signedCents: Int? {
        guard let cents = transactionAmount.euroCents else { return nil }
        switch creditDebitIndicator {
        case "DBIT": return -abs(cents)
        case "CRDT": return abs(cents)
        default: return nil
        }
    }
}

public struct EBBalance: Codable, Equatable, Sendable {
    public let name: String?
    public let balanceAmount: EBAmount
    public let balanceType: String
    public let lastChangeDateTime: String?
    /// Día de referencia del saldo (`yyyy-MM-dd`), p. ej. el cierre contabilizado de un día.
    public let referenceDate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case balanceAmount = "balance_amount"
        case balanceType = "balance_type"
        case lastChangeDateTime = "last_change_date_time"
        case referenceDate = "reference_date"
    }

    public init(name: String? = nil, balanceAmount: EBAmount, balanceType: String, lastChangeDateTime: String? = nil,
                referenceDate: String? = nil) {
        self.name = name
        self.balanceAmount = balanceAmount
        self.balanceType = balanceType
        self.lastChangeDateTime = lastChangeDateTime
        self.referenceDate = referenceDate
    }
}

/// Sin IBAN a propósito: `account_id` no se decodifica nunca.
public struct EBAccount: Codable, Equatable, Sendable {
    public let uid: String
    public let currency: String?
    public let cashAccountType: String?
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case uid, currency, name
        case cashAccountType = "cash_account_type"
    }

    public init(uid: String, currency: String? = nil, cashAccountType: String? = nil, name: String? = nil) {
        self.uid = uid
        self.currency = currency
        self.cashAccountType = cashAccountType
        self.name = name
    }
}

public struct EBSession: Decodable, Equatable, Sendable {
    public let sessionID: String
    public let accounts: [EBAccount]
    public let validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case accounts, access
    }
    enum AccessKeys: String, CodingKey { case validUntil = "valid_until" }

    public init(sessionID: String, accounts: [EBAccount], validUntil: Date?) {
        self.sessionID = sessionID
        self.accounts = accounts
        self.validUntil = validUntil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        accounts = try c.decodeIfPresent([EBAccount].self, forKey: .accounts) ?? []
        if let access = try? c.nestedContainer(keyedBy: AccessKeys.self, forKey: .access),
           let text = try access.decodeIfPresent(String.self, forKey: .validUntil) {
            validUntil = parseEnableBankingDate(text)
        } else {
            validUntil = nil
        }
    }
}

public struct EBASPSP: Codable, Equatable, Sendable {
    public let name: String
    public let country: String
    public let maximumConsentValidity: Int?
    public let requiredPSUHeaders: [String]?

    enum CodingKeys: String, CodingKey {
        case name, country
        case maximumConsentValidity = "maximum_consent_validity"
        case requiredPSUHeaders = "required_psu_headers"
    }

    public init(name: String, country: String, maximumConsentValidity: Int? = nil, requiredPSUHeaders: [String]? = nil) {
        self.name = name
        self.country = country
        self.maximumConsentValidity = maximumConsentValidity
        self.requiredPSUHeaders = requiredPSUHeaders
    }
}

/// ISO 8601 con o sin fracción de segundo ("...:00.000000+00:00", "...:00Z").
/// La fracción se descarta a mano: no todas las plataformas aceptan 6 dígitos.
func parseEnableBankingDate(_ text: String) -> Date? {
    var s = text
    var fraction: Double = 0
    if let dot = s.firstIndex(of: ".") {
        var end = s.index(after: dot)
        while end < s.endIndex, s[end].isASCII, s[end].isNumber { end = s.index(after: end) }
        fraction = Double("0" + String(s[dot..<end])) ?? 0
        s.removeSubrange(dot..<end)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: s) else { return nil }
    return date.addingTimeInterval(fraction)
}
