import Foundation
import Testing
@testable import MiBancoCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func flow(in phase: ConnectPhase) -> ConnectFlow {
    var f = ConnectFlow()
    switch phase {
    case .idle: break
    case .opening(let b): _ = f.handle(.start(b))
    case .waitingForBank(let b): _ = f.handle(.start(b)); _ = f.handle(.webOpened(b))
    case .finishing(let b): _ = f.handle(.start(b)); _ = f.handle(.webOpened(b)); _ = f.handle(.callback(.valid(b)))
    case .connected(let b): f = flow(in: .finishing(b)); _ = f.handle(.succeeded(b))
    case .needsResume(let b): f = flow(in: .waitingForBank(b)); _ = f.handle(.cancel)
    case .failed(let b, let m): f = flow(in: .opening(b)); _ = f.handle(.failed(b, m))
    case .chooseASPSP(let b, let l): f = flow(in: .opening(b)); _ = f.handle(.needsChoice(b, l))
    }
    return f
}

@Suite struct ConnectFlowTests {
    // MARK: arranque

    @Test func startOpensAndWebOpenedWaits() {
        var f = ConnectFlow()
        #expect(f.handle(.start(.rev)) == [])
        #expect(f.phase == .opening(.rev))
        #expect(f.handle(.webOpened(.rev)) == [])
        #expect(f.phase == .waitingForBank(.rev))
    }

    @Test func startIsIgnoredWhileActive() {
        for p in [ConnectPhase.opening(.rev), .waitingForBank(.rev), .finishing(.rev)] {
            var f = flow(in: p)
            #expect(f.handle(.start(.ima)) == [])
            #expect(f.phase == p)
        }
    }

    @Test func startIsAllowedAfterEndStates() {
        for p in [ConnectPhase.idle, .connected(.rev), .failed(.rev, "x"), .needsResume(.rev),
                  .chooseASPSP(.rev, [])] {
            var f = flow(in: p)
            #expect(f.handle(.start(.ima)) == [])
            #expect(f.phase == .opening(.ima))
        }
    }

    @Test func choiceOnlyFromOpening() {
        let list = [EBASPSP(name: "Un banco", country: "ES")]
        var f = flow(in: .opening(.ima))
        _ = f.handle(.needsChoice(.ima, list))
        #expect(f.phase == .chooseASPSP(.ima, list))
        var g = flow(in: .waitingForBank(.ima))
        _ = g.handle(.needsChoice(.ima, list))
        #expect(g.phase == .waitingForBank(.ima))
    }

    // MARK: la vuelta del banco, según el estado

    @Test func validCallbackWhileWaitingProcessesOnce() {
        var f = flow(in: .waitingForBank(.rev))
        #expect(f.handle(.callback(.valid(.rev))) == [.cancelWebSession, .processCallback(.rev)])
        #expect(f.phase == .finishing(.rev))
        // La segunda vuelta no encuentra nada pendiente; aunque lo encontrara, ya se está terminando.
        #expect(f.handle(.callback(.none)) == [])
        #expect(f.handle(.callback(.valid(.rev))) == [])
        #expect(f.phase == .finishing(.rev))
    }

    @Test func validCallbackIsProcessedInEveryStateButFinishing() {
        for p in [ConnectPhase.idle, .opening(.rev), .waitingForBank(.rev), .needsResume(.rev),
                  .failed(.rev, "x"), .connected(.rev)] {
            var f = flow(in: p)
            let actions = f.handle(.callback(.valid(.rev)))
            #expect(actions == [.cancelWebSession, .processCallback(.rev)], "\(p)")
            #expect(f.phase == .finishing(.rev))
        }
        var g = flow(in: .finishing(.rev))
        #expect(g.handle(.callback(.valid(.rev))) == [])
    }

    @Test func callbackWithoutPendingChangesNothing() {
        for p in [ConnectPhase.idle, .opening(.rev), .waitingForBank(.rev), .needsResume(.rev),
                  .failed(.rev, "x"), .connected(.rev), .finishing(.rev), .chooseASPSP(.rev, [])] {
            var f = flow(in: p)
            #expect(f.handle(.callback(.none)) == [])
            #expect(f.phase == p)
        }
    }

    @Test func callbackAfterTheTimeoutIsRejected() {
        var f = flow(in: .waitingForBank(.ima))
        let actions = f.handle(.callback(.expired(.ima)))
        #expect(actions == [.deletePending, .cancelWebSession])
        #expect(f.phase == .failed(.ima, ConnectMessage.tooSlow))
        var g = flow(in: .finishing(.ima))
        #expect(g.handle(.callback(.expired(.ima))) == [])
        #expect(g.phase == .finishing(.ima))
    }

    // MARK: bloqueo y fase de la escena (R14)

