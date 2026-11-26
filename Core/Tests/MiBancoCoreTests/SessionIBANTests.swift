import Foundation
import Testing
@testable import MiBancoCore

private struct IBANFakeSigner: JWTSigner {
    func signRS256(_ message: Data) throws -> Data { Data([1, 2, 3]) }
}

private actor IBANFixtureTransport: HTTPTransport {
    private var replies: [(Int, String)]
    private(set) var requests: [HTTPRequest] = []

    init(_ replies: [(Int, String)]) {
        self.replies = replies
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        let next = replies.isEmpty ? (500, "{}") : replies.removeFirst()
        return HTTPResponse(status: next.0, body: Data(next.1.utf8))
    }
}

@Suite struct SessionIBANTests {
    // Ejemplos públicos del estándar ISO 13616 / documentación (ningún dato real).
    private let esIBAN = "ES9121000418450200051332"
    private let esIBAN2 = "ES7921000813610123456789"
    private let ltIBAN = "LT121000011101001000"
    private let deIBAN = "DE89370400440532013000"
    private let gbIBAN = "GB82WEST12345698765432"
    private let frIBAN = "FR7630006000011234567890189"
    private let ieIBAN = "IE29AIBK93115212345678"

    // MARK: - Validación estricta de IBAN recibido de un banco

    @Test func validatesOfficialIBANsByCountryAndCheckDigits() {
        #expect(validatedBankIBAN("es91 2100 0418 4502 0005 1332") == esIBAN)
        #expect(validatedBankIBAN("ES91-2100-0418-4502-0005-1332") == esIBAN)
        #expect(validatedBankIBAN("lt12 1000 0111 0100 1000") == ltIBAN)
        #expect(validatedBankIBAN(deIBAN) == deIBAN)
        #expect(validatedBankIBAN(gbIBAN) == gbIBAN)
        #expect(validatedBankIBAN(frIBAN) == frIBAN)
        #expect(validatedBankIBAN(ieIBAN) == ieIBAN)
    }

    @Test(arguments: [
        "",
        "   ",
        "NO-ES-UN-IBAN",
        // Dígitos de control incorrectos (mod 97 != 1).
        "ES9221000418450200051332",
        "LT131000011101001000",
        // Dígitos de control prohibidos por ISO 13616 (00, 01, 99) aunque mod 97 sea 1.
        "ES0021000418450200051321",
        "ES0121000418450200051303",
        "ES9921000418450200051382",
        // Longitud incorrecta para el país aunque mod 97 sea 1 (LT debe ser 20, ES debe ser 24).
        "LT68100001110100100012",
        "ES982100041845020005133",
        "ES48210004184502000513321",
        // Código de país inexistente aunque mod 97 sea 1.
        "XX61ABCD1234567890ABCD1234567890AB",
        // Caracteres no permitidos en un IBAN bancario.
        "ES91@21000418450200051332",
        "esß91 2100 0418 4502 0005 1332",
        "ES91\n21000418450200051332",
    ])
    func rejectsInvalidBankIBANs(_ raw: String) {
        #expect(validatedBankIBAN(raw) == nil)
    }

    // MARK: - Extracción desde respuesta real de Enable Banking (POST /sessions)

    @Test func extractsIBANFromRealShapedSessionJSON() {
        let imaginJSON = #"""
        {
          "session_id": "sess-ima-1",
          "accounts": [
            {
              "uid": "acc-ima-eur",
              "account_id": { "iban": "es91 2100 0418 4502 0005 1332" },
              "all_account_ids": [
                { "identification": "ES9121000418450200051332", "scheme_name": "IBAN" }
              ],
              "currency": "EUR",
              "cash_account_type": "CACC",
              "name": "Cuenta corriente"
            }
          ],
          "access": { "valid_until": "2027-05-19T10:00:00.000000+00:00" }
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(imaginJSON.utf8)) == esIBAN)

