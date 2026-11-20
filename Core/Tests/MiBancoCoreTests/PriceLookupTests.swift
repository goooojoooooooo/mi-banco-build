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

    @Test func urlsSoloLlevanElCodigo() {
        #expect(yahooSearchURL(isin: "IE00B4L5Y983").absoluteString
            == "https://query2.finance.yahoo.com/v1/finance/search?q=IE00B4L5Y983&quotesCount=6&newsCount=0")
        #expect(yahooChartURL(symbol: "EUNL.DE").absoluteString
            == "https://query1.finance.yahoo.com/v8/finance/chart/EUNL.DE?range=5d&interval=1d")
        #expect(yahooChartURL(symbol: "A B").absoluteString.contains("A%20B"))
    }

    @Test func urlsConEntradaRara() {
        // Nada que cambie la forma de la dirección: ni barras, ni & ni ?.
        let u = yahooChartURL(symbol: "X/../Y?z=1&w=2#f").absoluteString
        #expect(u.hasPrefix("https://query1.finance.yahoo.com/v8/finance/chart/"))
        #expect(u.hasSuffix("?range=5d&interval=1d"))
        #expect(u.filter { $0 == "?" }.count == 1)
        #expect(u.filter { $0 == "&" }.count == 1)
        #expect(yahooSearchURL(isin: "A&b=1").absoluteString.filter { $0 == "&" }.count == 2)
        #expect(yahooChartURL(symbol: "").host == "query1.finance.yahoo.com")
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

    @Test func grafico() throws {
        let a = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0,"chartPreviousClose":108.5}}],"error":null}}"#)
        let got = try #require(yahooChartQuote(a, fetchedAt: fetched))
        #expect(got.quote == Quote(priceEUR: 110, previousCloseEUR: Decimal(string: "108.5"), fetchedAt: fetched))
        #expect(got.currency == "EUR")
        let b = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0,"previousClose":107.25}}]}}"#)
        #expect(yahooChartQuote(b, fetchedAt: fetched)?.quote.previousCloseEUR == Decimal(string: "107.25"))
        let c = json(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":110.0}}]}}"#)
        #expect(yahooChartQuote(c, fetchedAt: fetched)?.quote.previousCloseEUR == nil)
        #expect(yahooChartQuote(json(#"{"chart":{"result":null,"error":{"code":"Not Found"}}}"#), fetchedAt: fetched) == nil)
        #expect(yahooChartQuote(json("{ esto no es json"), fetchedAt: fetched) == nil)
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
        for m in bad { #expect(yahooChartQuote(meta(m), fetchedAt: fetched) == nil, "\(m)") }
        for raw in [#"{"chart":{"result":[]}}"#, #"{"chart":null}"#, #"{"chart":[]}"#, "[]", "", "null", #"{"chart":{"result":[null]}}"#,
                    #"{"chart":{"result":[{"meta":null}]}}"#, #"{"chart":{"result":"x"}}"#] {
            #expect(yahooChartQuote(json(raw), fetchedAt: fetched) == nil, "\(raw)")
        }
        // Un cierre anterior absurdo no tumba el precio: se descarta solo ese campo.
        let q = yahooChartQuote(meta(#"{"currency":"EUR","regularMarketPrice":10,"chartPreviousClose":"x","previousClose":-1}"#), fetchedAt: fetched)
        #expect(q?.quote.priceEUR == 10)
        #expect(q?.quote.previousCloseEUR == nil)
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