    @Test func backgroundNeverCancelsAndShortAbsenceKeepsWaiting() {
        var f = flow(in: .waitingForBank(.rev))
        #expect(f.handle(.sceneBackground(t0)) == [])
        #expect(f.phase == .waitingForBank(.rev))
        #expect(f.handle(.sceneActive(t0.addingTimeInterval(299))) == [])
        #expect(f.phase == .waitingForBank(.rev))
    }

    @Test func away300SecondsNeedsResumeAndCancels() {
        var f = flow(in: .waitingForBank(.rev))
        _ = f.handle(.sceneBackground(t0))
        #expect(f.handle(.sceneActive(t0.addingTimeInterval(300))) == [.cancelWebSession])
        #expect(f.phase == .needsResume(.rev))
    }

    @Test func longAbsenceWhileOpeningAlsoNeedsResume() {
        var f = flow(in: .opening(.rev))
        _ = f.handle(.sceneBackground(t0))
        #expect(f.handle(.sceneActive(t0.addingTimeInterval(900))) == [.cancelWebSession])
        #expect(f.phase == .needsResume(.rev))
    }

    @Test func longAbsenceDoesNotTouchOtherPhases() {
        for p in [ConnectPhase.idle, .finishing(.rev), .connected(.rev), .failed(.rev, "x"),
                  .needsResume(.rev), .chooseASPSP(.rev, [])] {
            var f = flow(in: p)
            _ = f.handle(.sceneBackground(t0))
            #expect(f.handle(.sceneActive(t0.addingTimeInterval(10_000))) == [])
            #expect(f.phase == p)
        }
    }

    @Test func secondBackgroundKeepsTheFirstInstant() {
        var f = flow(in: .waitingForBank(.rev))
        _ = f.handle(.sceneBackground(t0))
        _ = f.handle(.sceneBackground(t0.addingTimeInterval(250)))
        #expect(f.handle(.sceneActive(t0.addingTimeInterval(320))) == [.cancelWebSession])
    }

    @Test func activeClearsTheAbsence() {
        var f = flow(in: .waitingForBank(.rev))
        _ = f.handle(.sceneBackground(t0))
        _ = f.handle(.sceneActive(t0.addingTimeInterval(10)))
        // Un `.active` sin `.background` previo (p. ej. tras el aviso del sistema) no cuenta como ausencia.
        #expect(f.handle(.sceneActive(t0.addingTimeInterval(1_000))) == [])
        #expect(f.phase == .waitingForBank(.rev))
    }

    @Test func callbackWhileAwayIsStillProcessedAfterTheTimeout() {
        var f = flow(in: .waitingForBank(.rev))
        _ = f.handle(.sceneBackground(t0))
        _ = f.handle(.sceneActive(t0.addingTimeInterval(400)))
        #expect(f.phase == .needsResume(.rev))
        #expect(f.handle(.callback(.valid(.rev))) == [.cancelWebSession, .processCallback(.rev)])
        #expect(f.phase == .finishing(.rev))
    }

    // MARK: cancelar, seguir, empezar de nuevo

    @Test func explicitCancelLeavesNeedsResume() {
        var f = flow(in: .waitingForBank(.rev))
        #expect(f.handle(.cancel) == [.cancelWebSession])
        #expect(f.phase == .needsResume(.rev))
        var g = flow(in: .finishing(.rev))
        #expect(g.handle(.cancel) == [])
        #expect(g.phase == .finishing(.rev))
    }

    @Test func userClosingTheSheetFails() {
        var f = flow(in: .waitingForBank(.rev))
        #expect(f.handle(.webDismissedByUser) == [.deletePending])
        #expect(f.phase == .failed(.rev, ConnectMessage.cancelled))
        // Tras cancelarlo la app, el aviso tardío de la hoja no cambia nada.
        var g = flow(in: .needsResume(.rev))
        #expect(g.handle(.webDismissedByUser) == [])
        #expect(g.phase == .needsResume(.rev))
    }

    @Test func resumeReopensWhilePendingIsValid() {
        var f = flow(in: .needsResume(.rev))
        #expect(f.handle(.resume(pending: .valid(.rev), hasAuthURL: true)) == [.openWeb(.rev)])
        #expect(f.phase == .opening(.rev))
    }

    @Test func resumeRestartsWithoutValidPendingOrURL() {
        for (check, hasURL) in [(PendingCheck.expired(.rev), true), (.none, true), (.valid(.rev), false),
                                (.valid(.ima), true)] {
            var f = flow(in: .needsResume(.rev))
            #expect(f.handle(.resume(pending: check, hasAuthURL: hasURL)) == [.restart(.rev)])
            #expect(f.phase == .needsResume(.rev))
        }
    }

