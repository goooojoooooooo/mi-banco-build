import Foundation

/// Un destinatario guardado. Sensible: vive solo en el llavero (nunca en el libro, copias ni registros).
public struct Payee: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var iban: String?
    public var phone: String?

    public init(id: UUID = UUID(), name: String, iban: String? = nil, phone: String? = nil) {
        self.id = id
        self.name = name
        self.iban = iban
        self.phone = phone
    }
}

/// IBAN propios, saldo mínimo a respetar por banco y destinatarios. Solo para el llavero:
/// no forma parte de `LedgerState` ni de ninguna copia de seguridad.
public struct AccountBook: Codable, Equatable, Sendable {
    public var ibans: [BankID: String]
    /// Céntimos que no se quieren tocar en cada banco.
    public var floors: [BankID: Int]
    public var payees: [Payee]

    public init() {
        ibans = [:]
        floors = [:]
        payees = []
    }

    private enum CodingKeys: String, CodingKey { case ibans, floors, payees }

    /// Tolerante: lo que falte se lee vacío.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ibans = try c.decodeIfPresent([BankID: String].self, forKey: .ibans) ?? [:]
        floors = try c.decodeIfPresent([BankID: Int].self, forKey: .floors) ?? [:]
        payees = try c.decodeIfPresent([Payee].self, forKey: .payees) ?? []
    }
}
