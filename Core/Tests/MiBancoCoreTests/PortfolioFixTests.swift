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

private let fund = "IE00B4L5Y983"
private let header = "datetime,date,account_type,category,type,asset_class,name,symbol,shares,price,amount,fee,tax,currency,description,transaction_id"

private func line(id: String, dt: String = "2026-05-10T12:00:00Z", type: String, shares: String = "", amount: String = "",
                  symbol: String = fund) -> String {
    [dt, "", "DEFAULT", "TRADING", type, "FUND", "Fondo de prueba", symbol, shares, "", amount, "", "", "EUR", "", id]
        .joined(separator: ",")
}

private func extract(_ lines: [String]) throws -> InvestmentExtract {
    let text = ([header] + lines).joined(separator: "\n") + "\n"
    return investmentTransactions(from: try parseTradeRepublicExport(try CSVTable.parse(Data(text.utf8))))
}

private let buy10 = line(id: "b1", dt: "2026-03-01T10:00:00Z", type: "BUY", shares: "10", amount: "-1000.00")

@Suite struct PortfolioFixTests {
    // MARK: Tipos de fila

    @Test func dividendoNoCambiaLaPosicion() throws {
        let e = try extract([buy10, line(id: "d1", dt: "2026-04-01T10:00:00Z", type: "DIVIDEND", shares: "10", amount: "3.20")])
        #expect(e.transactions.map(\.id) == ["b1"])
        #expect(e.notTradeRows == 1)
        #expect(e.unreadableRows == 0)
        let p = positions(from: e.transactions)
        #expect(p.first?.shares == 10)
        #expect(p.first?.costCents == 100_000)
    }

    @Test func devolucionDeImpuestosYOtrosNoCambianNada() throws {
        let e = try extract([buy10,
                             line(id: "t1", type: "TAX_REFUND", shares: "10", amount: "4.00"),
                             line(id: "t2", type: "CORPORATE_ACTION", shares: "10", amount: "0"),
                             line(id: "t3", type: "STOCK_SPLIT", shares: "10", amount: "0"),
                             line(id: "t4", type: "spin_off", shares: "5", amount: "-10.00")])
        #expect(e.transactions.map(\.id) == ["b1"])
        #expect(e.notTradeRows == 4)
        #expect(e.notTradeTypes == ["CORPORATE_ACTION", "SPIN_OFF", "STOCK_SPLIT", "TAX_REFUND"])
        var p = Portfolio()
        let summary = p.merge(e, now: at(2026, 11, 20, 9, 0))
        #expect(summary.notTradeRows == 4)
        #expect(summary.notAppliedTypes == ["CORPORATE_ACTION", "SPIN_OFF", "STOCK_SPLIT", "TAX_REFUND"])
        #expect(summary.added == 1)
        #expect(p.transactions.count == 1)
    }

    @Test func ventaConAccionesPositivasEImporteCeroResta() throws {
        let e = try extract([buy10, line(id: "s1", dt: "2026-04-01T10:00:00Z", type: "SELL", shares: "4", amount: "0")])
        let sell = try #require(e.transactions.first { $0.id == "s1" })
        #expect(sell.shares == -4)
        #expect(positions(from: e.transactions).first?.shares == 6)
    }

    @Test func tipoVacioSigueLaRegla() throws {
        let e = try extract([line(id: "n1", type: "", shares: "4", amount: "440.00"),
                             line(id: "n2", type: "", shares: "4", amount: "-440.00"),
                             line(id: "n3", type: "", shares: "-4", amount: "-1.00")])
        #expect(e.transactions.first { $0.id == "n1" }?.shares == -4)
        #expect(e.transactions.first { $0.id == "n2" }?.shares == 4)
        #expect(e.transactions.first { $0.id == "n3" }?.shares == -4)
        #expect(e.notTradeRows == 0)
    }