    @Test func resumeOnlyFromNeedsResume() {
        var f = flow(in: .waitingForBank(.rev))
        #expect(f.handle(.resume(pending: .valid(.rev), hasAuthURL: true)) == [])
        #expect(f.phase == .waitingForBank(.rev))
    }

    // MARK: finales

    @Test func successAndFailureOnlyFromTheirPhases() {
        var f = flow(in: .finishing(.rev))
        _ = f.handle(.succeeded(.rev))
        #expect(f.phase == .connected(.rev))
        var g = flow(in: .waitingForBank(.rev))
        _ = g.handle(.succeeded(.rev))
        #expect(g.phase == .waitingForBank(.rev))
        var h = flow(in: .finishing(.rev))
        #expect(h.handle(.failed(.rev, "m")) == [.deletePending, .cancelWebSession])
        #expect(h.phase == .failed(.rev, "m"))
        var i = flow(in: .idle)
        #expect(i.handle(.failed(.rev, "m")) == [])
        #expect(i.phase == .idle)
    }

    @Test func resetOnlyOutsideWaitingAndFinishing() {
        for p in [ConnectPhase.connected(.rev), .failed(.rev, "x"), .needsResume(.rev), .opening(.rev)] {
            var f = flow(in: p)
            _ = f.handle(.reset)
            #expect(f.phase == .idle)
        }
        for p in [ConnectPhase.waitingForBank(.rev), .finishing(.rev)] {
            var f = flow(in: p)
            #expect(f.handle(.reset) == [])
            #expect(f.phase == p)
        }
    }

    @Test func activeFlagsMatchTheBrief() {
        #expect(ConnectPhase.opening(.rev).isActive)
        #expect(ConnectPhase.waitingForBank(.rev).isActive)
        #expect(ConnectPhase.finishing(.rev).isActive)
        #expect(!ConnectPhase.needsResume(.rev).isActive)
        #expect(!ConnectPhase.connected(.rev).isActive)
        #expect(!ConnectPhase.idle.isActive)
    }
}

@Suite struct ConnectMessagesTests {
    @Test func callbackResultsMapToTheBriefStrings() {
        #expect(connectMessage(for: .denied) == "Has cancelado en el banco. No se ha conectado nada.")
        #expect(connectMessage(for: .stateMismatch)
                == "Este enlace no es de tu conexión. Empieza de nuevo desde Ajustes.")
        #expect(connectMessage(for: .malformed)
                == "Este enlace no es de tu conexión. Empieza de nuevo desde Ajustes.")
        #expect(connectMessage(for: .code("c")) == nil)
    }

    @Test func clientErrorsMapToTheBriefStringsNeverRawText() {
        #expect(connectMessage(for: BankingClientError.api(.unknown, code: "EXPIRED_AUTHORIZATION_CODE"))
                == "El banco tardó demasiado. Vuelve a intentarlo.")
        #expect(connectMessage(for: BankingClientError.api(.bankUnavailable, code: nil))
                == "El banco tardó demasiado. Vuelve a intentarlo.")
        #expect(connectMessage(for: BankingClientError.api(.unknown, code: "REDIRECT_URI_NOT_ALLOWED"))
                == "Enable Banking no reconoce la dirección de vuelta. Revisa el paso 2 de la guía.")
        #expect(connectMessage(for: BankingClientError.offline) == "Sin conexión a internet.")
        #expect(connectMessage(for: BankingClientError.badResponse)
                == "El banco tardó demasiado. Vuelve a intentarlo.")
        struct Other: Error, CustomStringConvertible { var description: String { "texto crudo SECRETO" } }
        #expect(connectMessage(for: Other()) == "El banco tardó demasiado. Vuelve a intentarlo.")
    }

    @Test func noEuroAccountNamesTheBank() {
        #expect(ConnectMessage.noEuroAccount(.ima) == "No hemos encontrado una cuenta en euros en imagin.")
        #expect(ConnectMessage.noEuroAccount(.rev) == "No hemos encontrado una cuenta en euros en Revolut.")
    }

    @Test func callbackURLFilter() {
        func ok(_ s: String) -> Bool { isBankCallbackURL(URL(string: s)!) }
        #expect(ok("mibanco://cb?code=a&state=b"))
        #expect(ok("MIBANCO://CB?code=a&state=b"))
        #expect(!ok("mibanco://otro?code=a"))
        #expect(!ok("https://cb?code=a"))
        #expect(!ok("otro://cb"))
    }

    @Test func canConnectRules() {
        #expect(canConnectBank(.rev, cachedList: nil))
        #expect(canConnectBank(.ima, cachedList: []))
        #expect(!canConnectBank(.tr, cachedList: nil))
        #expect(!canConnectBank(.tr, cachedList: [EBASPSP(name: "Revolut", country: "ES")]))
        #expect(canConnectBank(.tr, cachedList: [EBASPSP(name: "Trade Republic", country: "DE")]))
    }
}

