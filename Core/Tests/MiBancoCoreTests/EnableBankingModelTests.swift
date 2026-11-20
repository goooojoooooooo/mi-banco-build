import Foundation
import Testing
@testable import MiBancoCore

@Suite struct EnableBankingModelTests {
    @Test(arguments: [
        ("12.50", 1250), ("12.5", 1250), ("-1234.56", -123456), ("0.01", 1),
        ("1234", 123400), ("12.500", 1250),
    ])
    func aceptaDecimalesDeLaAPI(_ raw: String, _ cents: Int) {
        #expect(centsFromDecimalString(raw) == cents)
    }

    @Test(arguments: ["12,50", "1.234.56", "", "12.505", "abc"])
    func rechazaLoQueNoEsDeLaAPI(_ raw: String) {
        #expect(centsFromDecimalString(raw) == nil)
    }

    private func decodeTx(_ json: String) throws -> EBTransaction {
        try JSONDecoder().decode(EBTransaction.self, from: Data(json.utf8))
    }

    @Test func signedCents() throws {
        let base = #"{"transaction_amount":{"currency":"EUR","amount":"12.50"},"credit_debit_indicator":"DBIT","status":"BOOK"}"#
        #expect(try decodeTx(base).signedCents == -1250)
        let credit = base.replacingOccurrences(of: "DBIT", with: "CRDT")
        #expect(try decodeTx(credit).signedCents == 1250)
        let negative = base.replacingOccurrences(of: "\"12.50\"", with: "\"-12.50\"")
        #expect(try decodeTx(negative).signedCents == -1250)
    }

    @Test func signedCentsIgnoresNonEuro() throws {
        let usd = #"{"transaction_amount":{"currency":"USD","amount":"12.50"},"credit_debit_indicator":"DBIT","status":"BOOK"}"#
        #expect(try decodeTx(usd).signedCents == nil)
        let lower = usd.replacingOccurrences(of: "USD", with: "eur")
        #expect(try decodeTx(lower).signedCents == -1250)
        #expect(EBAmount(currency: "GBP", amount: "1.00").euroCents == nil)
        #expect(EBAmount(currency: "EUR", amount: "1.00").euroCents == 100)
    }

    @Test func decodesTolerantly() throws {
        let json = #"{"transaction_amount":{"currency":"EUR","amount":"1.00"},"credit_debit_indicator":"CRDT","status":"ZZZZ","algo_nuevo":{"x":1},"otro":[1,2]}"#
        let tx = try decodeTx(json)
        #expect(tx.status == .othr)
        #expect(tx.entryReference == nil)
        #expect(tx.remittanceInformation == nil)
        #expect(tx.creditor == nil)
    }

