import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    madrid.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let nbsp = "\u{00A0}"

private let summaryNow = at(2026, 11, 20, 9, 0)

private let fund = "IE00B4L5Y983"
private let apple = "US0378331005"

/// Una línea CSV de la exportación (importes en euros con punto, como el fichero real). Las filas se construyen
/// pasando por `parseTradeRepublicExport`, el único lector.
private func line(id: String?, dt: String, type: String, asset: String = "", name: String = "", symbol: String = "",
                  shares: String = "", price: String = "", amount: String = "", fee: String = "", tax: String = "",
                  currency: String = "EUR") -> String {
    [dt, "", "DEFAULT", "TRADING", type, asset, name, symbol, shares, price, amount, fee, tax, currency, "", id ?? ""]
        .joined(separator: ",")
}

private let header = "datetime,date,account_type,category,type,asset_class,name,symbol,shares,price,amount,fee,tax,currency,description,transaction_id"

private func rows(_ lines: [String]) throws -> [TradeRepublicRow] {
    let text = ([header] + lines).joined(separator: "\n") + "\n"
    return try parseTradeRepublicExport(try CSVTable.parse(Data(text.utf8)))
}

private let fixtureLines: [String] = [
    line(id: "tx-001", dt: "2026-03-02T09:15:00Z", type: "BUY", asset: "FUND", name: "iShares Core MSCI World", symbol: fund,
         shares: "10", price: "95.5", amount: "-955.00", fee: "-1.00", tax: "0"),
    line(id: "tx-002", dt: "2026-04-01T07:00:00Z", type: "SAVINGS_PLAN", asset: "FUND", name: "iShares Core MSCI World", symbol: fund,
         shares: "2", price: "100", amount: "-200.00"),
    line(id: "tx-003", dt: "2026-05-10T12:00:00Z", type: "SELL", asset: "FUND", name: "iShares Core MSCI World", symbol: fund,
         shares: "4", price: "110", amount: "440.00", fee: "-1.00", tax: "-3.20"),
    line(id: "tx-004", dt: "2026-05-11T18:30:00Z", type: "CARD_TRANSACTION", amount: "-12.50"),
    line(id: "tx-005", dt: "2026-06-01T10:00:00Z", type: "FREE_RECEIPT", asset: "CRYPTO", name: "Ethereum", symbol: "ETH",
         shares: "0.01", price: "2500", amount: "0"),
    line(id: "tx-006", dt: "2026-06-15T13:45:00Z", type: "BUY", asset: "STOCK", name: "Apple", symbol: apple,
         shares: "3", price: "180", amount: "-540.00", fee: "-1.00"),
    line(id: "tx-007", dt: "", type: "BUY", asset: "STOCK", name: "Apple", symbol: apple, shares: "1"),
]

private func fixture() throws -> [TradeRepublicRow] { try rows(fixtureLines) }

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("portfolio-tests-\(UUID().uuidString)")
}

private func portfolioWithFixture() throws -> Portfolio {
    var p = Portfolio()
    _ = p.merge(investmentTransactions(from: try fixture()), now: at(2026, 11, 19, 12, 0))
    return p
}

@Suite struct PortfolioTests {
    @Test func extrae() throws {
        let e = investmentTransactions(from: try fixture())
        #expect(e.transactions.map(\.id) == ["tx-001", "tx-002", "tx-003", "tx-005", "tx-006"])
        #expect(e.ignoredRows == 1)
        #expect(e.unreadableRows == 1)
    }

    @Test func compra() throws {
        let t = try #require(investmentTransactions(from: try fixture()).transactions.first { $0.id == "tx-001" })
        #expect(t.shares == 10)
        #expect(t.cashCents == -95_600)
        #expect(t.priceEUR == Decimal(string: "95.5"))
        #expect(t.instrument == fund)
        #expect(t.name == "iShares Core MSCI World")
    }

    @Test func ventaSinSignoResta() throws {
        let t = try #require(investmentTransactions(from: try fixture()).transactions.first { $0.id == "tx-003" })
        #expect(t.shares == -4)
        #expect(t.cashCents == 43_580)
        let signed = try rows([line(id: "s", dt: "2026-05-10T12:00:00Z", type: "SELL", name: "X", symbol: fund, shares: "-4",
                                     amount: "440.00")])
        #expect(investmentTransactions(from: signed).transactions.first?.shares == -4)
    }

