import Foundation

// Consulta de precios con Yahoo Finance (fuente pública y sin clave). Aquí solo se construyen las direcciones y se
// interpretan las respuestas: no hay red. Las direcciones llevan únicamente el ISIN o el símbolo, nunca importes,
// cantidades ni nombres; las respuestas se tratan como no fiables.

/// ISIN: 2 letras mayúsculas, 9 caracteres alfanuméricos y un dígito de control (Luhn sobre las letras como números).
public func isISIN(_ code: String) -> Bool {
    let chars = Array(code.utf8)
    guard chars.count == 12 else { return false }
    for (i, c) in chars.enumerated() {
        let upper = c >= 65 && c <= 90, digit = c >= 48 && c <= 57
        if i < 2 ? !upper : (i == 11 ? !digit : !(upper || digit)) { return false }
    }
    var digits: [Int] = []
    for c in chars {
        if c >= 65 {
            let n = Int(c) - 55
            digits.append(n / 10)
            digits.append(n % 10)
        } else {
            digits.append(Int(c) - 48)
        }
    }
    var sum = 0
    for (i, d) in digits.reversed().enumerated() {
        if i % 2 == 1 {
            let doubled = d * 2
            sum += doubled > 9 ? doubled - 9 : doubled
        } else {
            sum += d
        }
    }
    return sum % 10 == 0
}

/// Solo letras ASCII, dígitos, `-`, `.` y `_` pasan tal cual; cualquier otro byte se codifica (nada puede cambiar la
/// forma de la dirección).
private func encodedCode(_ code: String) -> String {
    var out = ""
    for byte in code.utf8 {
        let plain = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
            || byte == 45 || byte == 46 || byte == 95
        if plain {
            out.unicodeScalars.append(Unicode.Scalar(byte))
        } else {
            let hex = String(byte, radix: 16, uppercase: true)
            out += "%" + (hex.count == 1 ? "0" : "") + hex
        }
    }
    return out
}

private let yahooFallback = URL(string: "https://query1.finance.yahoo.com")!

public func yahooSearchURL(isin: String) -> URL {
    URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encodedCode(isin))&quotesCount=6&newsCount=0") ?? yahooFallback
}

public func yahooChartURL(symbol: String) -> URL {
    URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encodedCode(symbol))?range=5d&interval=1d") ?? yahooFallback
}

public struct YahooCandidate: Equatable, Sendable {
    public let symbol: String
    public let exchange: String?

    public init(symbol: String, exchange: String?) {
        self.symbol = symbol
        self.exchange = exchange
    }
}

/// Respuestas más grandes que esto no son de Yahoo: se descartan sin leerlas.
private let maxResponseBytes = 2_000_000

private struct SearchResponse: Decodable {
    struct Item: Decodable {
        let symbol: String?
        let exchange: String?
        private enum CodingKeys: String, CodingKey { case symbol, exchange }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            symbol = (try? c?.decodeIfPresent(String.self, forKey: .symbol)) ?? nil
            exchange = (try? c?.decodeIfPresent(String.self, forKey: .exchange)) ?? nil
        }
    }

    let quotes: [Item]?
    private enum CodingKeys: String, CodingKey { case quotes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quotes = (try? c.decodeIfPresent([Item].self, forKey: .quotes)) ?? nil
    }
}

/// Los símbolos candidatos de la búsqueda (como mucho 20, de 1 a 20 caracteres y sin espacios). Cualquier otra forma -> [].
public func yahooSearchCandidates(_ data: Data) -> [YahooCandidate] {
    guard data.count <= maxResponseBytes, let response = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
    var result: [YahooCandidate] = []
    for item in response.quotes ?? [] {
        guard let symbol = item.symbol, (1...20).contains(symbol.count),
              !symbol.contains(where: { $0.isWhitespace }) else { continue }
        result.append(YahooCandidate(symbol: symbol, exchange: item.exchange.flatMap { $0.count <= 20 ? $0 : nil }))
        if result.count == 20 { break }
    }
    return result
}

