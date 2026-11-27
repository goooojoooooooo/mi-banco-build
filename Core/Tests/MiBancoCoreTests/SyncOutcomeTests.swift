import Foundation
import Testing
@testable import MiBancoCore

/// Lote final: `SyncOutcome` vive en Core y su reparto al veredicto de «Al día» tiene pruebas.
@Suite struct SyncOutcomeTests {
    @Test func everyOutcomeMapsToItsRefreshOutcome() {
        let until = Date(timeIntervalSince1970: 1_764_000_000)
        #expect(SyncOutcome.updated(added: 0).refreshOutcome == .updated)
        #expect(SyncOutcome.updated(added: 7).refreshOutcome == .updated)
        #expect(SyncOutcome.skipped(.fresh).refreshOutcome == .skipped(.fresh))
        #expect(SyncOutcome.skipped(.waiting(until: until)).refreshOutcome == .skipped(.waiting(until: until)))
        #expect(SyncOutcome.skipped(.budgetUsed(nextAt: until)).refreshOutcome == .skipped(.budgetUsed(nextAt: until)))
        #expect(SyncOutcome.skipped(.consentExpired).refreshOutcome == .skipped(.consentExpired))
        #expect(SyncOutcome.skipped(.notConnected).refreshOutcome == .skipped(.notConnected))
        #expect(SyncOutcome.failed(.offline).refreshOutcome == .failed(.offline))
        #expect(SyncOutcome.failed(.rateLimited).refreshOutcome == .failed(.rateLimited))
    }
}
