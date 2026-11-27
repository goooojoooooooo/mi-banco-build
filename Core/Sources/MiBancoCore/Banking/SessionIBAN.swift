import Foundation

/// Cuenta devuelta por Enable Banking en `POST /sessions` usada ÚNICAMENTE en el momento de conectar o renovar
/// para leer el IBAN propio de la cuenta principal en euros y pasarlo directo a `AccountBookStore`.
/// No conforma a `Encodable` para que nunca se serialice en `StoredSession`, `ledger.json` ni copias,
/// y oculta el IBAN en cualquier descripción.
public struct EBSessionAccountIBAN: Decodable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let uid: String
    public let currency: String?
    public let cashAccountType: String?
    let rawIBAN: String?

    public var description: String { "EBSessionAccountIBAN(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection()) }

    init(uid: String, currency: String? = nil, cashAccountType: String? = nil, rawIBAN: String? = nil) {
        self.uid = uid
        self.currency = currency
        self.cashAccountType = cashAccountType
        self.rawIBAN = rawIBAN
    }

    private enum CodingKeys: String, CodingKey {
        case uid, currency
        case cashAccountType = "cash_account_type"
        case accountID = "account_id"
        case allAccountIDs = "all_account_ids"
    }

    private struct GenericIdentification: Decodable {
        let identification: String?
        let schemeName: String?

        enum CodingKeys: String, CodingKey {
            case identification
            case schemeName = "scheme_name"
        }
    }

    private struct AccountIdentification: Decodable {
        let iban: String?
        let other: GenericIdentification?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(String.self, forKey: .uid)
        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        cashAccountType = try? c.decodeIfPresent(String.self, forKey: .cashAccountType)

        let accountID = (try? c.decodeIfPresent(AccountIdentification.self, forKey: .accountID)) ?? nil
        if let primary = accountID?.iban?.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            rawIBAN = primary
            return
        }

        var candidates: [String] = []
        if let other = accountID?.other,
           other.schemeName?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "IBAN",
           let id = other.identification?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            candidates.append(id)
        }
        if let allIDs = (try? c.decodeIfPresent([GenericIdentification].self, forKey: .allAccountIDs)) ?? nil {
            for item in allIDs {
                if item.schemeName?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "IBAN",
                   let id = item.identification?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !id.isEmpty {
                    candidates.append(id)
                }
            }
        }
        let distinct = Set(candidates.map { validatedBankIBAN($0) ?? $0.uppercased() })
        rawIBAN = distinct.count == 1 ? candidates.first : nil
    }
}

/// Resultado de `POST /sessions` solo para el flujo de conexión (`BankConnector.finish`):
/// mantiene `EBSession` y `EBAccount` libres de IBAN y entrega aparte el IBAN validado, si es inequívoco.
public struct EBSessionAuthorization: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let session: EBSession
    public let primaryEuroIBAN: String?

    public var description: String { "EBSessionAuthorization(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: EmptyCollection()) }

    public init(session: EBSession, primaryEuroIBAN: String?) {
        self.session = session
        self.primaryEuroIBAN = primaryEuroIBAN
    }
}

/// Elige el IBAN de la cuenta corriente principal en euros (mismo filtro que `selectAccounts`: EUR y CACC o sin tipo).
/// Si hay varias cuentas corrientes en euros con IBAN distintos (o a alguna le falta), no adivina y devuelve `nil`.
public func selectPrimaryEuroIBAN(from accounts: [EBSessionAccountIBAN]) -> String? {
    let eligible = accounts.filter { account in
        (account.currency ?? "").uppercased() == "EUR"
            && (account.cashAccountType == nil || account.cashAccountType?.uppercased() == "CACC")
    }
    guard !eligible.isEmpty else { return nil }
    var resolved: Set<String> = []
    for account in eligible {
        guard let raw = account.rawIBAN, let valid = validatedBankIBAN(raw) else {
            return nil
        }
        resolved.insert(valid)
    }
    return resolved.count == 1 ? resolved.first : nil
}

/// Lee de forma tolerante el IBAN principal en euros de la respuesta JSON cruda de `POST /sessions`.
/// Un dato raro o inválido nunca rompe la conexión: devuelve `nil` sin ruido.
public func extractPrimaryEuroIBAN(fromSessionData data: Data) -> String? {
    struct Envelope: Decodable {
        let accounts: [EBSessionAccountIBAN]?
    }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
        return nil
    }
    return selectPrimaryEuroIBAN(from: envelope.accounts ?? [])
}
