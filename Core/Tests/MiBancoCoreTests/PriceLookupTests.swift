import Foundation
import Testing
@testable import MiBancoCore

private let fetched = Date(timeIntervalSince1970: 1_800_000_000)

private func json(_ s: String) -> Data { Data(s.utf8) }

@Suite struct PriceLookupTests {
    @Test func isin() {
        #expect(isISIN("IE00B4L5Y983"))
        #expect(isISIN("US0378331005"))
        #expect(!isISIN("ETH"))
        #expect(!isISIN("IE00B4L5Y984"))
        #expect(!isISIN("ie00b4l5y983"))
        #expect(!isISIN(""))
        #expect(!isISIN("IE00B4L5Y983 "))
    }

    @Test func urlsSoloLlevanElCodigo() throws {
        #expect(try #require(yahooSearchURL(isin: "IE00B4L5Y983")).absoluteString
            == "https://query2.finance.yahoo.com/v1/finance/search?q=IE00B4L5Y983&quotesCount=6&newsCount=0")
        #expect(try #require(yahooChartURL(symbol: "EUNL.DE")).absoluteString
            == "https://query1.finance.yahoo.com/v8/finance/chart/EUNL.DE?range=5d&interval=1d")
        #expect(try #require(yahooChartURL(symbol: "ETH-EUR")).absoluteString.contains("/ETH-EUR?"))
        #expect(try #require(yahooChartURL(symbol: "EURUSD=X")).absoluteString.contains("EURUSD%3DX"))
    }

    @Test func urlsConEntradaRaraDanNil() {
        // Nada que cambie la forma de la dirección y nunca una dirección de relleno.
        for raw in ["A B", "X/../Y?z=1&w=2#f", "", "eunl.de", "A&b", String(repeating: "A", count: 21), "Ñ", "A%2FB"] {
            #expect(yahooChartURL(symbol: raw) == nil, "\(raw)")
        }
        #expect(yahooChartURL(symbol: String(repeating: "A", count: 20)) != nil)
        for raw in ["A&b=1", "", "ETH", "IE00B4L5Y984", "ie00b4l5y983", "IE00B4L5Y983 "] {
            #expect(yahooSearchURL(isin: raw) == nil, "\(raw)")
        }
    }

    @Test func busqueda() {
        let data = json(#"{"quotes":[{"symbol":"IWDA.AS","exchange":"AMS"},{"symbol":"SWDA.L","exchange":"LSE"},{"symbol":"EUNL.DE","exchange":"GER"},{"symbol":"EUNL.F","exchange":"FRA"}]}"#)
        let candidates = yahooSearchCandidates(data)
        #expect(candidates.count == 4)
        #expect(candidates[0] == YahooCandidate(symbol: "IWDA.AS", exchange: "AMS"))
        #expect(preferredSymbols(candidates) == ["EUNL.DE", "EUNL.F", "IWDA.AS", "SWDA.L"])
    }

    @Test func ordenCompleto() {
        let symbols = ["A.L", "B.MC", "C.MI", "D.PA", "E.AS", "F.F", "G.DE"].map { YahooCandidate(symbol: $0, exchange: nil) }
        #expect(preferredSymbols(symbols) == ["G.DE", "F.F", "E.AS", "D.PA", "C.MI", "B.MC", "A.L"])
        #expect(preferredSymbols([YahooCandidate(symbol: "X", exchange: nil), YahooCandidate(symbol: "X", exchange: "GER")]) == ["X"])
    }

    @Test func busquedaHostil() {
        for raw in ["", "[]", "null", "{", #"{"quotes":null}"#, #"{"quotes":"x"}"#, #"{"quotes":[1,null,"a",[]]}"#,
                    #"{"quotes":[{"symbol":5},{"symbol":""},{"exchange":"GER"},{"symbol":"OK","exchange":7}]}"#] {
            let c = yahooSearchCandidates(json(raw))
            #expect(c.allSatisfy { !$0.symbol.isEmpty })
        }
        #expect(yahooSearchCandidates(json(#"{"quotes":[{"symbol":"OK","exchange":7}]}"#)) == [YahooCandidate(symbol: "OK", exchange: nil)])
        #expect(yahooSearchCandidates(json(#"{"quotes":[{"symbol":5}]}"#)).isEmpty)
        let long = String(repeating: "A", count: 500)
        #expect(yahooSearchCandidates(json(#"{"quotes":[{"symbol":"\#(long)"}]}"#)).isEmpty)
        let many = (0..<200).map { #"{"symbol":"S\#($0)"}"# }.joined(separator: ",")
        #expect(yahooSearchCandidates(json(#"{"quotes":[\#(many)]}"#)).count <= 20)
    }

    private func quote(_ data: Data) -> Quote? {
        if case .success(let q) = yahooChartQuote(data, fetchedAt: fetched) { return q }
        return nil
    }

    @Test func grafico() throws {
        let a = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0,"previousClose":108.5}}],"error":null}}"#)
        #expect(try #require(quote(a)) == Quote(priceEUR: 110, previousCloseEUR: Decimal(string: "108.5"), fetchedAt: fetched))
        let c = json(#"{"chart":{"result":[{"meta":{"currency":"eur","regularMarketPrice":110.0}}]}}"#)
        #expect(quote(c)?.previousCloseEUR == nil)
        #expect(quote(c)?.priceEUR == 110)
        #expect(yahooChartQuote(json(#"{"chart":{"result":null,"error":{"code":"Not Found"}}}"#), fetchedAt: fetched) == .failure(.unreadable))
        #expect(yahooChartQuote(json("{ esto no es json"), fetchedAt: fetched) == .failure(.unreadable))
    }

    @Test func chartPreviousCloseNuncaEsAyer() {
        // Con range=5d ese campo es el cierre de antes del rango: no se usa jamás.
        let d = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0,"chartPreviousClose":90.0}}]}}"#)
        #expect(quote(d)?.previousCloseEUR == nil)
        let e = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0,"chartPreviousClose":90.0,"previousClose":107.0}}]}}"#)
        #expect(quote(e)?.previousCloseEUR == 107)
    }

    /// Cinco barras de Fráncfort (UTC+1): vie 13, lun 16, mar 17, mié 18 (el jueves 19 no hubo barra) y vie 20 (hoy, en curso).
    private func series(closes: String, marketTime: Int = 1_795_186_800, extra: String = "") -> Data {
        json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.5,"gmtoffset":3600,"regularMarketTime":\#(marketTime)\#(extra)},"#
            + #""timestamp":[1794556800,1794816000,1794902400,1794988800,1795161600],"#
            + #""indicators":{"quote":[{"close":\#(closes)}]}}]}}"#)
    }

    @Test func cierreAnteriorDeLaSerie() throws {
        let q = try #require(quote(series(closes: "[100.0,null,102.0,103.25,110.5]", extra: #","chartPreviousClose":50.0,"previousClose":1.0"#)))
        #expect(q.previousCloseEUR == Decimal(string: "103.25"))
        #expect(q.marketTime == Date(timeIntervalSince1970: 1_795_186_800))
        #expect(q.priceEUR == Decimal(string: "110.5"))
        // El último cierre previo es nulo: se salta hasta el anterior no nulo.
        #expect(quote(series(closes: "[100.0,null,102.0,null,110.5]"))?.previousCloseEUR == 102)
        // Solo hay un día previo con cierre, el primero.
        #expect(quote(series(closes: "[100.0,null,null,null,110.5]"))?.previousCloseEUR == 100)
    }

    @Test func cierreAnteriorSinSerieUtil() {
        // Serie sin cierres válidos: cae a previousClose; sin él, no hay cambio de hoy.
        #expect(quote(series(closes: "[null,null,null,null,110.5]", extra: #","previousClose":104.0"#))?.previousCloseEUR == 104)
        #expect(quote(series(closes: "[null,null,null,null,110.5]", extra: #","chartPreviousClose":50.0"#))?.previousCloseEUR == nil)
        // Serie rota o de otro tipo: ignorada.
        #expect(quote(series(closes: #""x""#, extra: #","previousClose":104.0"#))?.previousCloseEUR == 104)
    }

    @Test func barraDeHoyNoEsElCierreAnterior() {
        // El día de negociación se mide en la zona del mercado: la barra del 20 es de hoy.
        #expect(quote(series(closes: "[100.0,101.0,102.0,103.0,109.0]"))?.previousCloseEUR == 103)
        // Si el mercado aún marca el jueves 19 (festivo, sin barra), el cierre anterior sigue siendo el del miércoles 18.
        #expect(quote(series(closes: "[100.0,101.0,102.0,103.0,109.0]", marketTime: 1_795_075_200))?.previousCloseEUR == 103)
    }

    @Test func divisaQueNoEsEuroNoSeUsa() {
        let usd = json(#"{"chart":{"result":[{"meta":{"currency":"USD","regularMarketPrice":110.0,"previousClose":108.0}}]}}"#)
        #expect(yahooChartQuote(usd, fetchedAt: fetched) == .failure(.notEUR(currency: "USD")))
        let pence = json(#"{"chart":{"result":[{"meta":{"currency":"GBp","regularMarketPrice":8250.0}}]}}"#)
        #expect(yahooChartQuote(pence, fetchedAt: fetched) == .failure(.notEUR(currency: "GBp")))
        let gbp = json(#"{"chart":{"result":[{"meta":{"currency":"GBP","regularMarketPrice":82.5}}]}}"#)
        #expect(yahooChartQuote(gbp, fetchedAt: fetched) == .failure(.notEUR(currency: "GBP")))
        #expect(PriceFailure.notEUR(currency: "USD").message == "precio no disponible en euros")
        let eur = json(#"{"chart":{"result":[{"meta":{"currency":"Eur","regularMarketPrice":110.0}}]}}"#)
        #expect(quote(eur)?.priceEUR == 110)
    }

    @Test func graficoHostil() {
        func meta(_ m: String) -> Data { json(#"{"chart":{"result":[{"meta":\#(m)}]}}"#) }
        let bad = [
            "{}", #"{"currency":"EUR"}"#, #"{"regularMarketPrice":5}"#,
            #"{"currency":"EUR","regularMarketPrice":"110"}"#, #"{"currency":"EUR","regularMarketPrice":true}"#,
            #"{"currency":"EUR","regularMarketPrice":null}"#, #"{"currency":"EUR","regularMarketPrice":0}"#,
            #"{"currency":"EUR","regularMarketPrice":-3}"#, #"{"currency":"EUR","regularMarketPrice":1e300}"#,
            #"{"currency":"EUR","regularMarketPrice":1e999}"#, #"{"currency":"EUR","regularMarketPrice":[1]}"#,
            #"{"currency":5,"regularMarketPrice":5}"#, "[]", "null", "5",
        ]
        for m in bad { #expect(quote(meta(m)) == nil, "\(m)") }
        for raw in [#"{"chart":{"result":[]}}"#, #"{"chart":null}"#, #"{"chart":[]}"#, "[]", "", "null", #"{"chart":{"result":[null]}}"#,
                    #"{"chart":{"result":[{"meta":null}]}}"#, #"{"chart":{"result":"x"}}"#] {
            #expect(quote(json(raw)) == nil, "\(raw)")
        }
        // Un cierre anterior absurdo no tumba el precio: se descarta solo ese campo.
        let q = quote(meta(#"{"currency":"EUR","regularMarketPrice":10,"previousClose":-1,"regularMarketTime":"x"}"#))
        #expect(q?.priceEUR == 10)
        #expect(q?.previousCloseEUR == nil)
        #expect(q?.marketTime == nil)
        // Marca de tiempo y series hostiles: se ignoran sin tumbar el precio.
        let h = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":10,"regularMarketTime":1795186800},"timestamp":"x","indicators":[1]}]}}"#)
        #expect(quote(h)?.priceEUR == 10)
        #expect(quote(h)?.previousCloseEUR == nil)
    }

    @Test func horaDeMercadoDelPrecioViejo() throws {
        // Consultado ahora, pero la hora del mercado es de hace seis días: la cartera lo marca como viejo.
        let now = Date(timeIntervalSince1970: 1_795_186_800)
        let old = Int(now.timeIntervalSince1970) - 6 * 86_400
        let q = try #require(quote(series(closes: "[100.0,null,102.0,103.25,110.5]", marketTime: old)))
        #expect(q.marketTime == Date(timeIntervalSince1970: TimeInterval(old)))
        var p = Portfolio()
        p.transactions = [InvestmentTransaction(id: "b", date: now.addingTimeInterval(-9_000_000), instrument: "AA", name: "A",
                                                assetClass: nil, shares: 1, cashCents: -10_000, priceEUR: nil)]
        p.quotes["AA"] = Quote(priceEUR: q.priceEUR, previousCloseEUR: q.previousCloseEUR, fetchedAt: now, marketTime: q.marketTime)
        #expect(portfolioSummary(p, now: now)?.hasStalePrice == true)
    }

    @Test func cripto() {
        #expect(cryptoSymbol(instrument: "ETH", assetClass: "CRYPTO") == "ETH-EUR")
        #expect(cryptoSymbol(instrument: "ETH", assetClass: "crypto") == "ETH-EUR")
        #expect(cryptoSymbol(instrument: "US0378331005", assetClass: "STOCK") == nil)
        #expect(cryptoSymbol(instrument: "ETH", assetClass: nil) == nil)
        #expect(cryptoSymbol(instrument: "../x", assetClass: "CRYPTO") == nil)
        #expect(cryptoSymbol(instrument: "", assetClass: "CRYPTO") == nil)
    }

    @Test func refresco() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!shouldRefreshPrices(lastFetch: now.addingTimeInterval(-899), now: now))
        #expect(shouldRefreshPrices(lastFetch: now.addingTimeInterval(-900), now: now))
        #expect(shouldRefreshPrices(lastFetch: nil, now: now))
        #expect(shouldRefreshPrices(lastFetch: now.addingTimeInterval(60), now: now))
    }
}
