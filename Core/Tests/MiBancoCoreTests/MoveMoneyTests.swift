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

    @Test func movimientoPendienteSinIBAN() throws {
        let m = move()
        let data = try JSONEncoder().encode(m)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["amountCents", "createdAt", "from", "id", "target"])

        var hit = payment(20000, at: nov(20, 7, 49))
        hit.merchant = "Traspaso"
        guard case .done = moveState(m, movements: [hit], now: nov(20, 8)) else {
            Issue.record("el traspaso debería estar hecho")
            return
        }
        let state = LedgerState(movements: [hit])
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!json.contains("ES91"))
        #expect(!String(decoding: data, as: UTF8.self).contains("ES91"))
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
}
