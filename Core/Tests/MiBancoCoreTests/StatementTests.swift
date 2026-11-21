import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = minute; c.second = second
    return madrid.date(from: c)!
}

private let revolutHeader = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"
private let revolutRows = [
    "Transfer,Current,2026-11-16 10:00:00,2026-11-16 10:00:01,To USD,-20.00,0.50,EUR,COMPLETED,240.20",
    "Topup,Current,2026-11-17 08:00:00,2026-11-17 08:00:01,Apple Pay Top-Up,100.00,0.00,EUR,COMPLETED,340.20",
    "Card Payment,Current,2026-11-18 13:05:11,2026-11-19 09:00:00,Mercadona,-12.50,0.00,EUR,COMPLETED,327.70",
    "Card Payment,Current,2026-11-18 20:00:00,,Bolt,-7.30,0.00,EUR,PENDING,",
    "Card Payment,Savings,2026-11-10 10:00:00,2026-11-10 10:00:00,Vault,-5.00,0.00,EUR,COMPLETED,10.00",
    "Card Payment,Current,2026-11-15 10:00:00,2026-11-15 10:00:00,Shop US,-3.00,0.00,USD,COMPLETED,1.00",
]
private let revolutCSV = ([revolutHeader] + revolutRows).joined(separator: "\n") + "\n"

private let caixaCSV = """
Fecha;Fecha valor;Movimiento;Más datos;Importe;Saldo
18/11/2026;18/11/2026;COMPRA TARJ. 5402XXXXXXXX1234 MERCADONA;;-23,45;1.284,55
17/11/2026;17/11/2026;TRANSFERENCIA DE CARLOS;Nómina;1.250,00;1.308,00

"""

private let trHeaders = ["datetime", "date", "account_type", "category", "type", "asset_class", "name", "symbol", "shares", "price",
                         "amount", "fee", "tax", "currency", "original_amount", "original_currency", "fx_rate", "description",
                         "transaction_id", "counterparty_name", "counterparty_iban", "payment_reference", "mcc_code"]

private func trLine(_ values: [String: String]) -> String {
    trHeaders.map { h in
        let v = values[h] ?? ""
        return v.contains(",") || v.contains("\"") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }.joined(separator: ",")
}

private let trRows: [[String: String]] = [
    ["datetime": "2026-11-18T09:15:00Z", "date": "2026-11-18", "account_type": "DEFAULT", "category": "CASH", "type": "CARD_TRANSACTION",
     "name": "Mercadona", "amount": "-12.50", "currency": "EUR", "transaction_id": "tx-1", "counterparty_name": "Mercadona",
     "counterparty_iban": "XX00TEST", "mcc_code": "5411"],
    ["datetime": "2026-11-19T02:00:00Z", "date": "2026-11-19", "category": "CASH", "type": "INTEREST_PAYMENT", "amount": "2.31",
     "currency": "EUR", "description": "Interest", "transaction_id": "tx-2"],
    ["datetime": "2026-11-19T08:30:00Z", "date": "2026-11-19", "category": "TRADING", "type": "BUY", "asset_class": "FUND",
     "name": "Test World Fund", "symbol": "IE00B4L5Y983", "shares": "1.5", "price": "100.00", "amount": "-150.00", "fee": "-1.00",
     "currency": "EUR", "transaction_id": "tx-3"],
    ["datetime": "2026-11-19T09:00:00Z", "date": "2026-11-19", "category": "TRADING", "type": "FREE_RECEIPT", "asset_class": "CRYPTO",
     "name": "Test Coin", "symbol": "TST", "shares": "0.001", "currency": "EUR", "transaction_id": "tx-4"],
]
private let trCSV = ([trHeaders.joined(separator: ",")] + trRows.map(trLine)).joined(separator: "\n") + "\n"

private func parse(_ csv: String, _ bank: BankID, now: Date = at(11, 20)) throws -> ParsedStatement {
    try parseStatement(Data(csv.utf8), expected: bank, now: now, calendar: madrid)
}

@Suite struct StatementTests {
    // MARK: Revolut

