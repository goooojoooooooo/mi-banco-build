import Foundation

/// Lo único que se guarda de una sesión de banco. Sin IBAN.
public struct StoredSession: Codable, Equatable, Sendable {
    public var sessionID: String
    public var accountUIDs: [String]
    public var validUntil: Date
    public var aspspName: String
    public var aspspCountry: String

    public init(sessionID: String, accountUIDs: [String], validUntil: Date, aspspName: String, aspspCountry: String) {
        self.sessionID = sessionID
        self.accountUIDs = accountUIDs
        self.validUntil = validUntil
        self.aspspName = aspspName
        self.aspspCountry = aspspCountry
    }
}

/// Conexión a medias: se guarda al salir hacia el banco y caduca a los 15 minutos.
public struct PendingAuth: Codable, Equatable, Sendable {
    public var state: String
    public var bank: BankID
    public var aspspName: String
    public var aspspCountry: String
    public var startedAt: Date

    public init(state: String, bank: BankID, aspspName: String, aspspCountry: String, startedAt: Date) {
        self.state = state
        self.bank = bank
        self.aspspName = aspspName
        self.aspspCountry = aspspCountry
        self.startedAt = startedAt
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
