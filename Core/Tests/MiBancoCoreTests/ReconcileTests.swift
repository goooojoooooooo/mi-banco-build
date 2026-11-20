import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

/// Fecha de 2026 en hora de Madrid.
private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = minute; c.second = second
    return madrid.date(from: c)!
}

private func record(
    _ ref: String, _ cents: Int, _ timing: RecordTiming, status: BankStatus = .booked, merchant: String? = nil,
    isShop: Bool = false, bank: BankID = .rev
) -> BankRecord {
    BankRecord(ref: ref, bank: bank, amountCents: cents, timing: timing, status: status, merchant: merchant, isShop: isShop)
}

private func captured(_ cents: Int, _ date: Date, merchant: String? = "Mercadona", source: Movement.Source = .notification) -> Movement {
    Movement(bank: .rev, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income, source: source,
             date: date, fingerprint: "fp\(cents)\(date.timeIntervalSince1970)")
}

private func ledger(_ movements: [Movement] = []) -> Ledger {
    Ledger(state: LedgerState(movements: movements))
}

private func run(
    _ l: inout Ledger, _ records: [BankRecord], channel: RecordChannel = .bank, coverage: DateInterval? = nil,
    now: Date = at(11, 20, 12)
) -> ReconcileReport {
    l.reconcile(records, bank: .rev, channel: channel, coverage: coverage, now: now, calendar: madrid)
}

private func tx(
    _ cents: String, _ indicator: String = "DBIT", status: EBTransactionStatus = .book, currency: String = "EUR",
    txDate: String? = "2026-11-18", booking: String? = nil, creditor: String? = nil, debtor: String? = nil,
    mcc: String? = nil, remittance: [String]? = nil, entry: String? = nil, id: String? = nil
) -> EBTransaction {
    EBTransaction(
        transactionAmount: EBAmount(currency: currency, amount: cents), creditDebitIndicator: indicator, status: status,
        entryReference: entry, transactionID: id, bookingDate: booking, transactionDate: txDate,
        remittanceInformation: remittance, creditor: creditor.map { EBParty(name: $0) },
        debtor: debtor.map { EBParty(name: $0) }, merchantCategoryCode: mcc)
}

@Suite struct ReconcileTests {
    @Test func linksCapturedToBookedRecord() {
        var l = ledger([captured(-1250, at(11, 18, 13, 5))])
        let r = record("t1", -1250, .transactionDay(at(11, 18)), merchant: "Mercadona Valencia")
        let report = run(&l, [r])
        #expect(report.linked == 1)
        #expect(report.added == 0)
        #expect(l.state.movements.count == 1)
        let m = l.state.movements[0]
        #expect(m.merchant == "Mercadona")
        #expect(m.bankRef == "t1")
        #expect(m.bankStatus == .booked)
        #expect(m.importedAt == nil)
        #expect(m.isHistorical == false)
    }

    /// R9: vincular nunca cambia `merchant` (de él salen categorías, silenciados y suscripciones).
    @Test func linkingNeverChangesTheMerchantKey() {
        var l = ledger([captured(-1250, at(11, 18, 13, 5), merchant: "Mercadona"), captured(-700, at(11, 18, 9, 0), merchant: nil)])
        let before = l.state.movements.map { normalizeMerchant($0.merchant ?? "") }
        _ = run(&l, [
            record("a", -1250, .transactionDay(at(11, 18)), merchant: "Supermercados Valencia SL"),
            record("b", -700, .transactionDay(at(11, 18)), merchant: "Zara"),
        ])
        #expect(l.state.movements.map { normalizeMerchant($0.merchant ?? "") } == before)
        #expect(l.state.movements[0].merchant == "Mercadona")
        #expect(l.state.movements[0].bankMerchant == "Supermercados Valencia SL")
        #expect(l.state.movements[1].merchant == nil)
        #expect(l.state.movements[1].bankMerchant == "Zara")
        #expect(l.state.movements[1].displayMerchant == "Zara")
        #expect(l.state.movements[0].displayMerchant == "Mercadona")
        // Y al volver a descargar no cambia nada.
        let again = run(&l, [
            record("a", -1250, .transactionDay(at(11, 18)), merchant: "Supermercados Valencia SL"),
            record("b", -700, .transactionDay(at(11, 18)), merchant: "Zara"),
        ])
        #expect(again.unchanged == 2)
        #expect(again.updated == 0)
    }

