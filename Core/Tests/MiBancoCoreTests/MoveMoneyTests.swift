import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date { date(11, day, hour, minute) }

private let esIBAN = "ES9121000418450200051332"

private func payment(_ cents: Int, bank: BankID = .ima, at when: Date) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: nil, kind: .payment, source: .notification, date: when)
}

private func move(_ cents: Int = 20000) -> PendingMove {
    PendingMove(id: UUID(), from: .ima, target: .own(.rev), amountCents: cents, createdAt: nov(20, 7, 45))
}

@Suite struct MoveMoneyTests {
    @Test func iban() {
        #expect(isValidIBAN("ES91 2100 0418 4502 0005 1332"))
        #expect(isValidIBAN("es9121000418450200051332"))
        #expect(isValidIBAN("DE89370400440532013000"))
        #expect(isValidIBAN("GB82WEST12345698765432"))
        #expect(!isValidIBAN("ES9121000418450200051333"))
        #expect(!isValidIBAN("ES91210004184502"))
        #expect(!isValidIBAN(""))
        #expect(normalizeIBAN("es91-2100 0418 4502 0005 1332") == esIBAN)
        #expect(formatIBAN(esIBAN) == "ES91 2100 0418 4502 0005 1332")
        #expect(maskedIBAN(esIBAN) == "ES91 •••• 1332")
    }

    @Test func telefono() {
        #expect(normalizeSpanishMobile("612345678") == "+34 612 345 678")
        #expect(normalizeSpanishMobile("+34 612 34 56 78") == "+34 612 345 678")
        #expect(normalizeSpanishMobile("0034612345678") == "+34 612 345 678")
        #expect(normalizeSpanishMobile("912345678") == nil)
        #expect(normalizeSpanishMobile("61234567") == nil)
    }

    @Test func traspasoHecho() {
        let m = move()
        let id = UUID()
        var hit = payment(20000, at: nov(20, 7, 49))
        hit.id = id
        #expect(moveState(m, movements: [hit], now: nov(20, 8)) == .done(movementID: id))
        #expect(moveState(m, movements: [payment(20000, at: nov(20, 7, 39))], now: nov(20, 8)) == .waiting)
        #expect(moveState(m, movements: [payment(19999, at: nov(20, 7, 49))], now: nov(20, 8)) == .waiting)
        let income = Movement(bank: .ima, amountCents: 20000, merchant: nil, kind: .income, source: .notification,
                              date: nov(20, 7, 49))
        #expect(moveState(m, movements: [income], now: nov(20, 8)) == .waiting)
        #expect(moveState(m, movements: [], now: nov(23, 7, 45).addingTimeInterval(1)) == .expired)
    }

    /// Todas las claves de un JSON, a cualquier profundidad.
    private func allKeys(_ value: Any) -> Set<String> {
        if let dict = value as? [String: Any] {
            return dict.reduce(into: Set(dict.keys)) { $0.formUnion(allKeys($1.value)) }
        }
        if let list = value as? [Any] {
            return list.reduce(into: Set<String>()) { $0.formUnion(allKeys($1)) }
        }
        return []
    }

    @Test func movimientoPendienteSinIBAN() throws {
        let m = move()
        let data = try JSONEncoder().encode(m)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["amountCents", "createdAt", "from", "id", "target"])

