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
    /// Cuándo el banco rechazó con 422 las cabeceras PSU aunque `GET /aspsps` parecía cumplirse. `nil` = nunca.
    /// Caduca a los 7 días (`SyncPolicy.psuRejectionTTL`) y desaparece al cambiar de sesión.
    public var psuRejectedAt: Date?

    enum CodingKeys: String, CodingKey {
        case sessionID, accountUIDs, validUntil, aspspName, aspspCountry, requiredPSUHeaders, psuRejectedAt
    }

    public init(
        sessionID: String, accountUIDs: [String], validUntil: Date, aspspName: String, aspspCountry: String,
        requiredPSUHeaders: [String]? = nil, psuRejectedAt: Date? = nil
    ) {
        self.sessionID = sessionID
        self.accountUIDs = accountUIDs
        self.validUntil = validUntil
        self.aspspName = aspspName
        self.aspspCountry = aspspCountry
        self.requiredPSUHeaders = requiredPSUHeaders
        self.psuRejectedAt = psuRejectedAt
    }

    /// `true` mientras la marca anti-422 siga vigente (menos de 7 días y no anotada en el futuro).
    public func isPSURejected(now: Date) -> Bool {
        guard let at = psuRejectedAt else { return false }
        let elapsed = now.timeIntervalSince(at)
        return elapsed >= 0 && elapsed < SyncPolicy.psuRejectionTTL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        accountUIDs = try c.decode([String].self, forKey: .accountUIDs)
        validUntil = try c.decode(Date.self, forKey: .validUntil)
        aspspName = try c.decode(String.self, forKey: .aspspName)
        aspspCountry = try c.decode(String.self, forKey: .aspspCountry)
        requiredPSUHeaders = try c.decodeIfPresent([String].self, forKey: .requiredPSUHeaders)
        psuRejectedAt = try c.decodeIfPresent(Date.self, forKey: .psuRejectedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(accountUIDs, forKey: .accountUIDs)
        try c.encode(validUntil, forKey: .validUntil)
        try c.encode(aspspName, forKey: .aspspName)
        try c.encode(aspspCountry, forKey: .aspspCountry)
        try c.encodeIfPresent(requiredPSUHeaders, forKey: .requiredPSUHeaders)
        try c.encodeIfPresent(psuRejectedAt, forKey: .psuRejectedAt)
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