    @Test func refetchIsIdempotent() {
        var l = ledger([captured(-1250, at(11, 18, 13, 5))])
        let r = record("t1", -1250, .transactionDay(at(11, 18)), merchant: "Mercadona Valencia")
        _ = run(&l, [r])
        let state = l.state
        let report = run(&l, [r])
        #expect(report == ReconcileReport(unchanged: 1))
        #expect(l.state == state)
    }

    @Test func refetchOfAddedRecordIsIdempotent() {
        var l = ledger()
        let r = record("t1", -1250, .transactionDay(at(11, 18)), merchant: "Zara")
        let first = run(&l, [r])
        #expect(first.added == 1)
        #expect(first.addedIDs.count == 1)
        let state = l.state
        #expect(run(&l, [r]) == ReconcileReport(unchanged: 1))
        #expect(l.state == state)
        let m = l.state.movements[0]
        #expect(m.source == .bank)
        #expect(m.dayOnly)
        #expect(m.date == at(11, 18))
        #expect(m.importedAt == at(11, 20, 12))
        #expect(m.kind == .payment)
        #expect(m.merchant == "Zara")
    }

    @Test func twoEqualCoffeesLinkOneToOne() {
        var l = ledger([captured(-120, at(11, 18, 9, 0)), captured(-120, at(11, 18, 9, 30))])
        let report = run(&l, [
            record("c1", -120, .transactionDay(at(11, 18))),
            record("c2", -120, .transactionDay(at(11, 18))),
        ])
        #expect(report.linked == 2)
        #expect(report.added == 0)
        #expect(l.state.movements.count == 2)
        #expect(Set(l.state.movements.compactMap(\.bankRef)) == ["c1", "c2"])
    }