    @Test func grafiasDelPlanDeAhorroYTrade() throws {
        let e = try extract([line(id: "a", type: "SAVINGS_PLAN", shares: "1", amount: "-100.00"),
                             line(id: "b", type: "Savings Plan", shares: "1", amount: "-100.00"),
                             line(id: "c", type: "savingsplan", shares: "1", amount: "-100.00"),
                             line(id: "d", type: "TRADE", shares: "-1", amount: "100.00"),
                             line(id: "e", type: "TRADE", shares: "2", amount: "-200.00"),
                             line(id: "f", type: "TRADE", shares: "2", amount: "200.00"),
                             line(id: "g", type: "buy", shares: "1", amount: "-100.00")])
        #expect(e.transactions.map(\.id) == ["a", "b", "c", "d", "e", "g"])
        #expect(e.transactions.first { $0.id == "d" }?.shares == -1)
        #expect(e.notTradeRows == 1)
    }

    // MARK: J1 — entradas de acciones que no son compra

    @Test func entradasSinCompraSumanAcciones() throws {
        let types = ["FREE_RECEIPT", "TRANSFER_IN", "SAVEBACK", "ROUND_UP", "free receipt", "Transfer-In", "saveback", "roundup"]
        let lines = types.enumerated().map { line(id: "a\($0.offset)", dt: "2026-03-0\($0.offset + 1)T10:00:00Z", type: $0.element,
                                                  shares: "1", amount: "0") }
        let e = try extract(lines)
        #expect(e.transactions.count == types.count)
        #expect(e.notTradeRows == 0)
        #expect(e.notTradeTypes.isEmpty)
        #expect(e.transactions.allSatisfy { $0.acquired && $0.shares == 1 })
        let p = try #require(positions(from: e.transactions).first)
        #expect(p.shares == Decimal(types.count))
        #expect(p.costCents == 0)
        #expect(p.costIncomplete)
    }