    @Test func revolutStatement() throws {
        let s = try parse(revolutCSV, .rev)
        #expect(s.format == .revolut)
        #expect(s.records.map(\.amountCents) == [-2050, 10_000, -1250])
        #expect(s.records.map(\.isShop) == [false, false, true])
        #expect(s.records.allSatisfy { $0.bank == .rev && $0.status == .booked && $0.timing.isExact })
        #expect(s.records[2].timing.date == at(11, 18, 13, 5, 11))
        #expect(s.records[2].merchant == "Mercadona")
        #expect(s.ignoredRows == 3)
        #expect(s.latestBalance == StatementBalance(cents: 32_770, at: at(11, 19, 9, 0, 0)))
        #expect(s.firstDate == at(11, 16, 10))
        #expect(s.lastDate == at(11, 18, 13, 5, 11))
    }

    @Test func revolutExtraColumnTolerated() throws {
        let extra = (["\(revolutHeader),Notes"] + revolutRows.map { $0 + ",hola" }).joined(separator: "\n") + "\n"
        #expect(try parse(extra, .rev).records == (try parse(revolutCSV, .rev)).records)
    }

    @Test func revolutSpanishHeadersBomAndSemicolon() throws {
        let header = "Tipo;Producto;Fecha de inicio;Fecha de finalización;Descripción;Importe;Comisión;Divisa;Estado;Saldo"
        let row = "Pago con tarjeta;Actual;2026-11-18 13:05:11;2026-11-19 09:00:00;Mercadona;-12,50;0,00;EUR;COMPLETADO;327,70"
        let s = try parse("\u{FEFF}" + header + "\r\n" + row + "\r\n", .rev)
        #expect(s.records.map(\.amountCents) == [-1250])
        #expect(s.records[0].isShop)
        #expect(s.latestBalance?.cents == 32_770)
    }

    @Test func revolutOccurrenceKeepsIdenticalRowsApart() throws {
        let row = "Card Payment,Current,2026-11-18 13:05:11,2026-11-18 13:05:12,Cafe,-2.00,0.00,EUR,COMPLETED,10.00"
        let s = try parse(revolutHeader + "\n" + row + "\n" + row + "\n", .rev)
        #expect(s.records.count == 2)
        #expect(Set(s.records.map(\.ref)).count == 2)
        #expect(s.records.allSatisfy { $0.ref.hasPrefix("r|") })
    }

    // MARK: CaixaBank

    @Test func caixabankStatement() throws {
        let s = try parse(caixaCSV, .ima, now: at(11, 20, 12))
        #expect(s.format == .caixabank)
        #expect(s.records.map(\.amountCents) == [-2345, 125_000])
        #expect(s.records.map(\.merchant) == ["Mercadona", "Transferencia de Carlos"])
        #expect(s.records.map(\.isShop) == [true, false])
        #expect(s.records.allSatisfy { !$0.timing.isExact })
        #expect(s.records[0].timing.date == at(11, 18, 12))
        #expect(s.latestBalance == StatementBalance(cents: 128_455, at: at(11, 18, 23, 59, 59)))
        #expect(s.ignoredRows == 0)
    }

    @Test func caixabankBalanceIsClippedToNowAndPicksNewestDateNotFirstRow() throws {
        // Fichero del más antiguo al más nuevo: gana el último movimiento del día más reciente (C, 8,00 €), no la primera
        // fila ni la primera de ese día. (R32: antes esperaba 900, el saldo de B, que es anterior a C.)
        let csv = """
        Fecha;Fecha valor;Movimiento;Más datos;Importe;Saldo
        17/11/2026;17/11/2026;A;;-1,00;10,00
        18/11/2026;18/11/2026;B;;-1,00;9,00
        18/11/2026;18/11/2026;C;;-1,00;8,00

        """
        let s = try parse(csv, .ima, now: at(11, 18, 15))
        #expect(s.latestBalance == StatementBalance(cents: 800, at: at(11, 18, 15)))
    }

