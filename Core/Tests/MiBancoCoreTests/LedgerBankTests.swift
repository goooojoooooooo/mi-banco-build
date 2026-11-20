import Foundation
import Testing
@testable import MiBancoCore

@Suite struct LedgerBankTests {
    /// 2026-11-20T10:00:00Z
    let t = ISO8601DateFormatter().date(from: "2026-11-20T10:00:00Z")!

    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func bankRecord(amount: Int = -1250, at date: Date, ref: String = "t1", importedAt: Date? = nil) -> Movement {
        Movement(bank: .rev, amountCents: amount, merchant: "MERCADONA VALENCIA", kind: .payment, source: .bank, date: date,
                 bankRef: ref, bankStatus: .pending, importedAt: importedAt ?? t, dayOnly: true)
    }

    private func isStored(_ o: IngestOutcome) -> Bool {
        if case .stored = o { return true }
        return false
    }

    // MARK: Compatibilidad con libros guardados

    @Test func oldLedgerDecodes() throws {
        let json = """
        {"balances":["rev",{"cents":1000,"setAt":1000,"fromBank":true},"ima",{"cents":5,"setAt":1000,"fromBank":false}],
         "movements":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-500,"kind":"payment",
         "source":"notification","date":2000}],"unread":[]}
        """
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(json.utf8))
        let m = try #require(state.movements.first)
        #expect(m.bankRef == nil)
        #expect(m.statementRef == nil)
        #expect(m.bankStatus == nil)
        #expect(m.importedAt == nil)
        #expect(m.dayOnly == false)
        #expect(m.isHistorical == false)
        #expect(state.balances[.rev]?.origin == .notice)
        #expect(state.balances[.rev]?.fromBank == true)
        #expect(state.balances[.ima]?.origin == .manual)
        #expect(state.balances[.ima]?.fromBank == false)
        #expect(state.balances[.rev]?.fetchedAt == nil)
        #expect(state.links == [:])
    }

    @Test func manualBalanceRoundTripsOriginAndFromBank() throws {
        let b = ManualBalance(cents: 7, setAt: t, origin: .statement)
        let back = try JSONDecoder().decode(ManualBalance.self, from: JSONEncoder().encode(b))
        #expect(back == b)
        #expect(back.fromBank == true)
        let text = String(decoding: try JSONEncoder().encode(b), as: UTF8.self)
        #expect(text.contains("\"origin\""))
        #expect(text.contains("\"fromBank\""))
        #expect(ManualBalance(cents: 1, setAt: t, fromBank: true).origin == .notice)
        #expect(ManualBalance(cents: 1, setAt: t, fromBank: false).origin == .manual)
        // R31: la hora de la consulta también viaja; sin ella no se escribe la clave.
        let fetched = ManualBalance(cents: 7, setAt: t, origin: .bank, fetchedAt: t + 60)
        let fetchedBack = try JSONDecoder().decode(ManualBalance.self, from: JSONEncoder().encode(fetched))
        #expect(fetchedBack == fetched)
        #expect(fetchedBack.fetchedAt == t + 60)
        #expect(!text.contains("fetchedAt"))
    }

    @Test func isHistoricalOnlyForOldImportedRows() {
        let imported = t
        let old = Movement(bank: .rev, amountCents: -1, merchant: nil, kind: .payment, source: .bank,
                           date: imported.addingTimeInterval(-49 * 3600), importedAt: imported)
        let recent = Movement(bank: .rev, amountCents: -1, merchant: nil, kind: .payment, source: .bank,
                              date: imported.addingTimeInterval(-47 * 3600), importedAt: imported)
        let captured = Movement(bank: .rev, amountCents: -1, merchant: nil, kind: .payment, source: .wallet,
                                date: imported.addingTimeInterval(-900 * 3600))
        #expect(old.isHistorical)
        #expect(!recent.isHistorical)
        #expect(!captured.isHistorical)
    }

    // MARK: Saldo

    @Test func capturedAfterBankBalanceMakesEstimate() {
        var l = Ledger()
        let adopted0 = l.adoptBalance(.rev, cents: 100_000, at: t, origin: .bank)
        #expect(adopted0)
        let b0 = l.balance(.rev)
        #expect(b0?.cents == 100_000)
        #expect(b0?.estimated == false)
        _ = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: t + 60)
        let b = l.balance(.rev)
        #expect(b?.cents == 98_750)
        #expect(b?.estimated == true)
    }

    @Test func bankRecordsNeverAddToBankBalance() {
        var l = Ledger()
        l.adoptBalance(.rev, cents: 100_000, at: t, origin: .bank)
        var s = l.state
        s.movements.append(Movement(bank: .rev, amountCents: -500, merchant: nil, kind: .payment, source: .bank,
                                    date: t + 3600, bankRef: "x", dayOnly: true))
        s.movements.append(Movement(bank: .rev, amountCents: -300, merchant: nil, kind: .payment, source: .wallet,
                                    date: t - 60, bankRef: "y"))  // R21: enlazado y anterior a la lectura
        let b = Ledger(state: s).balance(.rev)
        #expect(b?.cents == 100_000)
        #expect(b?.estimated == false)
    }

    @Test func statementMovementsAddOnlyToManualBase() {
        let row = Movement(bank: .tr, amountCents: -1_000, merchant: nil, kind: .payment, source: .statement,
                           date: t + 86_400, statementRef: "s", dayOnly: true)
        var manual = Ledger()
        manual.setBalance(.tr, cents: 50_000, now: t)
        var ms = manual.state
        ms.movements.append(row)
        let mb = Ledger(state: ms).balance(.tr)
        #expect(mb?.cents == 49_000)
        #expect(mb?.estimated == true)

        var viaStatement = Ledger()
        viaStatement.adoptBalance(.tr, cents: 50_000, at: t, origin: .statement)
        var ss = viaStatement.state
        ss.movements.append(row)
        let sb = Ledger(state: ss).balance(.tr)
        #expect(sb?.cents == 50_000)
        #expect(sb?.estimated == false)
    }

    /// Fija el criterio único que usan `Ledger.balance` y "Te quedaban" (`LedgerSnapshot.balanceAfter`).
    @Test func countsTowardBalancePredicateIsPinned() {
        func m(_ source: Movement.Source, bankRef: String? = nil, at: Date) -> Movement {
            Movement(bank: .rev, amountCents: -100, merchant: nil, kind: .payment, source: source, date: at, bankRef: bankRef)
        }
        let bankBase = ManualBalance(cents: 1, setAt: t, origin: .bank)
        let manualBase = ManualBalance(cents: 1, setAt: t, origin: .manual)
        // Capturados posteriores: cuentan sobre cualquier base.
        #expect(Ledger.countsTowardBalance(m(.notification, at: t + 1), base: bankBase))
        #expect(Ledger.countsTowardBalance(m(.wallet, at: t + 1), base: manualBase))
        // Ni anteriores ni en el mismo instante de la lectura.
        #expect(!Ledger.countsTowardBalance(m(.wallet, at: t), base: bankBase))
        #expect(!Ledger.countsTowardBalance(m(.wallet, at: t - 1), base: bankBase))
        // Registros del banco: nunca.
        #expect(!Ledger.countsTowardBalance(m(.bank, at: t + 1), base: manualBase))
        // R21: enlazado a un registro del banco cuenta solo si es posterior a la lectura (hora precisa).
        #expect(Ledger.countsTowardBalance(m(.wallet, bankRef: "k", at: t + 1), base: bankBase))
        #expect(!Ledger.countsTowardBalance(m(.wallet, bankRef: "k", at: t), base: bankBase))
        #expect(!Ledger.countsTowardBalance(m(.wallet, bankRef: "k", at: t - 1), base: bankBase))
        #expect(!Ledger.countsTowardBalance(Movement(bank: .rev, amountCents: -100, merchant: nil, kind: .payment, source: .wallet,
                                                     date: t + 1, bankRef: "k", dayOnly: true), base: bankBase))
        // Extracto: solo sobre una base a mano.
        #expect(Ledger.countsTowardBalance(m(.statement, at: t + 1), base: manualBase))
        #expect(!Ledger.countsTowardBalance(m(.statement, at: t + 1), base: bankBase))
        #expect(!Ledger.countsTowardBalance(m(.statement, at: t + 1), base: ManualBalance(cents: 1, setAt: t, origin: .statement)))
        // R27: enlazado cuyo registro ya se conocía al tomar la lectura (importedAt <= lectura) no cuenta; posterior, sí.
        func late(importedAt: Date?) -> Movement {
            Movement(bank: .rev, amountCents: -100, merchant: nil, kind: .payment, source: .notification, date: t + 300,
                     bankRef: "k", importedAt: importedAt)
        }
        #expect(!Ledger.countsTowardBalance(late(importedAt: t), base: bankBase))
        #expect(!Ledger.countsTowardBalance(late(importedAt: t - 60), base: bankBase))
        #expect(Ledger.countsTowardBalance(late(importedAt: t + 60), base: bankBase))
        #expect(Ledger.countsTowardBalance(late(importedAt: nil), base: bankBase))
        // R31: con la hora de la consulta (`fetchedAt`) manda esa, no la de referencia del saldo (`setAt`).
        let fetchedBase = ManualBalance(cents: 1, setAt: t - 60, origin: .bank, fetchedAt: t)
        #expect(!Ledger.countsTowardBalance(late(importedAt: t), base: fetchedBase))
        #expect(!Ledger.countsTowardBalance(late(importedAt: t - 30), base: fetchedBase))
        #expect(Ledger.countsTowardBalance(late(importedAt: t + 1), base: fetchedBase))
        #expect(Ledger.countsTowardBalance(late(importedAt: nil), base: fetchedBase))
        // Sin `fetchedAt` se usa `setAt`, como antes.
        #expect(Ledger.countsTowardBalance(late(importedAt: t - 30), base: ManualBalance(cents: 1, setAt: t - 60, origin: .bank)))
        // R24: enlazado a una fila de extracto, sobre un saldo de extracto, nunca; sobre un saldo del banco, como R21.
        let stmtLinked = Movement(bank: .rev, amountCents: -100, merchant: nil, kind: .payment, source: .wallet, date: t + 300,
                                  statementRef: "s")
        #expect(!Ledger.countsTowardBalance(stmtLinked, base: ManualBalance(cents: 1, setAt: t, origin: .statement)))
        #expect(Ledger.countsTowardBalance(stmtLinked, base: bankBase))
        #expect(Ledger.countsTowardBalance(stmtLinked, base: manualBase))
        // La parte sin fecha (la que usa "Te quedaban" para el movimiento que cae justo en la lectura).
        #expect(Ledger.isBalanceEligible(m(.wallet, at: t), origin: .bank))
        #expect(!Ledger.isBalanceEligible(m(.bank, at: t), origin: .manual))
    }

    /// R27: el banco dio el pago antes que el aviso; el aviso tardío se fusiona y no se resta otra vez.
    @Test func lateNoticeMergedIntoKnownRowIsNotCountedAgain() {
        let reading = iso("2026-11-20T12:00:00Z")  // 13:00 en Madrid
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 10_000, setAt: reading, origin: .bank)],
                                          movements: [bankRecord(amount: -1250, at: iso("2026-11-20T11:00:00Z"), importedAt: reading)]))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T12:05:00Z"))
        guard case .merged = outcome else { Issue.record("esperaba .merged: \(outcome)"); return }
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == false)
    }

    /// R31: la consulta de las 13:00 trae la fila de -12,50 € y un saldo de 100,00 € con hora de referencia 12:59; el aviso
    /// llega a las 13:05 y se fusiona en esa fila: ya estaba dentro del saldo, aunque la fila se importó DESPUÉS de la
    /// hora de referencia.
    @Test func lateNoticeIsNotCountedWhenRowWasFetchedAfterReadingReference() {
        let fetch = iso("2026-11-20T13:00:00Z")
        let reference = iso("2026-11-20T12:59:00Z")
        func ledger(fetchedAt: Date?) -> Ledger {
            var l = Ledger(state: LedgerState(movements: [bankRecord(amount: -1250, at: iso("2026-11-20T11:00:00Z"), importedAt: fetch)]))
            l.adoptBalance(.rev, cents: 10_000, at: reference, origin: .bank, fetchedAt: fetchedAt)
            return l
        }
        var l = ledger(fetchedAt: fetch)
        #expect(l.state.balances[.rev]?.fetchedAt == fetch)
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T13:05:00Z"))
        guard case .merged = outcome else { Issue.record("esperaba .merged: \(outcome)"); return }
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == false)
        // Control: sin `fetchedAt` (libro anterior) la regla vieja lo contaría otra vez.
        var old = ledger(fetchedAt: nil)
        _ = old.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T13:05:00Z"))
        #expect(old.balance(.rev)?.cents == 8750)
    }

    /// R24: un capturado enlazado a una fila de extracto no se cuenta dos veces sobre un saldo de extracto.
    @Test func captureLinkedToStatementRowIsNotCountedOnStatementBalance() {
        let reading = iso("2026-11-19T11:00:00Z")
        let capture = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .wallet,
                               date: iso("2026-11-19T15:00:00Z"), statementRef: "r|abc|1")
        let l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 10_000, setAt: reading, origin: .statement)],
                                          movements: [capture]))
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == false)
    }

    @Test func olderReadingIsRejected() {
        var l = Ledger()
        l.adoptBalance(.rev, cents: 100, at: t, origin: .bank)
        let stale = l.adoptBalance(.rev, cents: 1, at: t - 60, origin: .notice)
        #expect(stale == false)
        #expect(l.balance(.rev)?.cents == 100)
        #expect(l.state.balances[.rev]?.origin == .bank)
        let fresh = l.adoptBalance(.rev, cents: 1, at: t + 60, origin: .notice)
        #expect(fresh)
        #expect(l.balance(.rev)?.cents == 1)

        var m = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 5, setAt: t + 3600, origin: .manual)]))
        let manualYields = m.adoptBalance(.rev, cents: 100, at: t, origin: .bank)
        #expect(manualYields)
        #expect(m.state.balances[.rev]?.origin == .bank)
    }

    @Test func noticeBalanceRespectsNewerBank() {
        var l = Ledger()
        l.adoptBalance(.rev, cents: 100_000, at: t, origin: .bank)
        _ = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 12,50 €\nSaldo: 327,70 €"), now: t - 30)
        #expect(l.balance(.rev)?.cents == 100_000)
        #expect(l.state.balances[.rev]?.origin == .bank)
    }

    // MARK: Fusión al registrar

    private func bankFirstLedger(bankDate: Date) -> Ledger {
        Ledger(state: LedgerState(movements: [bankRecord(at: bankDate)]))
    }

    @Test func notificationAfterBankRecordMerges() throws {
        let noon = iso("2026-11-20T11:00:00Z")  // 12:00 en Madrid
        var l = bankFirstLedger(bankDate: noon)
        let now = iso("2026-11-20T17:00:00Z")
        let outcome = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 12,50 € en Mercadona"), now: now)
        guard case .merged(let m) = outcome else { Issue.record("esperaba .merged: \(outcome)"); return }
        #expect(l.state.movements.count == 1)
        #expect(m.source == .notification)
        #expect(m.date == now)
        #expect(m.dayOnly == false)
        #expect(m.fingerprint != nil)
        #expect(m.bankRef == "t1")
        #expect(m.merchant == "Mercadona")
        #expect(l.state.movements[0] == m)
        let again = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 12,50 € en Mercadona"), now: now + 30)
        #expect(again == .duplicate)
        #expect(l.state.movements.count == 1)
    }

    @Test func walletAfterBankRecordMerges() {
        var l = bankFirstLedger(bankDate: iso("2026-11-20T11:00:00Z"))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T09:00:00Z"))
        guard case .merged(let m) = outcome else { Issue.record("esperaba .merged"); return }
        #expect(m.source == .wallet)
        #expect(m.isShop)
        #expect(l.state.movements.count == 1)
    }

    /// Un registro del banco a mediodía cae a pocos segundos del aviso: no debe emparejarse como "otra fuente" (duplicado
    /// silencioso) sino fusionarse.
    @Test func bankRecordIsNotPairedAsDuplicateByTimeWindow() {
        var l = bankFirstLedger(bankDate: iso("2026-11-20T11:00:00Z"))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T11:01:00Z"))
        if case .merged = outcome {} else { Issue.record("esperaba .merged: \(outcome)") }
        #expect(l.state.movements[0].pairedAcrossSources == false)
    }

    @Test func noMergeWithOldBankRecord() {
        var l = bankFirstLedger(bankDate: iso("2026-11-16T11:00:00Z"))
        let outcome = l.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Has pagado 12,50 € en Mercadona"),
                               now: iso("2026-11-20T17:00:00Z"))
        #expect(isStored(outcome))
        #expect(l.state.movements.count == 2)
    }

    @Test func noMergeAcrossBanksOrAmounts() {
        var l = bankFirstLedger(bankDate: iso("2026-11-20T11:00:00Z"))
        let o1 = l.ingest(.wallet(bank: .ima, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T17:00:00Z"))
        #expect(isStored(o1))
        let o2 = l.ingest(.wallet(bank: .rev, amount: "12,51", merchant: "Mercadona"), now: iso("2026-11-20T17:00:00Z"))
        #expect(isStored(o2))
        #expect(l.state.movements.count == 3)
    }

    @Test func mergePicksClosestRecord() {
        var l = Ledger(state: LedgerState(movements: [
            bankRecord(at: iso("2026-11-19T11:00:00Z"), ref: "far"),
            bankRecord(at: iso("2026-11-20T11:00:00Z"), ref: "near"),
        ]))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T17:00:00Z"))
        guard case .merged(let m) = outcome else { Issue.record("esperaba .merged"); return }
        #expect(m.bankRef == "near")
        #expect(l.state.movements.count == 2)
    }

    @Test func mergedMovementKeepsBalanceHonest() {
        var l = Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 100_000, setAt: iso("2026-11-20T08:00:00Z"), origin: .bank)],
                                          movements: [bankRecord(at: iso("2026-11-20T11:00:00Z"))]))
        #expect(l.balance(.rev)?.cents == 100_000)
        _ = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T17:00:00Z"))
        // R21: el aviso (hora precisa, 17:00) es posterior a la lectura (08:00): sigue contando y el saldo es estimado.
        #expect(l.balance(.rev)?.cents == 100_000 - 1250)
        #expect(l.balance(.rev)?.estimated == true)
    }

    private func linkedCapture(readingAt: Date) -> Ledger {
        let capture = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .notification,
                               date: iso("2026-11-20T10:05:00Z"), bankRef: "t1", bankStatus: .booked)
        return Ledger(state: LedgerState(balances: [.rev: ManualBalance(cents: 10_000, setAt: readingAt, origin: .bank)],
                                         movements: [capture]))
    }

    @Test func linkedCaptureAfterReadingStillCounts() {
        let l = linkedCapture(readingAt: iso("2026-11-20T10:02:00Z"))
        #expect(l.balance(.rev)?.cents == 8750)
        #expect(l.balance(.rev)?.estimated == true)
    }

    @Test func linkedCaptureBeforeReadingIsNotCounted() {
        let l = linkedCapture(readingAt: iso("2026-11-20T13:00:00Z"))
        #expect(l.balance(.rev)?.cents == 10_000)
        #expect(l.balance(.rev)?.estimated == false)
    }

    @Test func captureDoesNotMergeIntoYesterdaysRow() {
        var l = bankFirstLedger(bankDate: iso("2026-11-19T11:00:00Z"))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-20T08:00:00Z"))  // 09:00 Madrid
        #expect(isStored(outcome))
        #expect(l.state.movements.count == 2)
    }

    @Test func captureJustAfterMidnightMergesIntoYesterdaysRow() {
        var l = bankFirstLedger(bankDate: iso("2026-11-19T11:00:00Z"))
        let outcome = l.ingest(.wallet(bank: .rev, amount: "12,50", merchant: "Mercadona"), now: iso("2026-11-19T23:20:00Z"))  // 00:20 Madrid del 20
        if case .merged = outcome {} else { Issue.record("esperaba .merged: \(outcome)") }
        #expect(l.state.movements.count == 1)
    }

    // MARK: Secretos

    @Test func ledgerJSONHasNoSecrets() throws {
        var l = Ledger(state: LedgerState(movements: [bankRecord(at: t)]))
        l.setLink(.rev, BankLinkInfo(connectedAt: t, consentValidUntil: t + 86_400 * 180))
        var info = BankLinkInfo(connectedAt: t, consentValidUntil: t + 86_400 * 180)
        info.problem = .rateLimited
        info.fetchLog = [t]
        l.setLink(.ima, info)
        let data = try JSONEncoder().encode(l.state)
        func keys(_ any: Any) -> Set<String> {
            if let d = any as? [String: Any] { return Set(d.keys).union(d.values.flatMap { keys($0) }) }
            if let a = any as? [Any] { return Set(a.flatMap { keys($0) }) }
            return []
        }
        let found = keys(try JSONSerialization.jsonObject(with: data))
        for forbidden in ["sessionID", "session_id", "uid", "iban", "appID", "state"] {
            #expect(!found.contains(forbidden), "clave prohibida: \(forbidden)")
        }
        #expect(found.contains("links"))
        let back = try JSONDecoder().decode(LedgerState.self, from: data)
        #expect(back == l.state)
        l.setLink(.rev, nil)
        #expect(l.state.links[.rev] == nil)
    }
}