/// Símbolos por orden de preferencia: Fráncfort/XETRA (`.DE`, bolsa GER), `.F`, `.AS`, `.PA`, `.MI`, `.MC` y el resto en
/// su orden. Sin repetidos.
public func preferredSymbols(_ candidates: [YahooCandidate]) -> [String] {
    func rank(_ c: YahooCandidate) -> Int {
        let s = c.symbol.uppercased()
        if s.hasSuffix(".DE") || c.exchange?.uppercased() == "GER" { return 0 }
        for (i, suffix) in [".F", ".AS", ".PA", ".MI", ".MC"].enumerated() where s.hasSuffix(suffix) { return i + 1 }
        return 6
    }
    var seen = Set<String>()
    let unique = candidates.filter { seen.insert($0.symbol).inserted }
    return unique.enumerated().sorted {
        let a = rank($0.element), b = rank($1.element)
        return a != b ? a < b : $0.offset < $1.offset
    }.map { $0.element.symbol }
}

private struct ChartResponse: Decodable {
    struct Meta: Decodable {
        let currency: String?
        let price: Double?
        let chartPreviousClose: Double?
        let previousClose: Double?
        private enum CodingKeys: String, CodingKey { case currency, regularMarketPrice, chartPreviousClose, previousClose }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? nil
            price = (try? c.decodeIfPresent(Double.self, forKey: .regularMarketPrice)) ?? nil
            chartPreviousClose = (try? c.decodeIfPresent(Double.self, forKey: .chartPreviousClose)) ?? nil
            previousClose = (try? c.decodeIfPresent(Double.self, forKey: .previousClose)) ?? nil
        }
    }

    struct Result: Decodable { let meta: Meta? }
    struct Chart: Decodable { let result: [Result]? }
    let chart: Chart?
}

/// Un precio razonable: finito y entre 0,0001 y 1.000.000.000. Se convierte por su texto más corto para no arrastrar
/// el error binario (108.5 es 108,5).
private func plausiblePrice(_ value: Double?) -> Decimal? {
    guard let value, value.isFinite, value >= 0.0001, value <= 1_000_000_000 else { return nil }
    return Decimal(string: "\(value)", locale: nil)
}

/// Precio y cierre anterior del primer resultado del gráfico, con su divisa; nil si falta el precio o la divisa o algo
/// no tiene la forma esperada. Ojo: con `range=5d` el cierre anterior de Yahoo puede ser el de antes del rango.
public func yahooChartQuote(_ data: Data, fetchedAt: Date) -> (quote: Quote, currency: String)? {
    guard data.count <= maxResponseBytes,
          let response = try? JSONDecoder().decode(ChartResponse.self, from: data),
          let meta = response.chart?.result?.first?.meta,
          let currency = meta.currency, (1...8).contains(currency.count),
          let price = plausiblePrice(meta.price) else { return nil }
    let previous = plausiblePrice(meta.chartPreviousClose) ?? plausiblePrice(meta.previousClose)
    return (Quote(priceEUR: price, previousCloseEUR: previous, fetchedAt: fetchedAt), currency)
}

/// Símbolo de Yahoo para una cripto de la exportación ("ETH" -> "ETH-EUR"); nil si no es cripto o el código no son de
/// 2 a 10 letras o dígitos mayúsculos.
public func cryptoSymbol(instrument: String, assetClass: String?) -> String? {
    guard (assetClass ?? "").uppercased() == "CRYPTO", (2...10).contains(instrument.count),
          instrument.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { return nil }
    return instrument + "-EUR"
}

/// Los precios se piden como mucho cada 15 minutos (900 s); un reloj atrasado cuenta como "toca".
public func shouldRefreshPrices(lastFetch: Date?, now: Date) -> Bool {
    guard let lastFetch else { return true }
    let elapsed = now.timeIntervalSince(lastFetch)
    return elapsed < 0 || elapsed >= 900
}
