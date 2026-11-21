import Foundation

/// Estado de la conexión de un banco. Solo lo que se puede mostrar: nunca ids de sesión, cuentas, IBAN ni claves
/// (eso vive en el Llavero).
public struct BankLinkInfo: Codable, Equatable, Sendable {
    public var connectedAt: Date
    public var consentValidUntil: Date
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var problem: SyncProblem?
    public var backoffUntil: Date?
    /// Instantes de las últimas consultas al banco (para respetar su límite diario).
    public var fetchLog: [Date]
    public var historyLoaded: Bool

    public init(connectedAt: Date, consentValidUntil: Date) {
        self.connectedAt = connectedAt
        self.consentValidUntil = consentValidUntil
        self.lastAttemptAt = nil
        self.lastSuccessAt = nil
        self.problem = nil
        self.backoffUntil = nil
        self.fetchLog = []
        self.historyLoaded = false
    }
}