        let revolutJSON = #"""
        {
          "session_id": "sess-rev-1",
          "accounts": [
            {
              "uid": "acc-rev-eur",
              "account_id": { "iban": "LT121000011101001000" },
              "currency": "EUR",
              "cash_account_type": "CACC"
            }
          ],
          "access": { "valid_until": "2027-05-19T10:00:00Z" }
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(revolutJSON.utf8)) == ltIBAN)
    }

    @Test func fallsBackToAllAccountIDsAndRejectsAmbiguousIDs() {
        // Sin account_id.iban, pero con un único IBAN en all_account_ids (junto a BBAN).
        let fallbackJSON = #"""
        {
          "session_id": "s-1",
          "accounts": [{
            "uid": "u-1",
            "account_id": {},
            "all_account_ids": [
              { "scheme_name": "BBAN", "identification": "21000418450200051332" },
              { "scheme_name": "IBAN", "identification": "ES91 2100 0418 4502 0005 1332" }
            ],
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(fallbackJSON.utf8)) == esIBAN)

        // Sin account_id.iban, pero presente en account_id.other con scheme_name IBAN.
        let otherJSON = #"""
        {
          "session_id": "s-2",
          "accounts": [{
            "uid": "u-1",
            "account_id": {
              "other": { "scheme_name": "IBAN", "identification": "LT121000011101001000" }
            },
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(otherJSON.utf8)) == ltIBAN)

        // Si account_id.iban es válido, prevalece aunque all_account_ids liste otro secundario.
        let primaryWinsJSON = #"""
        {
          "session_id": "s-3",
          "accounts": [{
            "uid": "u-1",
            "account_id": { "iban": "ES9121000418450200051332" },
            "all_account_ids": [
              { "scheme_name": "IBAN", "identification": "ES9121000418450200051332" },
              { "scheme_name": "IBAN", "identification": "LT121000011101001000" }
            ],
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(primaryWinsJSON.utf8)) == esIBAN)

        // Si account_id.iban viene informado pero es inválido, se descarta sin adivinar con all_account_ids.
        let invalidPrimaryJSON = #"""
        {
          "session_id": "s-4",
          "accounts": [{
            "uid": "u-1",
            "account_id": { "iban": "ES0000000000000000000000" },
            "all_account_ids": [
              { "scheme_name": "IBAN", "identification": "ES9121000418450200051332" }
            ],
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(invalidPrimaryJSON.utf8)) == nil)

        // Sin account_id.iban y dos IBAN distintos en all_account_ids: no adivina.
        let ambiguousAllIDsJSON = #"""
        {
          "session_id": "s-5",
          "accounts": [{
            "uid": "u-1",
            "all_account_ids": [
              { "scheme_name": "IBAN", "identification": "ES9121000418450200051332" },
              { "scheme_name": "IBAN", "identification": "LT121000011101001000" }
            ],
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(ambiguousAllIDsJSON.utf8)) == nil)

        // Sin account_id.iban y el mismo IBAN repetido con formato distinto en all_account_ids: inequívoco.
        let duplicateSameIDJSON = #"""
        {
          "session_id": "s-6",
          "accounts": [{
            "uid": "u-1",
            "all_account_ids": [
              { "scheme_name": "IBAN", "identification": "ES9121000418450200051332" },
              { "scheme_name": "iban", "identification": "es91 2100 0418 4502 0005 1332" }
            ],
            "currency": "EUR",
            "cash_account_type": "CACC"
          }]
        }
        """#
        #expect(extractPrimaryEuroIBAN(fromSessionData: Data(duplicateSameIDJSON.utf8)) == esIBAN)
    }

    @Test func returnsNilWhenSessionHasNoIBANOrInvalidIBAN() {
        let cases = [
            #"{"session_id":"s","accounts":[{"uid":"u1","currency":"EUR","cash_account_type":"CACC"}]}"#,
            #"{"session_id":"s","accounts":[{"uid":"u1","account_id":{"iban":null},"currency":"EUR","cash_account_type":"CACC"}]}"#,
            #"{"session_id":"s","accounts":[{"uid":"u1","account_id":{"iban":"ES9221000418450200051332"},"currency":"EUR","cash_account_type":"CACC"}]}"#,
            #"{"session_id":"s","accounts":[{"uid":"u1","account_id":{"iban":"XX61ABCD1234567890ABCD1234567890AB"},"currency":"EUR","cash_account_type":"CACC"}]}"#,
            #"{"session_id":"s","accounts":[]}"#,
            #"{"session_id":"s"}"#,
            #"not json"#,
        ]
        for json in cases {
            #expect(extractPrimaryEuroIBAN(fromSessionData: Data(json.utf8)) == nil)
        }
    }

    // MARK: - Varias cuentas y divisas

    @Test func selectsOnlyPrimaryEuroCurrentAccountWithoutGuessing() {
        // 1 EUR CACC + USD + GBP -> elige la de euros.
        let multiCurrency = [
            EBSessionAccountIBAN(uid: "u-usd", currency: "USD", cashAccountType: "CACC", rawIBAN: deIBAN),
            EBSessionAccountIBAN(uid: "u-eur", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN),
            EBSessionAccountIBAN(uid: "u-gbp", currency: "GBP", cashAccountType: "CACC", rawIBAN: gbIBAN),
        ]
        #expect(selectPrimaryEuroIBAN(from: multiCurrency) == esIBAN)

        // 1 EUR CACC + 1 EUR ahorro (SVGS) + 1 EUR tarjeta (CARD) -> elige solo CACC.
        let withSavingsAndCard = [
            EBSessionAccountIBAN(uid: "u-sav", currency: "EUR", cashAccountType: "SVGS", rawIBAN: esIBAN2),
            EBSessionAccountIBAN(uid: "u-cur", currency: "eur", cashAccountType: "cacc", rawIBAN: esIBAN),
            EBSessionAccountIBAN(uid: "u-crd", currency: "EUR", cashAccountType: "CARD", rawIBAN: frIBAN),
        ]
        #expect(selectPrimaryEuroIBAN(from: withSavingsAndCard) == esIBAN)

        // 1 EUR sin cash_account_type + 1 USD -> aceptada (mismo criterio que selectAccounts).
        let nilTypeEuro = [
            EBSessionAccountIBAN(uid: "u-eur", currency: "EUR", cashAccountType: nil, rawIBAN: ltIBAN),
            EBSessionAccountIBAN(uid: "u-usd", currency: "USD", cashAccountType: nil, rawIBAN: deIBAN),
        ]
        #expect(selectPrimaryEuroIBAN(from: nilTypeEuro) == ltIBAN)

        // Solo divisas distintas del euro -> nil.
        let nonEuroOnly = [
            EBSessionAccountIBAN(uid: "u-usd", currency: "USD", cashAccountType: "CACC", rawIBAN: deIBAN),
            EBSessionAccountIBAN(uid: "u-gbp", currency: "GBP", cashAccountType: "CACC", rawIBAN: gbIBAN),
        ]
        #expect(selectPrimaryEuroIBAN(from: nonEuroOnly) == nil)

        // Solo cuenta de ahorro (SVGS), ninguna corriente -> nil.
        let savingsOnly = [
            EBSessionAccountIBAN(uid: "u-sav", currency: "EUR", cashAccountType: "SVGS", rawIBAN: esIBAN),
        ]
        #expect(selectPrimaryEuroIBAN(from: savingsOnly) == nil)

        // 2 cuentas corrientes en EUR con IBAN distintos -> NO adivina (nil).
        let twoEuroCurrent = [
            EBSessionAccountIBAN(uid: "u-1", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN),
            EBSessionAccountIBAN(uid: "u-2", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN2),
        ]
        #expect(selectPrimaryEuroIBAN(from: twoEuroCurrent) == nil)

        // 2 cuentas corrientes en EUR donde una no trae IBAN -> NO adivina (nil).
        let twoEuroOneMissing = [
            EBSessionAccountIBAN(uid: "u-1", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN),
            EBSessionAccountIBAN(uid: "u-2", currency: "EUR", cashAccountType: "CACC", rawIBAN: nil),
        ]
        #expect(selectPrimaryEuroIBAN(from: twoEuroOneMissing) == nil)

        // 2 entradas de cuenta corriente en EUR con el MISMO IBAN -> inequívoco.
        let duplicateSameIBAN = [
            EBSessionAccountIBAN(uid: "u-1", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN),
            EBSessionAccountIBAN(uid: "u-2", currency: "EUR", cashAccountType: "CACC", rawIBAN: "es91 2100 0418 4502 0005 1332"),
        ]
        #expect(selectPrimaryEuroIBAN(from: duplicateSameIBAN) == esIBAN)
    }

    // MARK: - Aislamiento: modelos normales y descripciones sin IBAN

    @Test func normalAccountAndSessionModelsNeverCarryOrLeakIBAN() throws {
        let json = #"""
        {
          "session_id": "sess-secret-99",
          "accounts": [{
            "uid": "u-1",
            "account_id": { "iban": "ES9121000418450200051332" },
            "currency": "EUR",
            "cash_account_type": "CACC",
            "name": "Principal"
          }],
          "access": { "valid_until": "2027-05-19T10:00:00Z" }
        }
        """#
        let data = Data(json.utf8)
        let session = try JSONDecoder().decode(EBSession.self, from: data)
        let stored = StoredSession(
            sessionID: session.sessionID,
            accountUIDs: session.accounts.map(\.uid),
            validUntil: session.validUntil ?? Date(timeIntervalSince1970: 0),
            aspspName: "imaginBank",
            aspspCountry: "ES"
        )

        let accountsText = String(decoding: try JSONEncoder().encode(session.accounts), as: UTF8.self)
        let storedText = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        #expect(!accountsText.contains("ES91"))
        #expect(!accountsText.contains("21000418"))
        #expect(!storedText.contains("ES91"))
        #expect(!storedText.contains("21000418"))

        // Los tipos aparte usados en la conexión tampoco filtran el IBAN ni el sessionID al imprimirse.
        let accountIBAN = EBSessionAccountIBAN(uid: "u-1", currency: "EUR", cashAccountType: "CACC", rawIBAN: esIBAN)
        let auth = EBSessionAuthorization(session: session, primaryEuroIBAN: esIBAN)
        for text in [
            "\(accountIBAN)", String(reflecting: accountIBAN),
            "\(auth)", String(reflecting: auth),
        ] {
            #expect(!text.contains("ES91"))
            #expect(!text.contains("21000418"))
            #expect(!text.contains("sess-secret-99"))
        }
    }

    // MARK: - Cliente Enable Banking: una sola llamada POST /sessions

    @Test func authorizeSessionReturnsSessionAndValidatedIBANInOneRequest() async throws {
        let json = #"""
        {
          "session_id": "s-auth-1",
          "accounts": [
            { "uid": "u-usd", "account_id": { "iban": "DE89370400440532013000" }, "currency": "USD", "cash_account_type": "CACC" },
            { "uid": "u-eur", "account_id": { "iban": "lt12 1000 0111 0100 1000" }, "currency": "EUR", "cash_account_type": "CACC" }
          ],
          "access": { "valid_until": "2027-05-19T10:00:00Z" }
        }
        """#
        let transport = IBANFixtureTransport([(200, json)])
        let client = EnableBankingClient(
            transport: transport,
            signer: IBANFakeSigner(),
            appID: "00000000-0000-4000-8000-000000000001",
            now: { Date(timeIntervalSince1970: 1_795_172_400) }
        )

        let result = try await client.authorizeSession(code: "code-123")
        #expect(result.session.sessionID == "s-auth-1")
        #expect(result.session.accounts.map(\.uid) == ["u-usd", "u-eur"])
        #expect(result.primaryEuroIBAN == ltIBAN)

        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].method == "POST")
        #expect(requests[0].url.absoluteString == "https://api.enablebanking.com/sessions")

        // La sesión normal sigue sin llevar IBAN.
        let encodedAccounts = String(decoding: try JSONEncoder().encode(result.session.accounts), as: UTF8.self)
        #expect(!encodedAccounts.contains("LT12"))
        #expect(!encodedAccounts.contains("DE89"))
    }

    // MARK: - Regla «rellenar solo si está vacío» de AccountBook

    @Test func accountBookFillsOnlyWhenEmptyValidAndNotTradeRepublic() {
        var book = AccountBook()
        let payee = Payee(name: "Contacto Prueba", iban: frIBAN)
        book.floors[.rev] = 25_000
        book.payees = [payee]

        // Rellena Revolut e imagin cuando están vacíos.
        #expect(book.fillIBANIfEmpty("lt12 1000 0111 0100 1000", for: .rev) == true)
        #expect(book.ibans[.rev] == ltIBAN)
        #expect(book.fillIBANIfEmpty("es91 2100 0418 4502 0005 1332", for: .ima) == true)
        #expect(book.ibans[.ima] == esIBAN)

        // Nunca pisa un IBAN ya guardado por el dueño (o rellenado previamente).
        #expect(book.fillIBANIfEmpty(esIBAN2, for: .rev) == false)
        #expect(book.ibans[.rev] == ltIBAN)
        #expect(book.fillIBANIfEmpty(esIBAN2, for: .ima) == false)
        #expect(book.ibans[.ima] == esIBAN)

        // Trade Republic nunca se rellena automáticamente: sigue siendo manual.
        #expect(book.fillIBANIfEmpty(deIBAN, for: .tr) == false)
        #expect(book.ibans[.tr] == nil)

        // Un IBAN inválido se descarta sin ruido y deja el hueco vacío.
        var fresh = AccountBook()
        #expect(fresh.fillIBANIfEmpty("ES9221000418450200051332", for: .ima) == false)
        #expect(fresh.fillIBANIfEmpty("XX61ABCD1234567890ABCD1234567890AB", for: .rev) == false)
        #expect(fresh.ibans.isEmpty)

        // Respeta colchones y contactos existentes.
        #expect(book.floors[.rev] == 25_000)
        #expect(book.payees == [payee])

        // La descripción del cuaderno sigue redactada sin IBAN.
        #expect(!"\(book)".contains("ES91"))
        #expect(!"\(book)".contains("LT12"))
    }
}