    @Test func entregaGratuita() throws {
        let e = investmentTransactions(from: try fixture())
        let t = try #require(e.transactions.first { $0.id == "tx-005" })
        #expect(t.shares == Decimal(string: "0.01"))
        #expect(t.cashCents == 0)
        #expect(t.assetClass == "CRYPTO")
        #expect(t.acquired)
        #expect(e.notTradeRows == 0)
    }

    @Test func decimales() {
        #expect(parseDecimal("1.234,56") == Decimal(string: "1234.56"))
        #expect(parseDecimal("1,234.56") == Decimal(string: "1234.56"))
        #expect(parseDecimal("10,5") == Decimal(string: "10.5"))
        #expect(parseDecimal("10.5") == Decimal(string: "10.5"))
        #expect(parseDecimal("-955.00") == Decimal(string: "-955"))
        #expect(parseDecimal("") == nil)
    }

    @Test func decimalesHostiles() {
        for raw in ["abc", "NaN", "1e5", "--1", "1.2,3,4", "   ", "+", ".", String(repeating: "9", count: 80)] {
            #expect(parseDecimal(raw) == nil, "\(raw)")
        }
    }

    @Test func entradaExtranaNoHaceNada() throws {
        // Otra divisa, acciones ilegibles, acciones a cero, sin identificador.
        let odd = try rows([
            line(id: "u", dt: "2026-05-10T12:00:00Z", type: "BUY", name: "X", symbol: "USX", shares: "1", amount: "-10.00", currency: "USD"),
            line(id: "v", dt: "2026-05-10T12:00:00Z", type: "BUY", name: "X", symbol: fund, shares: "mucho", amount: "-10.00"),
            line(id: "w", dt: "2026-05-10T12:00:00Z", type: "BUY", name: "X", symbol: fund, shares: "0", amount: "-10.00"),
            line(id: nil, dt: "2026-05-10T12:00:00Z", type: "BUY", name: "X", symbol: fund, shares: "1", amount: "-10.00"),
        ])
        let e = investmentTransactions(from: odd)
        #expect(e.transactions.isEmpty)
        #expect(e.ignoredRows == 1)
        #expect(e.unreadableRows == 3)
    }

    @Test func posiciones() throws {
        let p = positions(from: investmentTransactions(from: try fixture()).transactions)
        #expect(p.map(\.name) == ["Apple", "Ethereum", "iShares Core MSCI World"])
        #expect(p[0].shares == 3)
        #expect(p[0].costCents == 54_100)
        #expect(p[1].shares == Decimal(string: "0.01"))
        // Entrega gratuita: sin importe no hay coste y la posición queda marcada como incompleta.
        #expect(p[1].costCents == 0)
        #expect(p[1].costIncomplete)
        #expect(!p[0].costIncomplete)
        #expect(p[2].shares == 8)
        #expect(p[2].costCents == 77_067)
    }

    @Test func ventaDeLoQueNoHay() {
        let t = InvestmentTransaction(id: "a", date: at(2026, 1, 1, 10, 0), instrument: "XX", name: "X", assetClass: nil,
                                      shares: -2, cashCents: 500, priceEUR: nil)
        #expect(positions(from: [t]).isEmpty)
    }

    @Test func reimportarNoDuplica() throws {
        let extract = investmentTransactions(from: try fixture())
        var p = Portfolio()
        let now = at(2026, 11, 19, 12, 0)
        #expect(p.merge(extract, now: now) == ImportSummary(added: 5, alreadyThere: 0, ignoredRows: 1, unreadableRows: 1))
        #expect(p.merge(extract, now: now) == ImportSummary(added: 0, alreadyThere: 5, ignoredRows: 1, unreadableRows: 1))
        #expect(p.transactions.count == 5)
        #expect(p.lastImport == now)
    }

