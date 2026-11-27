import Foundation

/// Lo único que se guarda de una sesión de banco. Sin IBAN.
public struct StoredSession: Codable, Equatable, Sendable {
    public var sessionID: String
    public var accountUIDs: [String]
    public var validUntil: Date
    public var aspspName: String
    public var aspspCountry: String
    /// Nombres de cabeceras PSU requeridas según `GET /aspsps`.
    /// `nil` = pendiente de comprobar (sesión heredada o invalidada); `[]` = comprobado, ninguna requerida.
    public var requiredPSUHeaders: [String]?

    enum CodingKeys: String, CodingKey {
        case sessionID, accountUIDs, validUntil, aspspName, aspspCountry, requiredPSUHeaders
    }

    public init(
        sessionID: String, accountUIDs: [String], validUntil: Date, aspspName: String, aspspCountry: String,
        requiredPSUHeaders: [String]? = nil
    ) {
        self.sessionID = sessionID
        self.accountUIDs = accountUIDs
        self.validUntil = validUntil
        self.aspspName = aspspName
        self.aspspCountry = aspspCountry
        self.requiredPSUHeaders = requiredPSUHeaders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        accountUIDs = try c.decode([String].self, forKey: .accountUIDs)
        validUntil = try c.decode(Date.self, forKey: .validUntil)
        aspspName = try c.decode(String.self, forKey: .aspspName)
        aspspCountry = try c.decode(String.self, forKey: .aspspCountry)
        requiredPSUHeaders = try c.decodeIfPresent([String].self, forKey: .requiredPSUHeaders)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(accountUIDs, forKey: .accountUIDs)
        try c.encode(validUntil, forKey: .validUntil)
        try c.encode(aspspName, forKey: .aspspName)
        try c.encode(aspspCountry, forKey: .aspspCountry)
        try c.encodeIfPresent(requiredPSUHeaders, forKey: .requiredPSUHeaders)
    }
}

/// Conexión a medias: se guarda al salir hacia el banco y caduca a los 15 minutos.
public struct PendingAuth: Codable, Equatable, Sendable {
    public var state: String
    public var bank: BankID
    public var aspspName: String
    public var aspspCountry: String
    public var startedAt: Date
    public var requiredPSUHeaders: [String]?

    enum CodingKeys: String, CodingKey {
        case state, bank, aspspName, aspspCountry, startedAt, requiredPSUHeaders
    }

    public init(
        state: String, bank: BankID, aspspName: String, aspspCountry: String, startedAt: Date,
        requiredPSUHeaders: [String]? = nil
    ) {
        self.state = state
        self.bank = bank
        self.aspspName = aspspName
        self.aspspCountry = aspspCountry
        self.startedAt = startedAt
        self.requiredPSUHeaders = requiredPSUHeaders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        bank = try c.decode(BankID.self, forKey: .bank)
        aspspName = try c.decode(String.self, forKey: .aspspName)
        aspspCountry = try c.decode(String.self, forKey: .aspspCountry)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        requiredPSUHeaders = try c.decodeIfPresent([String].self, forKey: .requiredPSUHeaders)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state, forKey: .state)
        try c.encode(bank, forKey: .bank)
        try c.encode(aspspName, forKey: .aspspName)
        try c.encode(aspspCountry, forKey: .aspspCountry)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(requiredPSUHeaders, forKey: .requiredPSUHeaders)
    }

    public func isExpired(now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= 15 * 60
    }
}

/// Sin id de sesión ni cuentas.
extension StoredSession: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "StoredSession(\(aspspName), \(aspspCountry), redacted)" }
    public var debugDescription: String { description }
}

/// Sin `state`.
extension PendingAuth: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "PendingAuth(\(bank), \(aspspName), \(aspspCountry), redacted)" }
    public var debugDescription: String { description }
}
