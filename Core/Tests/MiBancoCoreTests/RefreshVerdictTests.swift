import Foundation
import Testing
@testable import MiBancoCore

private let now = Date(timeIntervalSince1970: 1_795_000_000)

/// Un banco conectado: consentimiento vigente; `succeeded` = hace cuánto se leyó bien por última vez (nil = nunca).
private func link(succeeded ago: TimeInterval? = 60, problem: SyncProblem? = nil) -> BankLinkInfo {
    var l = BankLinkInfo(connectedAt: now.addingTimeInterval(-30 * 86_400), consentValidUntil: now.addingTimeInterval(90 * 86_400))
    l.lastSuccessAt = ago.map { now.addingTimeInterval(-$0) }
    l.lastAttemptAt = l.lastSuccessAt
    l.problem = problem
    return l
}

private func verdict(_ outcomes: [BankID: BankRefreshOutcome], _ links: [BankID: BankLinkInfo]) -> Bool {
    RefreshVerdict.isUpToDate(outcomes: outcomes, links: links, now: now)
}

@Suite struct RefreshVerdictTests {
    @Test func allUpdatedIsUpToDate() {
        #expect(verdict([.rev: .updated, .ima: .updated], [.rev: link(), .ima: link()]))
    }

    @Test func oneFailedIsNot() {
        #expect(!verdict([.rev: .updated, .ima: .failed(.offline)], [.rev: link(), .ima: link()]))
    }

    @Test func consentExpiredIsNot() {
        #expect(!verdict(
            [.rev: .updated, .ima: .skipped(.consentExpired)],
            [.rev: link(), .ima: link(succeeded: 7_200, problem: .consentExpired)]))
    }

    @Test func dailyBudgetUsedIsNotUnlessFresh() {
        let budget = BankRefreshOutcome.skipped(.budgetUsed(nextAt: now.addingTimeInterval(3_600)))
        // Leído bien hace 10 horas: los datos pueden ser viejos.
        #expect(!verdict([.rev: budget], [.rev: link(succeeded: 36_000)]))
        // Nunca leído bien.
        #expect(!verdict([.rev: budget], [.rev: link(succeeded: nil)]))
        // Leído bien hace 10 minutos y sin problema: está al día de verdad.
        #expect(verdict([.rev: budget], [.rev: link(succeeded: 600)]))
    }

    @Test func freshSkipCountsOnlyIfReallyFresh() {
        // Saltado por «reciente» tras un intento que falló sin conexión: no está al día.
        #expect(!verdict([.rev: .skipped(.fresh)], [.rev: link(succeeded: 7_200 * 3, problem: .offline)]))
        #expect(verdict([.rev: .skipped(.fresh)], [.rev: link(succeeded: 30)]))
    }

    @Test func waitingAfterAFailureIsNot() {
        #expect(!verdict(
            [.rev: .skipped(.waiting(until: now.addingTimeInterval(3_600)))],
            [.rev: link(succeeded: 600, problem: .rateLimited)]))
    }

    @Test func syncDisabledIsNot() {
        // La consulta está desactivada: no devuelve nada aunque haya bancos conectados.
        #expect(!verdict([:], [.rev: link(), .ima: link()]))
    }

    @Test func connectedBankMissingFromOutcomesIsNot() {
        #expect(!verdict([.rev: .updated], [.rev: link(), .tr: link()]))
    }

    @Test func noBankConnectedIsNot() {
        #expect(!verdict([:], [:]))
        #expect(!verdict([.rev: .skipped(.notConnected), .ima: .skipped(.notConnected)], [:]))
    }

    /// Justo en el límite: una lectura de hace exactamente 3 h ya no es reciente (como `SyncPolicy.decide`, que con
    /// 3 h exactas vuelve a consultar); un segundo antes, sí.
    @Test func exactlyThreeHoursIsNotFresh() {
        let spacing = SyncPolicy.autoSpacing
        #expect(!verdict([.rev: .skipped(.fresh)], [.rev: link(succeeded: spacing)]))
        #expect(verdict([.rev: .skipped(.fresh)], [.rev: link(succeeded: spacing - 1)]))
    }

    /// Un reloj que va hacia atrás (última lectura «en el futuro») cuenta como reciente, igual que en `SyncPolicy`:
    /// la app no consulta y tampoco puede decir que los datos sean viejos.
    @Test func lastReadInTheFutureCountsAsFresh() {
        #expect(verdict([.rev: .skipped(.fresh)], [.rev: link(succeeded: -600)]))
    }

    @Test func mixOfUpdatedAndFreshIsUpToDate() {
        #expect(verdict(
            [.rev: .updated, .ima: .skipped(.fresh), .tr: .skipped(.notConnected)],
            [.rev: link(), .ima: link(succeeded: 90)]))
    }
}