    private func priced() throws -> Portfolio {
        var p = try portfolioWithFixture()
        let fetched = at(2026, 11, 19, 17, 35)
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: Decimal(string: "108.5"), fetchedAt: fetched)
        p.quotes[apple] = Quote(priceEUR: 200, previousCloseEUR: 202, fetchedAt: fetched)
        p.manualPrices["ETH"] = ManualPrice(priceEUR: 3000, setAt: at(2026, 11, 19, 9, 0))
        return p
    }

    @Test func valoracion() throws {
        let s = try #require(portfolioSummary(try priced(), now: summaryNow))
        let fundValue = try #require(s.positions.first { $0.id == fund })
        #expect(fundValue.valueCents == 88_000)
        #expect(fundValue.todayChangeCents == 1_200)
        #expect(fundValue.gainCents == 10_933)
        #expect(fundValue.gainTenths == 142)
        let appleValue = try #require(s.positions.first { $0.id == apple })
        #expect(appleValue.valueCents == 60_000)
        #expect(appleValue.todayChangeCents == -600)
        #expect(appleValue.gainCents == 5_900)
        let eth = try #require(s.positions.first { $0.id == "ETH" })
        #expect(eth.valueCents == 3_000)
        #expect(eth.todayChangeCents == nil)
        #expect(eth.gainCents == nil)
        #expect(eth.gainTenths == nil)
        #expect(eth.origin == .manual(at(2026, 11, 19, 9, 0)))
        #expect(s.valueCents == 151_000)
        #expect(s.todayChangeCents == 600)
        #expect(s.todayChangeTenths == 4)
        #expect(s.costCents == 131_167)
        // La ganancia solo compara las posiciones con coste completo (sin la cripto recibida gratis).
        #expect(s.gainCents == 16_833)
        #expect(s.gainTenths == 128)
        #expect(s.changeDay == at(2026, 11, 19, 0, 0))
        #expect(s.missingPrices == 0)
        #expect(s.pricedAt == at(2026, 11, 19, 17, 35))
    }

    @Test func manualMasNuevoGana() throws {
        var p = Portfolio()
        p.transactions = [InvestmentTransaction(id: "e", date: at(2026, 6, 1, 10, 0), instrument: "ETH", name: "Ethereum",
                                                assetClass: "CRYPTO", shares: 1, cashCents: -100_000, priceEUR: nil)]
        p.quotes["ETH"] = Quote(priceEUR: 2_000, previousCloseEUR: nil, fetchedAt: at(2026, 11, 19, 8, 0))
        p.manualPrices["ETH"] = ManualPrice(priceEUR: 3_000, setAt: at(2026, 11, 19, 9, 0))
        #expect(portfolioSummary(p, now: summaryNow)?.positions.first?.priceEUR == 3_000)
        p.quotes["ETH"] = Quote(priceEUR: 2_000, previousCloseEUR: nil, fetchedAt: at(2026, 11, 19, 10, 0))
        let s = try #require(portfolioSummary(p, now: summaryNow))
        #expect(s.positions.first?.priceEUR == 2_000)
        #expect(s.positions.first?.origin == .market(at(2026, 11, 19, 10, 0)))
    }

    @Test func sinPrecio() throws {
        let s = try #require(portfolioSummary(try portfolioWithFixture(), now: summaryNow))
        #expect(s.valueCents == nil)
        #expect(s.gainCents == nil)
        #expect(s.todayChangeCents == nil)
        #expect(s.missingPrices == 3)
        #expect(s.todayChangeTenths == nil)
        #expect(s.pricedAt == nil)
        #expect(s.positions.allSatisfy { $0.origin == .none && $0.valueCents == nil })
    }

    @Test func carteraVacia() {
        #expect(portfolioSummary(Portfolio(), now: summaryNow) == nil)
    }

    @Test func preciosAbsurdosNoRompen() throws {
        var p = try portfolioWithFixture()
        p.quotes[fund] = Quote(priceEUR: Decimal(string: "9999999999999999999999999999")!, previousCloseEUR: nil, fetchedAt: at(2026, 11, 19, 10, 0))
        p.quotes[apple] = Quote(priceEUR: -5, previousCloseEUR: nil, fetchedAt: at(2026, 11, 19, 10, 0))
        let s = try #require(portfolioSummary(p, now: summaryNow))
        #expect(s.missingPrices == 3)
    }

    @Test func formatos() {
        #expect(formatSignedEUR(600) == "+6,00\(nbsp)€")
        #expect(formatSignedEUR(-600) == "-6,00\(nbsp)€")
        #expect(formatSignedEUR(0) == "0,00\(nbsp)€")
        #expect(formatPercentTenths(4, signed: true) == "+0,4\(nbsp)%")
        #expect(formatPercentTenths(-25, signed: true) == "-2,5\(nbsp)%")
        #expect(formatPercentTenths(0, signed: true) == "0,0\(nbsp)%")
        #expect(formatPercentTenths(130, signed: false) == "13,0\(nbsp)%")
        #expect(formatShares(Decimal(string: "12.4")!) == "12,4")
        #expect(formatShares(Decimal(string: "0.01")!) == "0,01")
        #expect(formatShares(3) == "3")
        #expect(formatShares(Decimal(string: "1234.5")!) == "1.234,5")
        #expect(formatUnitPriceEUR(Decimal(string: "110")!) == "110,00\(nbsp)€")
        #expect(formatUnitPriceEUR(Decimal(string: "3000.5")!) == "3.000,50\(nbsp)€")
        #expect(formatUnitPriceEUR(Decimal(string: "0.0045")!) == "0,0045\(nbsp)€")
        #expect(formatUnitPriceEUR(Decimal(string: "12.34567")!) == "12,3457\(nbsp)€")
    }

    @Test func resumenDeImportacionDeCartera() {
        let full = ImportSummary(added: 14, alreadyThere: 3, ignoredRows: 22, unreadableRows: 0)
        #expect(formatPortfolioImportSummary(full)
                == "Importadas 14 operaciones nuevas · 3 ya estaban · 22 filas sin acciones ignoradas")

        let single = ImportSummary(added: 1, alreadyThere: 1, ignoredRows: 1, unreadableRows: 1,
                                   notTradeRows: 1, notAppliedTypes: ["DIVIDEND"])
        #expect(formatPortfolioImportSummary(single)
                == "Importada 1 operación nueva · 1 ya estaba · 1 fila sin acciones ignorada · 1 fila no aplicada (DIVIDEND) · 1 fila que no se pudo leer")

        let onlyNew = ImportSummary(added: 5, alreadyThere: 0, ignoredRows: 0, unreadableRows: 0)
        #expect(formatPortfolioImportSummary(onlyNew) == "Importadas 5 operaciones nuevas")

        let nothingNew = ImportSummary(added: 0, alreadyThere: 4, ignoredRows: 0, unreadableRows: 0)
        #expect(formatPortfolioImportSummary(nothingNew) == "No había operaciones nuevas · 4 ya estaban")

        let empty = ImportSummary(added: 0, alreadyThere: 0, ignoredRows: 0, unreadableRows: 0)
        #expect(formatPortfolioImportSummary(empty) == "No había operaciones nuevas")
    }

    @Test func copiaConCartera() throws {
        let p = try priced()
        let state = LedgerState()
        let t = at(2026, 11, 19, 18, 0)
        let data = try encodeBackup(state, portfolio: p, exportedAt: t)
        #expect(try decodeBackup(data).portfolio == p)
        let old = try encodeBackup(state, exportedAt: t)
        #expect(try decodeBackup(old).portfolio == nil)
        #expect(!String(decoding: old, as: UTF8.self).contains("portfolio"))
    }

    @Test func carteraTolerante() throws {
        let json = #"{"transactions":[{"id":"ok","date":0,"instrument":"AA","name":"A","shares":"2","cashCents":-10},{"id":5},"basura"],"#
            + #""quotes":{"AA":{"priceEUR":"1.5","fetchedAt":0},"BB":7},"extra":true}"#
        let p = try JSONDecoder().decode(Portfolio.self, from: Data(json.utf8))
        #expect(p.transactions.map(\.id) == ["ok"])
        #expect(p.quotes.keys.sorted() == ["AA"])
        #expect(p.manualPrices.isEmpty)
        #expect(try JSONDecoder().decode(Portfolio.self, from: Data("{}".utf8)) == Portfolio())
    }

    @Test func idaYVueltaExacta() throws {
        let p = try priced()
        let back = try JSONDecoder().decode(Portfolio.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }

    @Test func almacen() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PortfolioStore(directory: dir)
        #expect(try store.load() == Portfolio())
        let extract = investmentTransactions(from: try fixture())
        let summary = try store.update { $0.merge(extract, now: at(2026, 11, 19, 12, 0)) }
        #expect(summary.added == 5)
        #expect(try store.load().transactions.count == 5)
        #expect(try store.update { $0.merge(extract, now: at(2026, 11, 19, 12, 5)) }.added == 0)
    }
}