    @Test func decodesFullTransaction() throws {
        let json = #"""
        {"entry_reference":"e1","transaction_id":"t1",
         "transaction_amount":{"currency":"EUR","amount":"3.20"},
         "credit_debit_indicator":"DBIT","status":"PDNG",
         "booking_date":"2026-11-19","value_date":"2026-11-19","transaction_date":"2026-11-18",
         "remittance_information":["Cafe Prueba"],"creditor":{"name":"Cafe Prueba"},
         "debtor":{"name":null},"merchant_category_code":"5812",
         "balance_after_transaction":{"currency":"EUR","amount":"96.80"}}
        """#
        let tx = try decodeTx(json)
        #expect(tx.entryReference == "e1")
        #expect(tx.transactionID == "t1")
        #expect(tx.status == .pdng)
        #expect(tx.bookingDate == "2026-11-19")
        #expect(tx.transactionDate == "2026-11-18")
        #expect(tx.remittanceInformation == ["Cafe Prueba"])
        #expect(tx.creditor?.name == "Cafe Prueba")
        #expect(tx.debtor?.name == nil)
        #expect(tx.merchantCategoryCode == "5812")
        #expect(tx.balanceAfterTransaction?.amount == "96.80")
    }

    @Test func transactionRoundTripsWithSnakeCase() throws {
        let tx = EBTransaction(
            transactionAmount: EBAmount(currency: "EUR", amount: "1.00"),
            creditDebitIndicator: "CRDT", status: .book, transactionID: "t9")
        let data = try JSONEncoder().encode(tx)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"transaction_id\""))
        #expect(try JSONDecoder().decode(EBTransaction.self, from: data) == tx)
    }

    @Test func sessionDropsIBAN() throws {
        let json = #"{"session_id":"s-1","accounts":[{"uid":"u-1","account_id":{"iban":"XX00TEST"},"currency":"EUR","cash_account_type":"CACC"}],"access":{"valid_until":"2027-05-19T10:00:00.000000+00:00"}}"#
        let session = try JSONDecoder().decode(EBSession.self, from: Data(json.utf8))
        #expect(session.sessionID == "s-1")
        #expect(session.accounts[0].uid == "u-1")
        #expect(session.accounts[0].cashAccountType == "CACC")
        #expect(session.validUntil == Date(timeIntervalSince1970: 1810720800))
        let reencoded = try JSONEncoder().encode(session.accounts)
        #expect(!String(decoding: reencoded, as: UTF8.self).contains("XX00TEST"))
    }

    @Test(arguments: [
        "2027-05-19T10:00:00+00:00", "2027-05-19T10:00:00Z", "2027-05-19T12:00:00.5+02:00",
        "2027-05-19T10:00:00.123456Z",
    ])
    func sessionParsesISOVariants(_ stamp: String) throws {
        let json = #"{"session_id":"s","accounts":[],"access":{"valid_until":""# + stamp + #""}}"#
        let session = try JSONDecoder().decode(EBSession.self, from: Data(json.utf8))
        #expect(session.validUntil?.timeIntervalSince1970.rounded(.down) == 1810720800)
    }

    @Test func sessionWithoutAccessHasNoValidUntil() throws {
        let json = #"{"session_id":"s","accounts":[]}"#
        let session = try JSONDecoder().decode(EBSession.self, from: Data(json.utf8))
        #expect(session.validUntil == nil)
    }

    @Test func aspspDecodes() throws {
        let json = #"{"name":"Revolut","country":"ES","maximum_consent_validity":15552000,"required_psu_headers":["psu-ip-address"],"logo":"x"}"#
        let a = try JSONDecoder().decode(EBASPSP.self, from: Data(json.utf8))
        #expect(a.name == "Revolut")
        #expect(a.maximumConsentValidity == 15_552_000)
        #expect(a.requiredPSUHeaders == ["psu-ip-address"])
    }

    @Test func balanceDecodes() throws {
        let json = #"{"name":"Principal","balance_amount":{"currency":"EUR","amount":"100.00"},"balance_type":"CLBD","last_change_date_time":"2026-11-20T10:00:00Z"}"#
        let b = try JSONDecoder().decode(EBBalance.self, from: Data(json.utf8))
        #expect(b.balanceType == "CLBD")
        #expect(b.balanceAmount.amount == "100.00")
        #expect(b.lastChangeDateTime == "2026-11-20T10:00:00Z")
    }

    private func classify(_ status: Int, _ body: String) -> SyncProblem {
        classifyEnableBankingError(status: status, body: Data(body.utf8))
    }

    @Test(arguments: ["EXPIRED_SESSION", "REVOKED_SESSION", "CLOSED_SESSION", "SESSION_DOES_NOT_EXIST"])
    func sessionErrorsMeanConsentExpired(_ code: String) {
        let body = #"{"message":"x","code":401,"error":""# + code + #""}"#
        #expect(classify(401, body) == .consentExpired)
        #expect(classify(404, body) == .consentExpired)
    }

    @Test func classifiesSessionErrors() {
        #expect(classify(401, #"{"error":"EXPIRED_SESSION"}"#) == .consentExpired)
        #expect(classify(403, #"{"error":"REVOKED_SESSION"}"#) == .consentExpired)
        #expect(classify(403, #"{"error":"CLOSED_SESSION"}"#) == .consentExpired)
        #expect(classify(404, #"{"error":"SESSION_DOES_NOT_EXIST"}"#) == .consentExpired)
        #expect(classify(429, "{}") == .rateLimited)
        #expect(classify(422, #"{"error":"ASPSP_RATE_LIMIT_EXCEEDED"}"#) == .rateLimited)
        #expect(classify(500, "<html>") == .bankUnavailable)
        #expect(classify(408, #"{"error":"ASPSP_TIMEOUT"}"#) == .bankUnavailable)
        #expect(classify(400, #"{"error":"ASPSP_ERROR"}"#) == .bankUnavailable)
        #expect(classify(401, #"{"error":"UNAUTHORIZED_ACCESS"}"#) == .keyRejected)
        #expect(classify(401, "{}") == .keyRejected)
        #expect(classify(400, #"{"error":"WRONG_REQUEST_PARAMETERS"}"#) == .unknown)
    }

    @Test func nonJSONBodyFallsBackToStatus() {
        #expect(classify(401, "nope") == .keyRejected)
        #expect(classify(429, "") == .rateLimited)
        #expect(classify(503, "<html>") == .bankUnavailable)
        #expect(classify(418, "") == .unknown)
    }

    @Test func errorCodeWinsOverStatus() {
        #expect(classify(500, #"{"error":"EXPIRED_SESSION"}"#) == .consentExpired)
        #expect(classify(401, #"{"error":"ASPSP_RATE_LIMIT_EXCEEDED"}"#) == .rateLimited)
    }
}