@Suite struct ConnectFlowReviewTests {
    @Test func forgedCallbackWhileWaitingIsIgnoredAndTheGenuineOneStillSucceeds() {
        var f = flow(in: .waitingForBank(.rev))
        // Una vuelta falsa (state distinto, ausente o forma rara) no cambia nada ni pide ninguna acción.
        for forged in [AuthCallbackResult.stateMismatch, .malformed] {
            #expect(f.handle(.callbackReceived(.valid(.rev), forged)) == [])
            #expect(f.phase == .waitingForBank(.rev))
        }
        // Tampoco si el intento ya caducó: una vuelta falsa no lo "cancela".
        #expect(f.handle(.callbackReceived(.expired(.rev), .stateMismatch)) == [])
        #expect(f.phase == .waitingForBank(.rev))
        // La de verdad sigue funcionando.
        #expect(f.handle(.callbackReceived(.valid(.rev), .code("c"))) == [.cancelWebSession, .processCallback(.rev)])
        #expect(f.phase == .finishing(.rev))
        #expect(f.handle(.succeeded(.rev)) == [])
        #expect(f.phase == .connected(.rev))
    }

    @Test func verifiedDeniedGoesThroughAndNoPendingIsAlwaysIgnored() {
        var f = flow(in: .waitingForBank(.ima))
        #expect(f.handle(.callbackReceived(.none, .code("c"))) == [])
        #expect(f.handle(.callbackReceived(.none, .denied)) == [])
        #expect(f.phase == .waitingForBank(.ima))
        #expect(f.handle(.callbackReceived(.valid(.ima), .denied)) == [.cancelWebSession, .processCallback(.ima)])
        #expect(f.phase == .finishing(.ima))
        var g = flow(in: .waitingForBank(.ima))
        #expect(g.handle(.callbackReceived(.expired(.ima), .code("c"))) == [.deletePending, .cancelWebSession])
        #expect(g.phase == .failed(.ima, ConnectMessage.tooSlow))
    }

    @Test func forgedCallbackInAnyPhaseChangesNothing() {
        let phases: [ConnectPhase] = [.idle, .opening(.rev), .waitingForBank(.rev), .finishing(.rev), .connected(.rev),
                                      .needsResume(.rev), .failed(.rev, "x")]
        for phase in phases {
            var f = flow(in: phase)
            let before = f
            #expect(f.handle(.callbackReceived(.valid(.rev), .stateMismatch)) == [])
            #expect(f.handle(.callbackReceived(.valid(.rev), .malformed)) == [])
            #expect(f == before)
        }
    }

    @Test func disconnectDuringFinishingWinsAndOtherBanksAreUntouched() {
        var f = flow(in: .finishing(.rev))
        #expect(f.handle(.disconnected(.ima)) == [])
        #expect(f.phase == .finishing(.rev))
        #expect(f.handle(.disconnected(.rev)) == [.cancelWebSession, .deletePending])
        #expect(f.phase == .idle)
        // Un `succeeded` tardío ya no vale.
        #expect(f.handle(.succeeded(.rev)) == [])
        #expect(f.phase == .idle)
        var done = flow(in: .connected(.rev))
        #expect(done.handle(.disconnected(.rev)) == [.deletePending])
        #expect(done.phase == .idle)
        var idle = ConnectFlow()
        #expect(idle.handle(.disconnected(.rev)) == [])
    }

    @Test func newMessagesAreExact() {
        #expect(ConnectMessage.missingCredentials == "Falta la clave de tu banco. Añádela en Ajustes › Bancos.")
        #expect(ConnectMessage.storeFailed == "No se pudo guardar la conexión en este iPhone. Vuelve a intentarlo.")
    }

    @Test func ledgerFailureRestoresThePreviousSessionOrDeletesTheNewOne() {
        let old = StoredSession(sessionID: "old", accountUIDs: ["a"], validUntil: t0, aspspName: "Banco", aspspCountry: "ES")
        #expect(rollbackAfterLedgerFailure(previous: old) == .restore(old))
        #expect(rollbackAfterLedgerFailure(previous: nil) == .deleteNew)
    }

    @Test func onlyADifferentOldRemoteSessionIsDeletedAfterReconnecting() {
        let old = StoredSession(sessionID: "old", accountUIDs: ["a"], validUntil: t0, aspspName: "Banco", aspspCountry: "ES")
        let new = StoredSession(sessionID: "new", accountUIDs: ["a"], validUntil: t0, aspspName: "Banco", aspspCountry: "ES")
        #expect(staleRemoteSessionID(previous: old, new: new) == "old")
        #expect(staleRemoteSessionID(previous: old, new: old) == nil)
        #expect(staleRemoteSessionID(previous: nil, new: new) == nil)
    }
}