    /// R32 B1: el saldo de cierre es el del último movimiento en el tiempo, sea cual sea el orden del fichero.
    @Test func caixabankClosingBalanceDoesNotDependOnFileOrder() throws {
        let header = "Fecha;Fecha valor;Movimiento;Más datos;Importe;Saldo\n"
        func closing(_ rows: [String]) throws -> Int? {
            try parse(header + rows.joined(separator: "\n") + "\n", .ima, now: at(11, 20, 12)).latestBalance?.cents
        }
        // Más nuevo primero, varias filas el último día.
        #expect(try closing(["18/11/2026;18/11/2026;C;;-1,00;8,00", "18/11/2026;18/11/2026;B;;-1,00;9,00",
                             "17/11/2026;17/11/2026;A;;-1,00;10,00"]) == 800)
        // Más antiguo primero.
        #expect(try closing(["17/11/2026;17/11/2026;A;;-1,00;10,00", "18/11/2026;18/11/2026;B;;-1,00;9,00",
                             "18/11/2026;18/11/2026;C;;-1,00;8,00"]) == 800)
        // Todo el mismo día: solo la cadena del saldo dice el sentido.
        #expect(try closing(["18/11/2026;18/11/2026;B;;-1,00;9,00", "18/11/2026;18/11/2026;C;;-1,00;8,00"]) == 800)
        #expect(try closing(["18/11/2026;18/11/2026;C;;-1,00;8,00", "18/11/2026;18/11/2026;B;;-1,00;9,00"]) == 800)
    }

    /// R32: la cabecera con «Concepto» en lugar de «Movimiento» también es CaixaBank.
    @Test func caixabankDetectionAcceptsConceptoAlias() throws {
        let csv = "Fecha;Concepto;Importe;Saldo\n18/11/2026;COMPRA MERCADONA;-23,45;1.284,55\n"
        let s = try parse(csv, .ima)
        #expect(s.format == .caixabank)
        #expect(s.records.map(\.amountCents) == [-2345])
    }

    // MARK: R32 B2, B3: filas ilegibles

    @Test func tradeRepublicUnreadableAmountFeeOrTaxIsIgnoredNotZero() throws {
        let rows = [
            ["datetime": "2026-11-18T09:00:00Z", "category": "CASH", "amount": "-5.00", "currency": "EUR", "transaction_id": "ok"],
            ["datetime": "2026-11-18T09:01:00Z", "category": "CASH", "amount": "abc", "fee": "-1.00", "currency": "EUR",
             "transaction_id": "bad-amount"],
            ["datetime": "2026-11-18T09:02:00Z", "category": "CASH", "amount": "-5.00", "fee": "x1", "currency": "EUR",
             "transaction_id": "bad-fee"],
            ["datetime": "2026-11-18T09:03:00Z", "category": "CASH", "amount": "-5.00", "tax": "??", "currency": "EUR",
             "transaction_id": "bad-tax"],
            ["datetime": "2026-11-18T09:04:00Z", "category": "CASH", "amount": "-5.00", "fee": "", "currency": "EUR",
             "transaction_id": "empty-fee-is-fine"],
        ]
        let csv = ([trHeaders.joined(separator: ",")] + rows.map(trLine)).joined(separator: "\n") + "\n"
        let s = try parse(csv, .tr)
        #expect(s.records.map(\.ref) == ["tr|ok", "tr|empty-fee-is-fine"])
        #expect(s.records.map(\.amountCents) == [-500, -500])
        #expect(s.ignoredRows == 3)
        let exported = try parseTradeRepublicExport(try CSVTable.parse(Data(csv.utf8)))
        #expect(exported.map(\.hasUnreadableAmount) == [false, true, true, true, false])
    }

    @Test func unterminatedQuoteAtEndOfFileIsUnreadable() throws {
        #expect(throws: StatementError.unreadable) { try CSVTable.parse(Data("a,b\n1,\"abierta\n2,3\n".utf8)) }
        #expect(throws: StatementError.unreadable) { try parse(revolutCSV + "Card Payment,Current,\"2026-11-18 13:05:11\n", .rev) }
        // Cerrada al final del fichero no es un error.
        let closed = try CSVTable.parse(Data("a,b\n1,\"cerrada\"".utf8))
        #expect(closed.rows == [["1", "cerrada"]])
    }

    @Test func rowsWithAnotherCellCountAreIgnoredAndCounted() throws {
        let short = "Card Payment,Current,2026-11-18 13:05:11,2026-11-19 09:00:00,Cafe,-2.00\n"
        let long = "Card Payment,Current,2026-11-18 14:05:11,2026-11-19 09:00:00,Cafe,-2.00,0.00,EUR,COMPLETED,10.00,extra\n"
        let s = try parse(revolutCSV + short + long, .rev)
        #expect(s.records.map(\.amountCents) == [-2050, 10_000, -1250])
        #expect(s.ignoredRows == 3 + 2)
        let table = try CSVTable.parse(Data((revolutCSV + short + long).utf8))
        #expect(table.malformedRows == 2)
        #expect(table.rows.allSatisfy { $0.count == table.headers.count })
        // CaixaBank: sin la celda «Más datos» el importe quedaría desplazado a otra columna.
        let shifted = caixaCSV + "18/11/2026;18/11/2026;COMPRA;-5,00;9,00\n"
        let c = try parse(shifted, .ima)
        #expect(c.records.map(\.amountCents) == [-2345, 125_000])
        #expect(c.ignoredRows == 1)
        // Si todas las filas están mal no es un fichero vacío: se cuentan.
        let onlyBad = try parse(revolutHeader + "\n1,2\n", .rev)
        #expect(onlyBad.records.isEmpty)
        #expect(onlyBad.ignoredRows == 1)
    }

    @Test func tradeRepublicRowHasPublicInitAndUsesPassedCalendar() throws {
        let row = TradeRepublicRow(type: "BUY", amountCents: -1000, feeCents: -100, currency: "EUR", transactionID: "t")
        #expect(row.cashEffectCents == -1100)
        #expect(row.datetime == nil && row.hasUnreadableAmount == false)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let csv = ([trHeaders.joined(separator: ",")]
            + [trLine(["date": "2026-11-18", "amount": "5.00", "currency": "EUR", "transaction_id": "d"])]).joined(separator: "\n") + "\n"
        let table = try CSVTable.parse(Data(csv.utf8))
        let inUTC = try parseTradeRepublicExport(table, calendar: utc)
        #expect(inUTC[0].date == utc.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        let inMadrid = try parseTradeRepublicExport(table, calendar: madrid)
        #expect(inMadrid[0].date == at(11, 18, 12))
        #expect(inUTC[0].date != inMadrid[0].date)
        let s = try parseStatement(Data(csv.utf8), expected: .tr, now: at(11, 20), calendar: utc)
        #expect(s.records[0].timing.date == inUTC[0].date)
    }

    @Test func tradeRepublicRepeatedTransactionIDCarriesCentsInSuffix() throws {
        let rows = [
            ["datetime": "2026-11-18T09:00:00Z", "amount": "-5.00", "currency": "EUR", "transaction_id": "dup"],
            ["datetime": "2026-11-18T09:00:00Z", "amount": "-7.00", "currency": "EUR", "transaction_id": "dup"],
            ["datetime": "2026-11-18T09:00:00Z", "amount": "-7.00", "currency": "EUR", "transaction_id": "dup"],
        ]
        let csv = ([trHeaders.joined(separator: ",")] + rows.map(trLine)).joined(separator: "\n") + "\n"
        let s = try parse(csv, .tr)
        #expect(s.records.map(\.ref) == ["tr|dup", "tr|dup|-700", "tr|dup|-700|2"])
        // Un fichero que solo trae las dos primeras da las mismas claves a esas dos filas.
        let overlap = ([trHeaders.joined(separator: ",")] + rows.prefix(2).map(trLine)).joined(separator: "\n") + "\n"
        #expect(try parse(overlap, .tr).records.map(\.ref) == ["tr|dup", "tr|dup|-700"])
    }

    // MARK: R32 B4, B5: saldo más antiguo y claves por valores leídos

    @Test func importingAnOlderStatementNeverReplacesANewerBalance() throws {
        // A mano, de hoy.
        var manual = Ledger()
        manual.setBalance(.rev, cents: 50_000, now: at(11, 20, 10))
        manual.importStatement(try parse(revolutCSV, .rev), now: at(11, 20, 12), calendar: madrid)
        #expect(manual.state.balances[.rev]?.origin == .manual)
        #expect(manual.state.balances[.rev]?.cents == 50_000)
        #expect(manual.state.movements.count == 3)
        // De la API, de hoy.
        var bank = Ledger()
        bank.adoptBalance(.rev, cents: 777, at: at(11, 20, 10), origin: .bank)
        bank.importStatement(try parse(revolutCSV, .rev), now: at(11, 20, 12), calendar: madrid)
        #expect(bank.state.balances[.rev]?.origin == .bank)
        #expect(bank.state.balances[.rev]?.cents == 777)
        // Un extracto más reciente que la lectura sí la sustituye, también a una puesta a mano.
        var older = Ledger()
        older.setBalance(.rev, cents: 50_000, now: at(11, 1))
        older.importStatement(try parse(revolutCSV, .rev), now: at(11, 20, 12), calendar: madrid)
        #expect(older.state.balances[.rev]?.origin == .statement)
        #expect(older.state.balances[.rev]?.cents == 32_770)
    }

    @Test func sameStatementExportedWithOtherFormatsAddsNothing() throws {
        var l = Ledger()
        l.importStatement(try parse(revolutCSV, .rev), now: at(11, 20), calendar: madrid)
        let header = "Type;Product;Started Date;Completed Date;Description;Amount;Fee;Currency;State;Balance"
        let row = "Card Payment;Current;2026-11-18T13:05:11;2026-11-19T09:00:00;  MERCADONA ;-12,50;0,00;EUR;COMPLETED;327,70"
        let variant = try parse(header + "\n" + row + "\n", .rev)
        #expect(variant.records[0].ref == (try parse(revolutCSV, .rev)).records[2].ref)
        let report = l.importStatement(variant, now: at(11, 21), calendar: madrid)
        #expect(report.added == 0)
        #expect(l.state.movements.count == 3)

        var c = Ledger()
        c.importStatement(try parse(caixaCSV, .ima), now: at(11, 20), calendar: madrid)
        let other = """
        Fecha;Fecha valor;Movimiento;Más datos;Importe;Saldo
        18-11-2026;18-11-2026;compra tarj. 5402XXXXXXXX1234   mercadona;;-23.45;1284.55

        """
        let again = c.importStatement(try parse(other, .ima), now: at(11, 21), calendar: madrid)
        #expect(again.added == 0)
        #expect(c.state.movements.count == 2)
    }

    /// Libros con filas importadas con la clave de la versión anterior (hash del texto de las celdas): al reimportar se
    /// reconocen por `legacyRefs`, pasan a la clave nueva y no se duplican.
    @Test func rowsImportedWithTheOldRefSchemeAreNotDuplicated() throws {
        let oldRevolut = "r|" + fnv1aHex("2026-11-18 13:05:11|-12.50|Mercadona") + "|0"
        let oldCaixa = "c|" + fnv1aHex("18/11/2026|-23,45|COMPRA TARJ. 5402XXXXXXXX1234 MERCADONA|1.284,55") + "|0"
        let oldTR = "tr|" + fnv1aHex(["1794993300", "-1250", "CARD_TRANSACTION", "Mercadona", ""].joined(separator: "|")) + "|0"
        func stored(_ bank: BankID, _ ref: String, _ cents: Int, _ date: Date, dayOnly: Bool) -> Movement {
            Movement(bank: bank, amountCents: cents, merchant: "x", kind: .payment, source: .statement, date: date,
                     statementRef: ref, bankStatus: .booked, importedAt: at(11, 19), dayOnly: dayOnly)
        }
        var rev = Ledger(state: LedgerState(movements: [stored(.rev, oldRevolut, -1250, at(11, 18, 13, 5, 11), dayOnly: false)]))
        let revReport = rev.importStatement(try parse(revolutCSV, .rev), now: at(11, 20), calendar: madrid)
        #expect(revReport.added == 2)
        #expect(rev.state.movements.count == 3)
        let newRef = try parse(revolutCSV, .rev).records[2].ref
        #expect(newRef != oldRevolut)
        #expect(rev.state.movements.contains { $0.statementRef == newRef })
        #expect(!rev.state.movements.contains { $0.statementRef == oldRevolut })

        var caixa = Ledger(state: LedgerState(movements: [stored(.ima, oldCaixa, -2345, at(11, 18, 12), dayOnly: true)]))
        #expect(caixa.importStatement(try parse(caixaCSV, .ima), now: at(11, 20), calendar: madrid).added == 1)
        #expect(caixa.state.movements.count == 2)

        var tr = Ledger(state: LedgerState(movements: [stored(.tr, oldTR, -1250, Date(timeIntervalSince1970: 1_794_993_300), dayOnly: false)]))
        let noID = ([trHeaders.joined(separator: ",")] + [trLine(["datetime": "2026-11-18T09:15:00Z", "type": "CARD_TRANSACTION",
            "name": "Mercadona", "amount": "-12.50", "currency": "EUR"])]).joined(separator: "\n") + "\n"
        #expect(tr.importStatement(try parse(noID, .tr), now: at(11, 20), calendar: madrid).added == 0)
        #expect(tr.state.movements.count == 1)
        #expect(tr.state.movements[0].statementRef != oldTR)
    }

    @Test func missingColumnIsNamed() {
        let csv = """
        Fecha;Fecha valor;Movimiento;Más datos;Saldo
        18/11/2026;18/11/2026;COMPRA;;1.284,55

        """
        #expect(throws: StatementError.missingColumns(["importe"])) { try parse(csv, .ima) }
    }

    @Test func wrongBankDetected() {
        #expect(throws: StatementError.wrongBank(detected: .rev)) { try parse(revolutCSV, .ima) }
        #expect(throws: StatementError.wrongBank(detected: .ima)) { try parse(caixaCSV, .tr) }
    }

    @Test func unknownFormatAndEmpty() {
        #expect(throws: StatementError.unknownFormat) { try parse("a;b\n1;2\n", .rev) }
        #expect(throws: StatementError.empty) { try parse(revolutHeader + "\n", .rev) }
        #expect(throws: StatementError.empty) { try parse("", .rev) }
    }

    @Test func caixabankRowsWithBadDateOrAmountAreIgnored() throws {
        let csv = caixaCSV + "ayer;ayer;RARO;;-1,00;5,00\n19/11/2026;19/11/2026;RARO;;xx;5,00\n"
        let s = try parse(csv, .ima)
        #expect(s.records.count == 2)
        #expect(s.ignoredRows == 2)
    }

    // MARK: Trade Republic

    @Test func tradeRepublicExport() throws {
        let table = try CSVTable.parse(Data(trCSV.utf8))
        let rows = try parseTradeRepublicExport(table)
        #expect(rows.count == 4)
        #expect(rows[2].shares == "1.5")
        #expect(rows[2].symbol == "IE00B4L5Y983")
        #expect(rows[2].price == "100.00")
        #expect(rows[2].amountCents == -15_000)
        #expect(rows[2].feeCents == -100)
        #expect(rows[2].type == "BUY")
        #expect(rows[0].transactionID == "tx-1")
        #expect(rows[0].counterpartyName == "Mercadona")
        #expect(rows[0].mccCode == "5411")
        #expect(rows[0].datetime == Date(timeIntervalSince1970: 1_794_993_300))
        #expect(rows[3].amountCents == nil)
        // El IBAN de la contraparte nunca se lee.
        for row in rows {
            for child in Mirror(reflecting: row).children {
                #expect(!"\(child.value)".contains("XX00TEST"))
            }
        }

        let s = try parse(trCSV, .tr)
        #expect(s.format == .tradeRepublic)
        #expect(s.records.map(\.amountCents) == [-1250, 231, -15_100])
        #expect(s.records.map(\.isShop) == [true, false, false])
        #expect(s.records.map(\.excludedFromSpending) == [false, false, true])
        #expect(s.records[0].timing.isExact)
        #expect(s.records[0].ref == "tr|tx-1")
        #expect(s.ignoredRows == 1)
        #expect(s.latestBalance == nil)
    }

    @Test func tradeRepublicSemicolonDecimalCommaAndMissingColumn() throws {
        let header = trHeaders.joined(separator: ";")
        let row = trHeaders.map { h -> String in
            ["datetime": "2026-11-18T09:15:00.000Z", "amount": "-12,50", "currency": "EUR", "transaction_id": "tx-9",
             "counterparty_name": "Cafe"][h] ?? ""
        }.joined(separator: ";")
        let s = try parse(header + "\n" + row + "\n", .tr)
        #expect(s.records.map(\.amountCents) == [-1250])

        let noTx = trHeaders.filter { $0 != "transaction_id" && $0 != "counterparty_name" }.joined(separator: ",")
        #expect(throws: StatementError.missingColumns(["transaction_id"])) { try parse(noTx + "\n" + "1\n", .tr) }
    }

    @Test func tradeRepublicDayOnlyRowAndNonEuroAreHandled() throws {
        let rows = [
            ["date": "2026-11-18", "category": "CASH", "type": "TRANSFER_INBOUND", "amount": "50.00", "currency": "EUR", "transaction_id": "d1"],
            ["datetime": "2026-11-18T10:00:00Z", "category": "CASH", "amount": "-5.00", "currency": "USD", "transaction_id": "d2"],
        ]
        let csv = ([trHeaders.joined(separator: ",")] + rows.map(trLine)).joined(separator: "\n") + "\n"
        let s = try parse(csv, .tr)
        #expect(s.records.count == 1)
        #expect(s.records[0].timing == .transactionDay(at(11, 18, 12)))
        #expect(s.ignoredRows == 1)
    }

    // MARK: Importar

    @Test func importIsIdempotent() throws {
        let s = try parse(revolutCSV, .rev)
        var l = Ledger()
        let first = l.importStatement(s, now: at(11, 20), calendar: madrid)
        #expect(first.added == 3)
        let snapshot = l.state
        let second = l.importStatement(s, now: at(11, 20, 13), calendar: madrid)
        #expect(second.added == 0)
        #expect(second.alreadyThere == 3)
        #expect(l.state == snapshot)
    }

    @Test func importLinksCaptured() throws {
        let s = try parse(revolutCSV, .rev)
        let capture = Movement(bank: .rev, amountCents: -1250, merchant: "Mercadona", kind: .payment, source: .notification,
                               date: at(11, 18, 13, 6), fingerprint: "fp")
        var l = Ledger(state: LedgerState(movements: [capture]))
        let before = l.state
        let preview = l.previewImport(s, now: at(11, 20), calendar: madrid)
        #expect(preview.added == 2)
        #expect(preview.linked == 1)
        #expect(l.state == before)
        #expect(importSummary(preview) == "2 movimientos nuevos, 1 ya estaba, 3 filas ignoradas")
        let real = l.importStatement(s, now: at(11, 20), calendar: madrid)
        #expect(real.added == preview.added && real.linked == preview.linked && real.ignoredRows == preview.ignoredRows)
        #expect(l.state.movements.count == 3)
    }

    @Test func csvAfterApiAddsNothing() throws {
        func bankRow(_ cents: Int, _ day: Int, _ ref: String) -> Movement {
            Movement(bank: .rev, amountCents: cents, merchant: nil, kind: cents < 0 ? .payment : .income, source: .bank,
                     date: at(11, day, 12), bankRef: ref, bankStatus: .booked, importedAt: at(11, 19), dayOnly: true)
        }
        var l = Ledger(state: LedgerState(movements: [bankRow(-2050, 16, "a"), bankRow(10_000, 17, "b"), bankRow(-1250, 18, "c")]))
        let report = l.importStatement(try parse(revolutCSV, .rev), now: at(11, 20), calendar: madrid)
        #expect(report.added == 0)
        #expect(report.linked == 3)
        #expect(l.state.movements.count == 3)
        #expect(l.state.movements.allSatisfy { $0.statementRef != nil && $0.bankRef != nil })
    }

    @Test func importSummaryCopy() {
        #expect(importSummary(ReconcileReport(added: 123, linked: 30, unchanged: 10, ignoredRows: 0))
                == "123 movimientos nuevos, 40 ya estaban")
        #expect(importSummary(ReconcileReport(added: 1, linked: 0, unchanged: 0, ignoredRows: 1))
                == "1 movimiento nuevo, 1 fila ignorada")
        #expect(importSummary(ReconcileReport(added: 0, linked: 1, unchanged: 0, ignoredRows: 2))
                == "0 movimientos nuevos, 1 ya estaba, 2 filas ignoradas")
    }

    @Test func statementBalanceAdoption() throws {
        var l = Ledger()
        l.importStatement(try parse(revolutCSV, .rev), now: at(11, 20), calendar: madrid)
        let b = try #require(l.balance(.rev))
        #expect(b.cents == 32_770)
        #expect(b.estimated == false)
        #expect(l.state.balances[.rev]?.origin == .statement)
        _ = l.ingest(.wallet(bank: .rev, amount: "5,00", merchant: "Cafe"), now: at(11, 19, 10))
        let after = try #require(l.balance(.rev))
        #expect(after.cents == 32_270)
        #expect(after.estimated == true)
    }

    @Test func captureLinkedToStatementRowIsNotCountedTwice() throws {
        // R24: capturado enlazado a una fila del extracto, con hora posterior al saldo de solo día (mediodía).
        let capture = Movement(bank: .ima, amountCents: -2345, merchant: "Mercadona", kind: .payment, source: .notification,
                               date: at(11, 18, 20), fingerprint: "fp")
        var l = Ledger(state: LedgerState(movements: [capture]))
        let report = l.importStatement(try parse(caixaCSV, .ima, now: at(11, 18, 12)), now: at(11, 18, 12), calendar: madrid)
        #expect(report.linked == 1)
        let b = try #require(l.balance(.ima))
        #expect(b.cents == 128_455)
        #expect(b.estimated == false)
    }

    // MARK: Inversión (R12) y hora (R13)

    @Test func tradesAreExcludedFromSpendingButMoveBalance() throws {
        var l = Ledger()
        l.importStatement(try parse(trCSV, .tr), now: at(11, 20), calendar: madrid)
        let byRef = Dictionary(uniqueKeysWithValues: l.state.movements.map { ($0.statementRef ?? "", $0) })
        #expect(byRef["tr|tx-3"]?.amountCents == -15_100)
        #expect(byRef["tr|tx-3"]?.excludedFromSpending == true)
        #expect(byRef["tr|tx-1"]?.excludedFromSpending == false)
        #expect(byRef["tr|tx-2"]?.excludedFromSpending == false)
        // Con un saldo a mano anterior, los tres mueven el saldo.
        var m = Ledger()
        m.setBalance(.tr, cents: 100_000, now: at(11, 1))
        m.importStatement(try parse(trCSV, .tr), now: at(11, 20), calendar: madrid)
        #expect(m.balance(.tr)?.cents == 100_000 - 1250 + 231 - 15_100)
    }

    @Test func excludedFromSpendingDecodesFromOldBooks() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"tr","amountCents":-500,"kind":"payment","source":"statement","date":2000}
        """
        let m = try JSONDecoder().decode(Movement.self, from: Data(json.utf8))
        #expect(m.excludedFromSpending == false)
        var flagged = m
        flagged.excludedFromSpending = true
        let back = try JSONDecoder().decode(Movement.self, from: JSONEncoder().encode(flagged))
        #expect(back.excludedFromSpending)
    }

    @Test func dayOnlyRowsSayTheyHaveNoRealTime() throws {
        var caixa = Ledger()
        caixa.importStatement(try parse(caixaCSV, .ima), now: at(11, 20), calendar: madrid)
        #expect(caixa.state.movements.allSatisfy { $0.dayOnly })
        var rev = Ledger()
        rev.importStatement(try parse(revolutCSV, .rev), now: at(11, 20), calendar: madrid)
        #expect(rev.state.movements.allSatisfy { !$0.dayOnly })
    }

    @Test func nonEuroStatementRowsAreNeverCounted() throws {
        let s = try parse(revolutCSV, .rev)
        #expect(!s.records.contains { $0.amountCents == -300 })
    }
}