    @Test func pendingBecomesBookedInPlace() {
        var l = ledger()
        let first = run(&l, [record("p1", -4999, .transactionDay(at(11, 19)), status: .pending)],
                        coverage: DateInterval(start: at(11, 1, 0), end: at(11, 20, 0)))
        #expect(first.added == 1)
        let second = run(&l, [record("b1", -4999, .bookingDay(at(11, 21)))],
                         coverage: DateInterval(start: at(11, 1, 0), end: at(11, 22, 0)), now: at(11, 22, 12))
        #expect(second.updated == 1)
        #expect(second.removed == 0)
        #expect(second.added == 0)
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements[0].bankRef == "b1")
        #expect(l.state.movements[0].bankStatus == .booked)
    }

    @Test func pendingStillInTheBatchIsNotRekeyed() {
        var l = ledger()
        _ = run(&l, [record("p1", -4999, .transactionDay(at(11, 19)), status: .pending)])
        // Otro cobro igual, ya apuntado, mientras el pendiente sigue ahí: son dos.
        let report = run(&l, [
            record("p1", -4999, .transactionDay(at(11, 19)), status: .pending),
            record("b9", -4999, .bookingDay(at(11, 20))),
        ])
        #expect(report.added == 1)
        #expect(l.state.movements.count == 2)
    }

    @Test func cancelledPendingIsRemoved() {
        var l = ledger()
        _ = run(&l, [record("p1", -4999, .transactionDay(at(11, 19)), status: .pending)],
                coverage: DateInterval(start: at(11, 1, 0), end: at(11, 20, 0)))
        let report = run(&l, [], coverage: DateInterval(start: at(11, 1, 0), end: at(11, 22, 0)))
        #expect(report.removed == 1)
        #expect(l.state.movements.isEmpty)
    }

    @Test func pendingOutsideCoverageStays() {
        var l = ledger()
        _ = run(&l, [record("p1", -4999, .transactionDay(at(11, 19)), status: .pending)])
        let report = run(&l, [], coverage: DateInterval(start: at(11, 20, 0), end: at(11, 22, 0)))
        #expect(report.removed == 0)
        #expect(l.state.movements.count == 1)
    }

    @Test func capturedLinkedToVanishedPendingStays() {
        var l = ledger([captured(-4999, at(11, 19, 10, 0))])
        let first = run(&l, [record("p1", -4999, .transactionDay(at(11, 19)), status: .pending)])
        #expect(first.linked == 1)
        #expect(l.state.movements[0].bankStatus == .pending)
        let second = run(&l, [], coverage: DateInterval(start: at(11, 1, 0), end: at(11, 22, 0)))
        #expect(second.removed == 0)
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements[0].bankRef == nil)
        #expect(l.state.movements[0].bankStatus == nil)
    }

    /// R10: un pago en divisa o con propina que no casa deja dos filas; el capturado queda «sin confirmar».
    /// R8: el registro del banco va a mediodía; el capturado de las 10:00 del mismo día cuenta por día, no por hora.
    @Test func foreignCurrencyStaysUnconfirmed() {
        let cap = captured(-550, at(11, 10, 10, 0))
        var l = ledger([cap, captured(-300, at(11, 15, 10, 0))])
        let report = run(&l, [record("r1", -507, .transactionDay(at(11, 10)))], now: at(11, 20, 10))
        #expect(report.added == 1)
        #expect(report.linked == 0)
        #expect(l.state.movements.count == 3)
        var info = BankLinkInfo(connectedAt: at(11, 1), consentValidUntil: at(12, 20))
        info.lastSuccessAt = at(11, 20, 10)
        l.setLink(.rev, info)
        #expect(l.unconfirmedCaptures(bank: .rev, now: at(11, 20, 10)) == [cap.id])
    }

    @Test func unconfirmedNeedsALink() {
        let cap = captured(-550, at(11, 10, 10, 0))
        var l = ledger([cap])
        var info = BankLinkInfo(connectedAt: at(11, 1), consentValidUntil: at(12, 20))
        info.lastSuccessAt = at(11, 20, 10)
        l.setLink(.rev, info)
        // Sin ningún movimiento con clave del banco no hay desde cuándo mirar.
        #expect(l.unconfirmedCaptures(bank: .rev, now: at(11, 20, 10)).isEmpty)
        // Un capturado anterior al primer registro del banco no se reclama.
        _ = run(&l, [record("r1", -999, .transactionDay(at(11, 12)))])
        #expect(l.unconfirmedCaptures(bank: .rev, now: at(11, 20, 10)).isEmpty)
        // Sin conexión con éxito, nada.
        l.setLink(.rev, nil)
        #expect(l.unconfirmedCaptures(bank: .rev, now: at(11, 20, 10)).isEmpty)
    }

    @Test func bookingWindow() {
        var near = ledger([captured(-1250, at(11, 14, 10, 0))])
        let r = record("t1", -1250, .bookingDay(at(11, 18)))
        #expect(run(&near, [r]).linked == 1)
        var far = ledger([captured(-1250, at(11, 12, 10, 0))])
        let report = run(&far, [r])
        #expect(report.added == 1)
        #expect(report.linked == 0)
        #expect(far.state.movements.count == 2)
    }

    @Test func exactWindow() {
        let r = record("s1", -1250, .exact(at(11, 18, 13, 5, 11)))
        var close = ledger([captured(-1250, at(11, 18, 13, 6))])
        #expect(run(&close, [r], channel: .statement).linked == 1)
        #expect(close.state.movements[0].statementRef == "s1")
        var far = ledger([captured(-1250, at(11, 20, 8, 0))])
        #expect(run(&far, [r], channel: .statement).added == 1)
        #expect(far.state.movements.count == 2)
        #expect(far.state.movements[1].dayOnly == false)
        #expect(far.state.movements[1].source == .statement)
    }

    /// R28: un capturado enlaza con un registro de solo día si su día de Madrid está a ±1 día del del registro.
    @Test func transactionDayLinksWithinOneDay() {
        let r = record("t1", -1250, .transactionDay(at(11, 18)))
        var nextMorning = ledger([captured(-1250, at(11, 19, 10, 0))])
        #expect(run(&nextMorning, [r]).linked == 1)
        var justAfterMidnight = ledger([captured(-1250, at(11, 19, 0, 20))])
        #expect(run(&justAfterMidnight, [r]).linked == 1)
        var earlyBefore = ledger([captured(-1250, at(11, 17, 15, 0))])
        #expect(run(&earlyBefore, [r]).linked == 1)
        var twoDays = ledger([captured(-1250, at(11, 20, 10, 0))])
        #expect(run(&twoDays, [r]).added == 1)
    }

    @Test func captureLinksToARecordDatedTheNextDayWhenNothingIsCloser() {
        // El banco da como fecha el día de liquidación (D+1).
        var l = ledger([captured(-1250, at(11, 18, 20, 0))])
        let report = run(&l, [record("t1", -1250, .transactionDay(at(11, 19)))])
        #expect(report.linked == 1)
        #expect(report.added == 0)
        #expect(l.state.movements.count == 1)
    }

    @Test func sameDayCandidateWinsOverNeighbouringDay() {
        let near = captured(-1250, at(11, 18, 20, 0))
        let far = captured(-1250, at(11, 19, 9, 0))
        var l = ledger([far, near])
        _ = run(&l, [record("t1", -1250, .transactionDay(at(11, 18)))])
        let linked = l.state.movements.filter { $0.bankRef == "t1" }
        #expect(linked.count == 1)
        #expect(linked[0].id == near.id)
    }

    /// R29: pendiente y apuntado del mismo pago en un lote no acaban como dos movimientos.
    @Test func pendingAndBookedInOneBatchEndAsOneMovement() {
        let capture = captured(-1250, at(11, 18, 10, 5))
        var l = ledger([capture])
        let day = RecordTiming.transactionDay(at(11, 18))
        let coverage = DateInterval(start: at(11, 10, 0), end: at(11, 20, 0))
        let pending = record("p1", -1250, day, status: .pending)
        let booked = record("b1", -1250, day, status: .booked, merchant: "Mercadona Valencia")
        _ = run(&l, [pending, booked], coverage: coverage)
        _ = run(&l, [booked], coverage: coverage)
        #expect(l.state.movements.count == 1)
        let m = l.state.movements[0]
        #expect(m.id == capture.id)
        #expect(m.merchant == capture.merchant)
        #expect(m.date == capture.date)
        #expect(m.bankRef == "b1")
        #expect(m.bankStatus == .booked)
        #expect(m.bankMerchant == "Mercadona Valencia")
        let before = l.state
        let third = run(&l, [booked], coverage: coverage)
        #expect(l.state == before)
        #expect(third.added == 0 && third.removed == 0)
    }

    /// R32 (R29): solo se funde con una fila apuntada que viene en el lote actual; una de otra consulta no es su pareja.
    @Test func foldOnlyUsesBookedRowFromCurrentBatch() {
        let capture = captured(-1250, at(11, 18, 10, 5))
        var l = ledger([capture])
        let day = RecordTiming.transactionDay(at(11, 18))
        let coverage = DateInterval(start: at(11, 10, 0), end: at(11, 20, 0))
        _ = run(&l, [record("p1", -1250, day, status: .pending)], coverage: coverage)
        // Otra fila apuntada del mismo importe llegó en una consulta anterior y no vuelve en este lote.
        var other = Movement(bank: .rev, amountCents: -1250, merchant: "Otro", kind: .payment, source: .bank,
                             date: at(11, 18), bankRef: "old-b", bankStatus: .booked, importedAt: at(11, 19), dayOnly: true)
        other.id = UUID()
        l.state.movements.append(other)
        let report = run(&l, [], coverage: coverage)
        #expect(report.removed == 0)
        #expect(l.state.movements.count == 2)
        let kept = l.state.movements.first { $0.id == capture.id }
        #expect(kept?.bankRef == nil)
        #expect(l.state.movements.contains { $0.id == other.id })
    }

    /// Un renombrado del banco que cambia la clave del comercio no pierde la categoría «para todo el comercio» de la clave
    /// antigua.
    @Test func renameByBankKeepsMerchantWideCategoryOnTheMovement() {
        let oldName = "Zxq Shop Centro"
        let row = Movement(bank: .rev, amountCents: -700, merchant: oldName, kind: .payment, source: .bank,
                           date: at(11, 18), bankRef: "t1", bankStatus: .booked, importedAt: at(11, 19), dayOnly: true)
        var l = Ledger(state: LedgerState(movements: [row], categoryOverrides: [normalizeMerchant(oldName): .ocio]))
        let report = run(&l, [record("t1", -700, .transactionDay(at(11, 18)), merchant: "Zxq")])
        #expect(report.updated == 1)
        #expect(l.state.movements[0].merchant == "Zxq")
        #expect(l.state.movements[0].category == .ocio)
        #expect(categoryOf(l.state.movements[0], in: l.state, subscriptionKeys: []) == .ocio)
    }

    @Test func statementAfterApiAddsNothing() {
        var l = ledger()
        _ = run(&l, [record("t1", -1250, .transactionDay(at(11, 18)), merchant: "Zara")])
        let report = run(&l, [record("row1", -1250, .transactionDay(at(11, 18)))], channel: .statement)
        #expect(report.linked == 1)
        #expect(report.added == 0)
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements[0].bankRef == "t1")
        #expect(l.state.movements[0].statementRef == "row1")
        #expect(l.state.movements[0].source == .bank)
        let again = run(&l, [record("row1", -1250, .transactionDay(at(11, 18)))], channel: .statement)
        #expect(again == ReconcileReport(unchanged: 1))
    }

    @Test func otherBankIsNeverMatched() {
        var l = ledger([captured(-1250, at(11, 18, 13, 5))])
        let report = l.reconcile([record("t1", -1250, .transactionDay(at(11, 18)), bank: .ima)], bank: .ima, channel: .bank,
                                 coverage: nil, now: at(11, 20), calendar: madrid)
        #expect(report.added == 1)
        #expect(report.linked == 0)
    }

    @Test func historyProducesNoInsights() {
        let now = at(11, 20, 12)
        var records: [BankRecord] = []
        for i in 0..<37 {
            records.append(record("h\(i)", -(500 + i * 7), .transactionDay(at(11, 20).addingTimeInterval(-Double(i + 3) * 1.6 * 86_400)),
                                  merchant: "Comercio \(i % 9)"))
        }
        records.append(record("big", -30_000, .transactionDay(at(11, 17)), merchant: "Mediamarkt"))
        records.append(record("n1", -999, .exact(at(10, 31, 20, 0)), merchant: "Netflix"))
        records.append(record("n2", -999, .exact(at(10, 31, 20, 5)), merchant: "Netflix"))
        #expect(records.count == 40)
        var l = ledger()
        let report = run(&l, records, now: now)
        #expect(report.added == 40)
        let forbidden: Set<InsightKind> = [.largePayment, .unusualPayment, .duplicateCharge]
        #expect(insights(for: l.state, now: now, calendar: madrid).filter { forbidden.contains($0.kind) }.isEmpty)
        #expect(l.state.movements.allSatisfy { $0.isHistorical == ($0.date < now.addingTimeInterval(-48 * 3600)) })

        // Un pago nuevo (no histórico) sí entra en el feed.
        _ = run(&l, [record("new", -20_000, .transactionDay(at(11, 19)), merchant: "Muebles")], now: now)
        let large = insights(for: l.state, now: now, calendar: madrid).filter { $0.kind == .largePayment }
        #expect(large.count == 1)
    }

    // MARK: bankRecords

    @Test func bankRecordsMapping() {
        let list = [
            tx("12.50", creditor: "MERCADONA", mcc: "5411"),
            tx("35.00", "CRDT", status: .pdng, txDate: nil, booking: "2026-11-18", debtor: "CARLOS"),
            tx("1.00", status: .cncl),
            tx("5.00", mcc: "4829", remittance: ["BIZUM A LAURA"]),
            tx("3.00", currency: "USD"),
        ]
        let out = bankRecords(from: list, bank: .rev, calendar: madrid)
        #expect(out.count == 3)
        #expect(out[0].amountCents == -1250)
        #expect(out[0].isShop)
        #expect(out[0].timing == .transactionDay(at(11, 18)))
        #expect(out[0].status == .booked)
        #expect(out[0].merchant == "Mercadona")
        #expect(out[1].amountCents == 3500)
        #expect(out[1].status == .pending)
        #expect(out[1].isShop == false)
        #expect(out[1].timing == .bookingDay(at(11, 18)))
        #expect(out[2].amountCents == -500)
        #expect(out[2].isShop == false)
        #expect(out[2].merchant == "Bizum a Laura")
    }

    @Test func statusMapping() {
        let statuses: [(EBTransactionStatus, BankStatus?)] = [
            (.book, .booked), (.othr, .booked), (.pdng, .pending), (.hold, .pending),
            (.cncl, nil), (.rjct, nil), (.schd, nil),
        ]
        for (eb, expected) in statuses {
            let out = bankRecords(from: [tx("1.00", status: eb)], bank: .rev, calendar: madrid)
            #expect(out.first?.status == expected)
            #expect(out.count == (expected == nil ? 0 : 1))
        }
    }

    @Test func timingPrefersTransactionThenBookingThenValueDate() {
        func timing(_ t: EBTransaction) -> RecordTiming? { bankRecords(from: [t], bank: .rev, calendar: madrid).first?.timing }
        #expect(timing(tx("1.00", txDate: "2026-11-18", booking: "2026-11-19")) == .transactionDay(at(11, 18)))
        #expect(timing(tx("1.00", txDate: nil, booking: "2026-11-19")) == .bookingDay(at(11, 19)))
        let valueOnly = EBTransaction(transactionAmount: EBAmount(currency: "EUR", amount: "1.00"), creditDebitIndicator: "DBIT",
                                      status: .book, valueDate: "2026-11-17")
        #expect(timing(valueOnly) == .bookingDay(at(11, 17)))
        #expect(timing(tx("1.00", txDate: nil)) == nil)
        #expect(timing(tx("1.00", txDate: "no-es-fecha")) == nil)
    }

    @Test func refsAreStableAndSyntheticOnesCountDuplicates() {
        let a = tx("2.00", remittance: ["CAFE"])
        let out = bankRecords(from: [a, a], bank: .rev, calendar: madrid)
        #expect(out.count == 2)
        #expect(out[0].ref.hasPrefix("s|") && out[0].ref.hasSuffix("|0"))
        #expect(out[1].ref.hasPrefix("s|") && out[1].ref.hasSuffix("|1"))
        #expect(out[0].ref != out[1].ref)
        #expect(bankRecords(from: [a, a], bank: .rev, calendar: madrid) == out)
        let other = bankRecords(from: [tx("2.01", remittance: ["CAFE"])], bank: .rev, calendar: madrid)
        #expect(other[0].ref != out[0].ref)
        let named = bankRecords(from: [tx("2.00", entry: "E1", id: "T1"), tx("2.00", id: "T2"), tx("2.00", entry: "")], bank: .rev,
                                calendar: madrid)
        #expect(named.map(\.ref).prefix(2) == ["E1", "T2"])
        #expect(named[2].ref.hasPrefix("s|"))
    }

    @Test func shopRules() {
        func shop(_ t: EBTransaction) -> Bool? { bankRecords(from: [t], bank: .rev, calendar: madrid).first?.isShop }
        #expect(shop(tx("1.00", creditor: "Algo Raro", mcc: "5812")) == true)
        #expect(shop(tx("1.00", creditor: "Carlos", mcc: "6010")) == false)
        #expect(shop(tx("1.00", creditor: "Netflix")) == true)
        #expect(shop(tx("1.00", creditor: "Carlos Perez")) == false)
        #expect(shop(tx("1.00", "CRDT", debtor: "Netflix", mcc: "5411")) == false)
    }

    /// Una divisa que no es EUR nunca se casa ni se cuenta.
    @Test func nonEuroRecordIsNeverMatchedOrCounted() {
        let usd = tx("12.50", currency: "USD", creditor: "Mercadona")
        #expect(usd.signedCents == nil)
        #expect(bankRecords(from: [usd], bank: .rev, calendar: madrid).isEmpty)
        var l = ledger([captured(-1250, at(11, 18, 13, 5))])
        let report = run(&l, bankRecords(from: [usd], bank: .rev, calendar: madrid))
        #expect(report == ReconcileReport())
        #expect(l.state.movements.count == 1)
        #expect(l.state.movements[0].bankRef == nil)
    }
}