        // El libro nunca lleva claves de IBAN, destinatarios, teléfono ni libro de cuentas.
        var hit = payment(20000, at: nov(20, 7, 49))
        hit.merchant = "Traspaso"
        let state = LedgerState(
            balances: [.ima: ManualBalance(cents: 128455, setAt: nov(20), fromBank: false)],
            movements: [hit], unread: [UnreadNotice(bank: .rev, text: "texto", date: nov(20))])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        let keys = Set(allKeys(json).map { $0.lowercased() })
        #expect(keys.contains("movements"))
        #expect(keys.contains("amountcents"))
        for forbidden in ["iban", "ibans", "payee", "payees", "accountbook", "phone"] {
            #expect(!keys.contains(forbidden), "\(forbidden)")
        }
    }

    @Test func libroDeCuentasTolerante() throws {
        let empty = try JSONDecoder().decode(AccountBook.self, from: Data("{}".utf8))
        #expect(empty == AccountBook())
        var book = AccountBook()
        book.ibans[.rev] = esIBAN
        book.floors[.rev] = 5000
        book.payees = [Payee(id: UUID(), name: "Ana", iban: esIBAN, phone: nil)]
        let back = try JSONDecoder().decode(AccountBook.self, from: try JSONEncoder().encode(book))
        #expect(back == book)
    }

    @Test func portapapelesCaduca() {
        #expect(clipboardLifetime == 180)
    }

    @Test func pistas() {
        #expect(bankTransferHint(from: .ima, kind: .iban, amountCents: 20000)
            == "En imagin: Enviar dinero → Transferencia → pega el IBAN y pon 200,00\u{00A0}€.")
        #expect(bankTransferHint(from: .rev, kind: .iban, amountCents: 20000)
            == "En Revolut: Pagos → Transferir → Cuenta bancaria → pega el IBAN y pon 200,00\u{00A0}€.")
        #expect(bankTransferHint(from: .tr, kind: .iban, amountCents: 20000)
            == "En Trade Republic: Efectivo → Transferir → Retirar. Solo puedes enviarlo a tu cuenta de referencia.")
        #expect(bankTransferHint(from: .ima, kind: .phone, amountCents: 1500)
            == "En imagin: Bizum → Enviar → pega el número y pon 15,00\u{00A0}€.")
    }

    private let balances: [BankID: Int] = [.rev: 34020, .ima: 128455, .tr: 215000]
    private let floors: [BankID: Int] = [.rev: 5000]
    private var spotify: UpcomingCharge { UpcomingCharge(name: "Spotify", bank: .rev, cents: 1099, date: nov(22)) }
    private var netflix: UpcomingCharge { UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(25)) }

    @Test func dondeLoPago() {
        let upcoming = [spotify, netflix]
        #expect(whereToPay(amountCents: 4500, balances: balances, floors: floors, upcoming: upcoming) == [
            PayOption(bank: .ima, leftAfterCents: 123955, fits: true),
            PayOption(bank: .rev, leftAfterCents: 22022, fits: true),
            PayOption(bank: .tr, leftAfterCents: 210500, fits: true),
        ])
        #expect(whereToPay(amountCents: 30000, balances: balances, floors: floors, upcoming: upcoming) == [
            PayOption(bank: .ima, leftAfterCents: 98455, fits: true),
            PayOption(bank: .tr, leftAfterCents: 185000, fits: true),
            PayOption(bank: .rev, leftAfterCents: -3478, fits: false),
        ])
    }

    @Test func faltaParaUnCobro() {
        let now = nov(19, 10)
        let netflixSoon = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(20, 12))
        let low: [BankID: Int] = [.rev: 920, .ima: 128455]
        #expect(shortfalls(balances: low, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal) == [
            Shortfall(bank: .rev, charge: netflixSoon, balanceCents: 920, missingCents: 479, suggestedFrom: .ima,
                      suggestedCents: 1000),
        ])
        let netflixLater = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(23, 12))
        #expect(shortfalls(balances: low, floors: [:], upcoming: [netflixLater], now: now, calendar: cal).isEmpty)
        let spotifyTomorrow = UpcomingCharge(name: "Spotify", bank: .rev, cents: 1099, date: nov(21, 12))
        let withFloor = shortfalls(balances: [.rev: 6000, .ima: 128455], floors: [.rev: 5000],
                                   upcoming: [spotifyTomorrow], now: now, calendar: cal)
        #expect(withFloor.count == 1)
        #expect(withFloor[0].missingCents == 99)
        #expect(withFloor[0].suggestedCents == 1000)
    }

    @Test func dineroLibre() {
        let now = nov(20, 8, 30)
        let decDate = date(12, 5)
        let pending = [
            UpcomingCharge(name: "Spotify", bank: .rev, cents: 1099, date: nov(22)),
            UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(25)),
            UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: decDate),
        ]
        let free = freeMoney(balances: balances, floors: floors, banks: [.rev, .ima], pending: pending, now: now, calendar: cal)
        #expect(free == FreeMoney(cents: 154977, daysLeft: 11))
        #expect(free?.perDayCents == 14088)
        #expect(freeMoney(balances: [:], floors: floors, banks: [.rev, .ima], pending: pending, now: now, calendar: cal) == nil)
        #expect(freeMoney(balances: [.rev: 3000], floors: [.rev: 5000], banks: [.rev], pending: [], now: now, calendar: cal) == nil)
    }

    // MARK: Ronda de arreglos tras la revisión

    @Test func traspasoNoLoCierraOtroPago() {
        let m = move()
        var shop = payment(20000, at: nov(20, 7, 46))
        shop.isShop = true
        #expect(moveState(m, movements: [shop], now: nov(20, 8)) == .waiting)

        // Dos traspasos iguales necesitan dos movimientos distintos.
        let m2 = move()
        let first = payment(20000, at: nov(20, 7, 49))
        let second = payment(20000, at: nov(20, 7, 55))
        let all = [first, second]
        guard case .done(let firstID) = moveState(m, movements: all, now: nov(20, 8)) else {
            Issue.record("el primero debería cerrarse")
            return
        }
        #expect(firstID == first.id)
        #expect(moveState(m2, movements: [first], now: nov(20, 8), claimed: [firstID]) == .waiting)
        #expect(moveState(m2, movements: all, now: nov(20, 8), claimed: [firstID]) == .done(movementID: second.id))

        // Fechado después de ahora: no vale.
        #expect(moveState(m, movements: [payment(20000, at: nov(20, 9))], now: nov(20, 8)) == .waiting)
        // Otro banco y «no es mío»: no valen.
        #expect(moveState(m, movements: [payment(20000, bank: .rev, at: nov(20, 7, 49))], now: nov(20, 8)) == .waiting)
        var flagged = payment(20000, at: nov(20, 7, 49))
        flagged.flaggedNotMine = true
        #expect(moveState(m, movements: [flagged], now: nov(20, 8)) == .waiting)
    }

    @Test func traspasoLimitesExactos() {
        let m = move()
        let start = m.createdAt.addingTimeInterval(-300)
        let end = m.createdAt.addingTimeInterval(3 * 86_400)
        let now = end.addingTimeInterval(10)
        func at(_ when: Date) -> MoveState { moveState(m, movements: [payment(20000, at: when)], now: now) }
        #expect(at(start) != .waiting && at(start) != .expired)
        #expect(at(start.addingTimeInterval(-1)) == .expired)
        #expect(at(end) != .waiting && at(end) != .expired)
        #expect(at(end.addingTimeInterval(1)) == .expired)
    }

    @Test func dineroLibreAvisaDeLosQueFaltan() {
        let now = nov(20, 8, 30)
        let free = freeMoney(balances: [.rev: 34020], floors: floors, banks: [.rev, .ima], pending: [], now: now, calendar: cal)
        #expect(free?.cents == 29020)
        #expect(free?.missingBanks == [BankID.ima])
        let full = freeMoney(balances: balances, floors: floors, banks: [.rev, .ima, .tr], pending: [], now: now, calendar: cal)
        #expect(full?.missingBanks.isEmpty == true)
        #expect(freeMoney(balances: [.tr: 100], floors: [:], banks: [.rev, .ima], pending: [], now: now, calendar: cal) == nil)
    }

    @Test func dondeLoPagoSoloLosIncluidos() {
        let options = whereToPay(amountCents: 4500, balances: balances, floors: floors, upcoming: [spotify, netflix],
                                 included: [.rev, .ima], estimated: [.ima])
        #expect(options == [
            PayOption(bank: .ima, leftAfterCents: 123955, fits: true, isEstimated: true),
            PayOption(bank: .rev, leftAfterCents: 22022, fits: true),
        ])
    }

    @Test func faltaSoloConIncluidosYMarcaEstimados() {
        let now = nov(19, 10)
        let netflixSoon = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(20, 12))
        let all: [BankID: Int] = [.rev: 920, .ima: 128455, .tr: 215000]
        // imagin excluido: se sugiere Trade Republic; con las dos excluidas, nadie.
        let noIma = shortfalls(balances: all, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal, included: [.rev, .tr])
        #expect(noIma.first?.suggestedFrom == .tr)
        let onlyRev = shortfalls(balances: all, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal, included: [.rev])
        #expect(onlyRev.count == 1)
        #expect(onlyRev[0].suggestedFrom == nil)
        // Rev excluido: no se le avisa de que le falta.
        #expect(shortfalls(balances: all, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal, included: [.ima, .tr]).isEmpty)
        // Estimados.
        let est = shortfalls(balances: all, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal, estimated: [.rev, .ima])
        #expect(est.first?.isEstimated == true)
        #expect(est.first?.suggestedIsEstimated == true)
        let exact = shortfalls(balances: all, floors: [:], upcoming: [netflixSoon], now: now, calendar: cal)
        #expect(exact.first?.isEstimated == false)
        #expect(exact.first?.suggestedIsEstimated == false)
        // Un cobro anterior a ahora ya está en el saldo.
        let past = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1399, date: nov(19, 9))
        #expect(shortfalls(balances: all, floors: [:], upcoming: [past], now: now, calendar: cal).isEmpty)
    }

    @Test func pistaDeTradeRepublicConTelefono() {
        #expect(bankTransferHint(from: .tr, kind: .phone, amountCents: 1500)
            == "No encuentro cómo enviar dinero a un teléfono desde Trade Republic. Usa su IBAN.")
    }

    @Test func salidaSinDatosPersonales() {
        let payee = Payee(id: UUID(), name: "Ana Pérez", iban: esIBAN, phone: "+34 612 345 678")
        var book = AccountBook()
        book.ibans[.rev] = esIBAN
        book.payees = [payee]
        for text in ["\(payee)", String(reflecting: payee), "\(book)", String(reflecting: book), String(describing: book)] {
            #expect(!text.contains("Ana"))
            #expect(!text.contains("ES91"))
            #expect(!text.contains("612"))
            #expect(!text.contains("2100"))
        }
    }

    @Test func ibanCasosLimite() {
        // 34 caracteres con dígito de control correcto.
        let long = "XX61ABCD1234567890ABCD1234567890AB"
        #expect(long.count == 34)
        #expect(isValidIBAN(long))
        #expect(maskedIBAN(long) == "XX61 •••• 90AB")
        // España con el módulo 97 correcto pero de 23 y 25 caracteres: no vale.
        #expect(!isValidIBAN("ES982100041845020005133"))
        #expect(!isValidIBAN("ES48210004184502000513321"))
        // Lo que no es ASCII se descarta antes de pasar a mayúsculas.
        #expect(normalizeIBAN("ß") == "")
        #expect(normalizeIBAN("esß91 2100 0418 4502 0005 1332") == esIBAN)
        // Máscara de IBAN cortos: solo los dos últimos.
        #expect(maskedIBAN("ES91ABCDEFGH") == "ES91 •••• EFGH")
        #expect(maskedIBAN("ES91ABCDEFG") == "•••• FG")
        #expect(maskedIBAN("") == "••••")
    }

    @Test func telefonoConGuiones() {
        #expect(normalizeSpanishMobile("612-345-678") == "+34 612 345 678")
        #expect(normalizeSpanishMobile("+34-612-34-56-78") == "+34 612 345 678")
    }
}
