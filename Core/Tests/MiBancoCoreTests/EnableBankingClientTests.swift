import Foundation
import Testing
@testable import MiBancoCore

private struct FakeSigner: JWTSigner {
    func signRS256(_ message: Data) throws -> Data { Data([1, 2, 3]) }
}

private enum Reply: Sendable {
    case json(Int, String)
    case fail(URLError.Code)
}

/// Guarda las peticiones y responde desde una cola; si se acaba, repite `fallback`.
private actor FixtureTransport: HTTPTransport {
    private var queue: [Reply]
    private let fallback: Reply?
    private(set) var requests: [HTTPRequest] = []

    init(_ queue: [Reply], fallback: Reply? = nil) {
        self.queue = queue
        self.fallback = fallback
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        let reply = queue.isEmpty ? (fallback ?? .json(500, "{}")) : queue.removeFirst()
        switch reply {
        case let .json(status, body): return HTTPResponse(status: status, body: Data(body.utf8))
        case let .fail(code): throw URLError(code)
        }
    }
}

private let appID = "00000000-0000-4000-8000-000000000001"
private let fixedNow = Date(timeIntervalSince1970: 1_795_172_400) // 2026-11-20T11:00:00Z

private func makeClient(_ transport: FixtureTransport) -> EnableBankingClient {
    EnableBankingClient(transport: transport, signer: FakeSigner(), appID: appID, now: { fixedNow })
}

private func tx(_ id: String) -> String {
    #"{"transaction_id":""# + id + #"","transaction_amount":{"currency":"EUR","amount":"1.00"},"credit_debit_indicator":"DBIT","status":"BOOK"}"#
}

@Suite struct EnableBankingClientTests {
    @Test func fixedNowIsTheExpectedInstant() {
        let f = ISO8601DateFormatter()
        #expect(f.date(from: "2026-11-20T11:00:00Z") == fixedNow)
    }