    @Test func entradaConImporteTieneCosteYSinImporteMarcaIncompleto() throws {
        let withCost = try extract([line(id: "t1", type: "TRANSFER_IN", shares: "5", amount: "-10.00")])
        let a = try #require(positions(from: withCost.transactions).first)
        #expect(a.costCents == 1_000)
        #expect(!a.costIncomplete)
        // Una compra normal más una entrega gratuita: el coste es el de la compra, pero la posición ya no cuenta ganancia.
        let mixed = try extract([buy10, line(id: "f1", dt: "2026-04-01T10:00:00Z", type: "FREE_RECEIPT", shares: "2", amount: "0")])
        let p = try #require(positions(from: mixed.transactions).first)
        #expect(p.shares == 12)
        #expect(p.costCents == 100_000)
        #expect(p.costIncomplete)
        var portfolio = Portfolio()
        _ = portfolio.merge(mixed, now: at(2026, 11, 20, 9, 0))
        portfolio.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: at(2026, 11, 20, 9, 0))
        let s = try #require(portfolioSummary(portfolio, now: at(2026, 11, 20, 9, 0)))
        #expect(s.valueCents == 132_000)
        #expect(s.gainCents == nil)
        #expect(s.positions.first?.gainCents == nil)
    }

    @Test func entradaGratuitaConPrecioNoInventaCoste() throws {
        let t = InvestmentTransaction(id: "f", date: at(2026, 3, 1, 10, 0), instrument: fund, name: "F", assetClass: nil, shares: 2,
                                      cashCents: 0, priceEUR: 100, acquired: true)
        #expect(positions(from: [t]).first?.costCents == 0)
        let buy = InvestmentTransaction(id: "b", date: at(2026, 3, 1, 10, 0), instrument: fund, name: "F", assetClass: nil, shares: 2,
                                        cashCents: 0, priceEUR: 100)
        #expect(positions(from: [buy]).first?.costCents == 20_000)
    }

    @Test func traspasoDeSalidaQuitaAccionesSinGanancia() throws {
        let e = try extract([buy10, line(id: "o1", dt: "2026-04-01T10:00:00Z", type: "TRANSFER_OUT", shares: "4", amount: "0")])
        let out = try #require(e.transactions.first { $0.id == "o1" })
        #expect(out.shares == -4)
        #expect(e.notTradeRows == 0)
        let p = try #require(positions(from: e.transactions).first)
        #expect(p.shares == 6)
        #expect(p.costCents == 60_000)
    }

    @Test func laMarcaDeEntradaSobreviveALaCopia() throws {
        let t = InvestmentTransaction(id: "f", date: at(2026, 3, 1, 10, 0), instrument: fund, name: "F", assetClass: nil, shares: 2,
                                      cashCents: 0, priceEUR: nil, acquired: true)
        let back = try JSONDecoder().decode(InvestmentTransaction.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        #expect(back.acquired)
        let old = try JSONDecoder().decode(InvestmentTransaction.self,
                                           from: Data(#"{"id":"o","date":0,"instrument":"AA","name":"A","shares":"2","cashCents":-10}"#.utf8))
        #expect(!old.acquired)
    }

    // MARK: J2 — día del cambio y cierre anterior

    @Test func cambioPerteneceAlDiaDelPrecio() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund()
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: 109, fetchedAt: now, marketTime: at(2026, 11, 19, 17, 30))
        let s = try #require(portfolioSummary(p, now: now, calendar: madrid))
        #expect(s.changeDay == at(2026, 11, 19, 0, 0))
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: at(2026, 11, 19, 17, 30))
        #expect(try #require(portfolioSummary(p, now: now, calendar: madrid)).changeDay == nil)
    }

    @Test func cierreAnteriorConLaSerieAcabadaElDiaAnterior() throws {
        // Mercado el 20 (vie) pero la serie acaba el jueves 19: el cierre anterior es el del 19, no el penúltimo de la serie.
        let data = Data((#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.5,"gmtoffset":3600,"regularMarketTime":1795186800},"#
            + #""timestamp":[1794556800,1794816000,1794902400,1794988800,1795075200],"#
            + #""indicators":{"quote":[{"close":[100.0,101.0,102.0,103.0,104.5]}]}}]}}"#).utf8)
        guard case .success(let q) = yahooChartQuote(data, fetchedAt: at(2026, 11, 20, 9, 0)) else {
            Issue.record("sin precio")
            return
        }
        #expect(q.previousCloseEUR == Decimal(string: "104.5"))
    }

    // MARK: Empates de fecha

    @Test func compraYVentaConLaMismaHoraSeAplicanEnOrden() throws {
        let when = at(2026, 5, 10, 12, 0)
        // La venta tiene un id que va antes que el de la compra: da igual.
        let sell = InvestmentTransaction(id: "a-sell", date: when, instrument: fund, name: "F", assetClass: nil, shares: -4,
                                         cashCents: 44_000, priceEUR: nil)
        let buy = InvestmentTransaction(id: "z-buy", date: when, instrument: fund, name: "F", assetClass: nil, shares: 10,
                                        cashCents: -100_000, priceEUR: nil)
        for list in [[sell, buy], [buy, sell]] {
            let p = positions(from: list)
            #expect(p.first?.shares == 6)
            #expect(p.first?.costCents == 60_000)
        }
        var portfolio = Portfolio()
        _ = portfolio.merge(InvestmentExtract(transactions: [sell, buy], ignoredRows: 0, unreadableRows: 0), now: when)
        #expect(portfolio.transactions.map(\.id) == ["z-buy", "a-sell"])
        #expect(positions(from: portfolio.transactions).first?.shares == 6)
    }

    @Test func mismoDiaConservaElOrden() {
        let when = at(2026, 5, 10, 12, 0)
        func buy(_ id: String) -> InvestmentTransaction {
            InvestmentTransaction(id: id, date: when, instrument: fund, name: "F", assetClass: nil, shares: 1, cashCents: -100, priceEUR: nil)
        }
        var portfolio = Portfolio()
        _ = portfolio.merge(InvestmentExtract(transactions: [buy("z"), buy("a"), buy("m")], ignoredRows: 0, unreadableRows: 0), now: when)
        #expect(portfolio.transactions.map(\.id) == ["z", "a", "m"])
    }

    // MARK: Edad y honestidad de los precios

    private func ownedFund(cashCents: Int = -100_000) -> Portfolio {
        var p = Portfolio()
        p.transactions = [InvestmentTransaction(id: "b", date: at(2026, 3, 1, 10, 0), instrument: fund, name: "F", assetClass: nil,
                                                shares: 10, cashCents: cashCents, priceEUR: nil)]
        return p
    }

    @Test func precioViejoPorSuHoraDeMercado() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund()
        // Consultado ahora, pero el mercado cerró hace seis días.
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: at(2026, 11, 14, 17, 30))
        let s = try #require(portfolioSummary(p, now: now))
        #expect(s.hasStalePrice)
        #expect(s.oldestPriceAt == at(2026, 11, 14, 17, 30))
        #expect(s.pricedAt == at(2026, 11, 14, 17, 30))
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: at(2026, 11, 19, 17, 30))
        #expect(try #require(portfolioSummary(p, now: now)).hasStalePrice == false)
        // Sin hora de mercado se usa la de la consulta.
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: at(2026, 11, 10, 9, 0))
        #expect(try #require(portfolioSummary(p, now: now)).hasStalePrice)
    }

    @Test func cuatroDiasExactosNoEsViejo() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund()
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: now.addingTimeInterval(-4 * 86_400))
        #expect(try #require(portfolioSummary(p, now: now)).hasStalePrice == false)
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: now.addingTimeInterval(-4 * 86_400 - 1))
        #expect(try #require(portfolioSummary(p, now: now)).hasStalePrice)
    }

    @Test func masAntiguoYMasNuevoEntreVarios() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund()
        p.transactions.append(InvestmentTransaction(id: "b2", date: at(2026, 3, 2, 10, 0), instrument: "ETH", name: "Ethereum",
                                                    assetClass: "CRYPTO", shares: 1, cashCents: -50_000, priceEUR: nil))
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: at(2026, 11, 19, 17, 30))
        p.manualPrices["ETH"] = ManualPrice(priceEUR: 600, setAt: at(2026, 11, 1, 9, 0))
        let s = try #require(portfolioSummary(p, now: now))
        #expect(s.pricedAt == at(2026, 11, 19, 17, 30))
        #expect(s.oldestPriceAt == at(2026, 11, 1, 9, 0))
        #expect(s.hasStalePrice)
    }

    @Test func sinPreciosElValorEsNilNoCero() throws {
        let s = try #require(portfolioSummary(ownedFund(), now: at(2026, 11, 20, 9, 0)))
        #expect(s.valueCents == nil)
        #expect(s.gainCents == nil)
        #expect(s.gainTenths == nil)
        #expect(s.oldestPriceAt == nil)
        #expect(s.hasStalePrice == false)
        #expect(s.missingPrices == 1)
    }

    @Test func costeCeroNoDaGanancia() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund(cashCents: 0)
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: 109, fetchedAt: now, marketTime: now)
        let s = try #require(portfolioSummary(p, now: now))
        let position = try #require(s.positions.first)
        #expect(position.valueCents == 110_000)
        #expect(position.gainCents == nil)
        #expect(position.gainTenths == nil)
        #expect(s.valueCents == 110_000)
        #expect(s.gainCents == nil)
        #expect(s.costCents == 0)
    }

    @Test func cambioDeHoyAusenteEsNil() throws {
        let now = at(2026, 11, 20, 9, 0)
        var p = ownedFund()
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: nil, fetchedAt: now, marketTime: now)
        let s = try #require(portfolioSummary(p, now: now))
        #expect(s.todayChangeCents == nil)
        #expect(s.todayChangeTenths == nil)
        #expect(s.valueCents == 110_000)
    }

    @Test func horaDeMercadoViajaEnLaCartera() throws {
        var p = ownedFund()
        p.quotes[fund] = Quote(priceEUR: 110, previousCloseEUR: 109, fetchedAt: at(2026, 11, 20, 9, 0), marketTime: at(2026, 11, 19, 17, 30))
        let back = try JSONDecoder().decode(Portfolio.self, from: JSONEncoder().encode(p))
        #expect(back.quotes[fund]?.marketTime == at(2026, 11, 19, 17, 30))
        #expect(back == p)
    }

    // MARK: Copia de seguridad

    private func backupJSON(portfolio: Any?) throws -> Data {
        let data = try encodeBackup(LedgerState(), exportedAt: at(2026, 11, 20, 9, 0))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        if let portfolio { object["portfolio"] = portfolio }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func carteraRotaNoTumbaLaCopia() throws {
        for bad in [5, "texto", [1, 2], true] as [Any] {
            let file = try decodeBackup(try backupJSON(portfolio: bad))
            #expect(file.portfolio == nil)
            #expect(file.ledger == LedgerState())
            #expect(file.droppedPortfolioEntries == 1)
        }
        let nulo = try decodeBackup(try backupJSON(portfolio: NSNull()))
        #expect(nulo.portfolio == nil)
        #expect(nulo.droppedPortfolioEntries == 0)
        let sin = try decodeBackup(try backupJSON(portfolio: nil))
        #expect(sin.portfolio == nil)
        #expect(sin.droppedPortfolioEntries == 0)
    }

    @Test func entradasDescartadasSeCuentan() throws {
        let good: [String: Any] = ["id": "ok", "date": 0, "instrument": "AA", "name": "A", "shares": "2", "cashCents": -10]
        let portfolio: [String: Any] = [
            "transactions": [good, 5, "basura"],
            "quotes": ["AA": ["priceEUR": "1.5", "fetchedAt": 0], "BB": 7],
            "manualPrices": "no es un diccionario",
        ]
        let file = try decodeBackup(try backupJSON(portfolio: portfolio))
        let p = try #require(file.portfolio)
        #expect(p.transactions.map(\.id) == ["ok"])
        #expect(p.quotes.keys.sorted() == ["AA"])
        // 2 transacciones + 1 cotización + la lista de precios manuales con el tipo equivocado.
        #expect(p.droppedEntries == 4)
        #expect(file.droppedPortfolioEntries == 4)
        // Una cartera limpia no descarta nada.
        let clean = try decodeBackup(try backupJSON(portfolio: ["transactions": [good]]))
        #expect(clean.droppedPortfolioEntries == 0)
    }

    @Test func listaDeTipoEquivocadoCuentaUno() throws {
        let p = try JSONDecoder().decode(Portfolio.self, from: Data(#"{"transactions":"x","quotes":[1,2],"symbols":null}"#.utf8))
        #expect(p.transactions.isEmpty)
        #expect(p.droppedEntries == 2)
        #expect(try JSONDecoder().decode(Portfolio.self, from: Data("{}".utf8)).droppedEntries == 0)
    }

    @Test func restauracionDeLaCartera() throws {
        var current = Portfolio()
        current.transactions = [InvestmentTransaction(id: "c", date: at(2026, 1, 1, 10, 0), instrument: "AA", name: "A",
                                                      assetClass: nil, shares: 1, cashCents: -100, priceEUR: nil)]
        var other = Portfolio()
        other.symbols["BB"] = "BB.DE"
        #expect(portfolioAfterRestore(current: current, backup: nil as Portfolio?) == current)
        #expect(portfolioAfterRestore(current: current, backup: other) == other)
        let withoutPortfolio = try decodeBackup(try backupJSON(portfolio: nil))
        #expect(portfolioAfterRestore(current: current, backup: withoutPortfolio) == current)
        let broken = try decodeBackup(try backupJSON(portfolio: 5))
        #expect(portfolioAfterRestore(current: current, backup: broken) == current)
        let withPortfolio = try decodeBackup(try encodeBackup(LedgerState(), portfolio: other, exportedAt: at(2026, 11, 20, 9, 0)))
        #expect(portfolioAfterRestore(current: current, backup: withPortfolio) == other)
    }
}