    @Test func sendsJWTAndNoPSUHeaders() async throws {
        let transport = FixtureTransport([.json(200, #"{"balances":[]}"#)])
        _ = try await makeClient(transport).balances(accountUID: "u-1")
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(Set(request.headers.keys) == ["Accept", "Authorization", "Content-Type"])
        let auth = try #require(request.headers["Authorization"])
        #expect(auth.hasPrefix("Bearer "))
        #expect(auth.hasSuffix(".AQID"))
        #expect(!request.headers.keys.contains { $0.lowercased().hasPrefix("psu-") })
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://api.enablebanking.com/accounts/u-1/balances")
    }

    @Test func jwtExpiresIn300Seconds() async throws {
        let transport = FixtureTransport([.json(200, #"{"balances":[]}"#)])
        _ = try await makeClient(transport).balances(accountUID: "u-1")
        let request = try #require(await transport.requests.first)
        let auth = try #require(request.headers["Authorization"])
        let jwt = String(auth.dropFirst("Bearer ".count))
        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3)
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        let payloadData = try #require(Data(base64Encoded: b64))
        let payload = try #require(try JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let iat = try #require(payload["iat"] as? Int)
        let exp = try #require(payload["exp"] as? Int)
        #expect(exp - iat == 300)
    }

    @Test func startAuthBody() async throws {
        let transport = FixtureTransport([.json(200, #"{"url":"https://bank.example/consent?x=1"}"#)])
        let aspsp = EBASPSP(name: "Revolut", country: "ES")
        let validUntil = Date(timeIntervalSince1970: 1_810_724_400) // 2027-05-19T11:00:00Z
        let url = try await makeClient(transport).startAuth(aspsp: aspsp, validUntil: validUntil, state: "st-1")
        #expect(url.absoluteString == "https://bank.example/consent?x=1")
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.enablebanking.com/auth")
        let expected = #"{"access":{"valid_until":"2027-05-19T11:00:00+00:00"},"aspsp":{"country":"ES","name":"Revolut"},"language":"es","psu_type":"personal","redirect_url":"https://goooojoooooooo.github.io/mi-banco-build/cb/","state":"st-1"}"#
        func canonical(_ data: Data) throws -> Data {
            let object = try JSONSerialization.jsonObject(with: data)
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        #expect(try canonical(try #require(request.body)) == canonical(Data(expected.utf8)))
    }

    @Test func startAuthRejectsNonHTTPSUrl() async {
        let transport = FixtureTransport([.json(200, #"{"url":"http://bank.example/x"}"#)])
        await #expect(throws: BankingClientError.badResponse) {
            _ = try await makeClient(transport).startAuth(
                aspsp: EBASPSP(name: "Revolut", country: "ES"), validUntil: fixedNow, state: "s")
        }
    }

    @Test func createSessionPostsCodeAndDecodes() async throws {
        let json = #"{"session_id":"s-1","accounts":[{"uid":"u-1","currency":"EUR","cash_account_type":"CACC"}],"access":{"valid_until":"2027-05-19T10:00:00Z"}}"#
        let transport = FixtureTransport([.json(200, json)])
        let session = try await makeClient(transport).createSession(code: "abc")
        #expect(session.sessionID == "s-1")
        #expect(session.accounts.map(\.uid) == ["u-1"])
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.url.absoluteString == "https://api.enablebanking.com/sessions")
        #expect(String(decoding: try #require(request.body), as: UTF8.self) == #"{"code":"abc"}"#)
    }

    @Test func aspspsQueryHasCountry() async throws {
        let json = #"{"aspsps":[{"name":"Revolut","country":"ES","maximum_consent_validity":15552000}]}"#
        let transport = FixtureTransport([.json(200, json)])
        let list = try await makeClient(transport).aspsps(country: "ES")
        #expect(list == [EBASPSP(name: "Revolut", country: "ES", maximumConsentValidity: 15_552_000)])
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.url.absoluteString == "https://api.enablebanking.com/aspsps?country=ES")
    }

    @Test func deleteSessionSendsDelete() async throws {
        let transport = FixtureTransport([.json(204, "")])
        try await makeClient(transport).deleteSession(id: "s-1")
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.method == "DELETE")
        #expect(request.url.absoluteString == "https://api.enablebanking.com/sessions/s-1")
    }

    @Test func followsContinuationKey() async throws {
        let page1 = #"{"transactions":["# + tx("t1") + "," + tx("t2") + #"],"continuation_key":"abc"}"#
        let page2 = #"{"transactions":["# + tx("t3") + #"],"continuation_key":null}"#
        let transport = FixtureTransport([.json(200, page1), .json(200, page2)])
        let all = try await makeClient(transport).transactions(
            accountUID: "u-1", dateFrom: "2025-11-20", strategy: .longest)
        #expect(all.map(\.transactionID) == ["t1", "t2", "t3"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url.query == "date_from=2025-11-20&strategy=longest")
        #expect(requests[1].url.query?.contains("continuation_key=abc") == true)
    }

    @Test func defaultStrategyUsesDefaultKeyword() async throws {
        let transport = FixtureTransport([.json(200, #"{"transactions":[]}"#)])
        _ = try await makeClient(transport).transactions(accountUID: "u-1", dateFrom: "2026-11-01", strategy: .standard)
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.url.query == "date_from=2026-11-01&strategy=default")
    }

    /// Páginas con claves distintas, para que solo el límite las pare.
    private func endlessPages(_ count: Int) -> [Reply] {
        (0..<count).map { .json(200, #"{"transactions":["# + tx("t\($0)") + #"],"continuation_key":"k\#($0)"}"#) }
    }

    @Test func stopsAfterMaxPages() async throws {
        let transport = FixtureTransport(endlessPages(60))
        await #expect(throws: BankingClientError.tooManyPages) {
            _ = try await makeClient(transport).transactions(
                accountUID: "u-1", dateFrom: "2025-11-20", strategy: .longest)
        }
        let sent = await transport.requests
        #expect(sent.count == 50)
    }

    @Test func pageLimitKeepsWhatWasFetched() async throws {
        let transport = FixtureTransport(endlessPages(60))
        let fetch = try await makeClient(transport).fetchTransactions(
            accountUID: "u-1", dateFrom: "2025-11-20", strategy: .longest)
        #expect(fetch.complete == false)
        #expect(fetch.transactions.count == 50)
        #expect(fetch.transactions.first?.transactionID == "t0")
        let sent = await transport.requests
        #expect(sent.count == 50)
    }

    @Test func repeatedContinuationKeyStopsAndKeepsWhatWasFetched() async throws {
        let page = #"{"transactions":["# + tx("t1") + #"],"continuation_key":"again"}"#
        let transport = FixtureTransport([], fallback: .json(200, page))
        let fetch = try await makeClient(transport).fetchTransactions(
            accountUID: "u-1", dateFrom: "2025-11-20", strategy: .longest)
        #expect(fetch.complete == false)
        #expect(fetch.transactions.count == 2)
        let sent = await transport.requests
        #expect(sent.count == 2)
    }

    @Test func completeFetchIsComplete() async throws {
        let transport = FixtureTransport([.json(200, #"{"transactions":["# + tx("t1") + #"]}"#)])
        let fetch = try await makeClient(transport).fetchTransactions(
            accountUID: "u-1", dateFrom: "2025-11-20", strategy: .standard)
        #expect(fetch == TransactionFetch(transactions: fetch.transactions, complete: true))
        #expect(fetch.transactions.count == 1)
    }

    @Test func networkFailureAfterSomePagesStillThrows() async {
        let page = #"{"transactions":["# + tx("t1") + #"],"continuation_key":"k1"}"#
        let transport = FixtureTransport([.json(200, page), .fail(.notConnectedToInternet)])
        await #expect(throws: BankingClientError.offline) {
            _ = try await makeClient(transport).fetchTransactions(
                accountUID: "u-1", dateFrom: "2025-11-20", strategy: .longest)
        }
    }

    @Test func mapsHTTPErrors() async {
        let expired = FixtureTransport([.json(401, #"{"message":"x","code":401,"error":"EXPIRED_SESSION"}"#)])
        await #expect(throws: BankingClientError.api(.consentExpired, code: "EXPIRED_SESSION")) {
            _ = try await makeClient(expired).balances(accountUID: "u")
        }
        let redirect = FixtureTransport([.json(400, #"{"error":"REDIRECT_URI_NOT_ALLOWED"}"#)])
        await #expect(throws: BankingClientError.api(.unknown, code: "REDIRECT_URI_NOT_ALLOWED")) {
            _ = try await makeClient(redirect).createSession(code: "x")
        }
        let html = FixtureTransport([.json(502, "<html>")])
        await #expect(throws: BankingClientError.api(.bankUnavailable, code: nil)) {
            _ = try await makeClient(html).balances(accountUID: "u")
        }
        let offline = FixtureTransport([.fail(.notConnectedToInternet)])
        await #expect(throws: BankingClientError.offline) {
            _ = try await makeClient(offline).balances(accountUID: "u")
        }
        let garbage = FixtureTransport([.json(200, "not json")])
        await #expect(throws: BankingClientError.badResponse) {
            _ = try await makeClient(garbage).balances(accountUID: "u")
        }
    }

    @Test func cancelledTransportIsCancellationNotOffline() async {
        let cancelled = FixtureTransport([.fail(.cancelled)])
        await #expect(throws: CancellationError.self) {
            _ = try await makeClient(cancelled).balances(accountUID: "u")
        }
    }

    @Test func nonASCIIIsPercentEscaped() async throws {
        let transport = FixtureTransport([.json(200, #"{"balances":[]}"#)])
        _ = try await makeClient(transport).balances(accountUID: "ñ٣é")
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.url.absoluteString == "https://api.enablebanking.com/accounts/%C3%B1%D9%A3%C3%A9/balances")
    }

    @Test func requestAndSessionDescriptionsAreRedacted() {
        let secretToken = "tok-SECRET-123"
        let secretQuery = "code=CODE-SECRET-9&state=STATE-SECRET-7"
        let request = HTTPRequest(
            method: "GET", url: URL(string: "https://api.example.test/p?" + secretQuery)!,
            headers: ["Authorization": "Bearer " + secretToken], body: Data("BODY-SECRET".utf8))
        let session = StoredSession(
            sessionID: "SESSION-SECRET-5", accountUIDs: ["UID-SECRET-6"], validUntil: fixedNow,
            aspspName: "Banco", aspspCountry: "ES")
        let pending = PendingAuth(
            state: "STATE-SECRET-7", bank: .rev, aspspName: "Banco", aspspCountry: "ES", startedAt: fixedNow)
        let secrets = ["SECRET", secretToken, "CODE", "STATE", "BODY", "SESSION", "UID", "Bearer", "?"]
        let texts = [
            String(describing: request), String(reflecting: request), "\(request)",
            String(describing: session), String(reflecting: session), "\(session)",
            String(describing: pending), String(reflecting: pending), "\(pending)",
        ]
        for text in texts {
            for secret in secrets { #expect(!text.contains(secret)) }
        }
        #expect(String(describing: request).contains("GET"))
        #expect(String(describing: session).contains("Banco"))
    }

    @Test func eachRequestGetsAFreshJWT() async throws {
        let transport = FixtureTransport([.json(200, #"{"balances":[]}"#), .json(200, #"{"balances":[]}"#)])
        let client = makeClient(transport)
        _ = try await client.balances(accountUID: "a")
        _ = try await client.balances(accountUID: "b")
        let requests = await transport.requests
        #expect(requests.count == 2)
        for r in requests { #expect(r.headers["Authorization"]?.hasPrefix("Bearer ") == true) }
    }

    @Test func accountUIDIsEscapedInThePath() async throws {
        let transport = FixtureTransport([.json(200, #"{"balances":[]}"#)])
        _ = try await makeClient(transport).balances(accountUID: "a/b c")
        let sent = await transport.requests
        let request = try #require(sent.first)
        #expect(request.url.absoluteString == "https://api.enablebanking.com/accounts/a%2Fb%20c/balances")
    }

    @Test func rejects3xxRedirectStatusWithoutFollowing() async {
        let transport = FixtureTransport([.json(302, "")])
        await #expect(throws: BankingClientError.api(.unknown, code: nil)) {
            _ = try await makeClient(transport).balances(accountUID: "u-1")
        }
    }

    @Test func responseByteLimitRejectsOversizedHeader() async {
        #expect(BankingConstants.maxResponseBytes == 10 * 1024 * 1024)
        let empty = AsyncStream<UInt8> { $0.finish() }
        await #expect(throws: CappedDownloadError.tooLarge) {
            _ = try await collectCapped(
                empty,
                expectedLength: Int64(BankingConstants.maxResponseBytes + 1),
                limit: BankingConstants.maxResponseBytes
            )
        }
    }
}
