import Foundation

/// Limpia el nombre de un comercio para buscarlo en el directorio y en palabras clave, sin alterar el texto guardado:
/// - quita prefijos de pasarela de pago (`SUMUP *`, `ZTL*`, `ZETTLE_*`, `PAYPAL *`, `SQ *`, `STRIPE*`, `IZ *`, `CRV*`, `GOOGLE *`, `APPLE.COM/BILL`) sin romper `Apple`, `Google` ni `PayPal` cuando van solos;
/// - elimina asteriscos y separadores raros, pasando a minúsculas y sin tildes;
/// - quita formas jurídicas (`SL`, `S.L.`, `SLU`, `SA`, `S.A.`, `SAU`, `SRL`, `SLL`, `SLNE`, `LTD`, `LIMITED`, `GMBH`, `BV`, `SAS`, `INC`, `LLC`, `PLC`, `CORP`, `S.COOP.`);
/// - quita ciudades y provincias españolas y código país (`ES`/`ESP`) al final;
/// - quita números de tienda/sucursal (`1234`, `#42`, `TIENDA 12`, `SUC 05`) y códigos de referencia al final, sin romper marcas con número (`100 Montaditos`, `O2`, `Todo a 100`).
public func cleanMerchantName(_ raw: String) -> String {
    let folded = foldKeepingSeparators(raw)
    guard !folded.isEmpty else { return "" }

    if let appleResult = stripAppleBillPrefix(folded) {
        if appleResult.isStandaloneApple { return "apple" }
        return cleanTokens(from: appleResult.remainder)
    }

    let withoutGateway = stripGatewayPrefixes(folded)
    let cleaned = cleanTokens(from: withoutGateway)
    if !cleaned.isEmpty { return cleaned }
    return cleanTokens(from: folded)
}

// MARK: - Plegado y pasarelas

private let cleanerAccentFree: [Character: Character] = [
    "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u",
    "ñ": "n", "ç": "c",
]

/// Minúsculas, sin tildes, sin apóstrofos; conserva `*`, `/`, `_`, `.`, `#` para reconocer pasarelas y siglas con puntos.
private func foldKeepingSeparators(_ raw: String) -> String {
    var out = ""
    out.reserveCapacity(raw.count)
    var lastWasSpace = true
    for ch in raw.lowercased() {
        if ch == "'" || ch == "’" || ch == "`" || ch == "´" { continue }
        let mapped: Character
        if let plain = cleanerAccentFree[ch] {
            mapped = plain
        } else if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "*" || ch == "/" || ch == "_" || ch == "." || ch == "#") {
            mapped = ch
        } else {
            mapped = " "
        }
        if mapped == " " {
            if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        } else {
            out.append(mapped)
            lastWasSpace = false
        }
    }
    if out.last == " " { out.removeLast() }
    return out
}

private let appleBillingNoises: Set<String> = ["itunes", "itunes.com", "cork", "dublin", "ie", "ireland", "bill"]

/// `APPLE.COM/BILL` solo (o con `itunes.com`/`cork`/`ie`/referencia) -> `"apple"`;
/// `APPLE.COM/BILL *SPOTIFY` -> `"spotify"`.
private func stripAppleBillPrefix(_ text: String) -> (isStandaloneApple: Bool, remainder: String)? {
    guard text == "apple.com/bill" || text.hasPrefix("apple.com/bill ") || text.hasPrefix("apple.com/bill*") else {
        return nil
    }
    let after = text.dropFirst("apple.com/bill".count)
        .drop(while: { $0 == " " || $0 == "*" || $0 == "_" || $0 == "/" })
    let remainder = String(after)
    if remainder.isEmpty { return (true, "") }
    let words = remainder.split(whereSeparator: { $0 == " " || $0 == "*" || $0 == "_" || $0 == "/" }).map(String.init)
    if words.allSatisfy({ appleBillingNoises.contains($0) || isStoreNumberOrCode($0) }) {
        return (true, "")
    }
    return (false, remainder)
}

/// Pasarelas que se reconocen con `*` o `_` detrás (`SUMUP *`, `ZTL*`, `ZETTLE_*`, `PAYPAL *`, `SQ *`, `STRIPE*`, `IZ *`, `CRV*`, `GOOGLE *`).
private let starredGateways: [String] = [
    "izettle", "zettle", "square", "stripe", "paypal", "google", "sumup", "ztl", "crv", "sq", "iz", "pp",
]

/// Pasarelas inequívocas que también pueden venir separadas por espacio (tras `cleanBankMerchant`, p. ej. `PAYPAL *1234 FNAC` -> `Paypal Fnac`).
private let spacedGateways: [String] = [
    "izettle ", "zettle ", "stripe ", "paypal ", "sumup ", "ztl ",
]

private func stripGatewayPrefixes(_ text: String) -> String {
    var current = text
    stripping: while true {
        for gw in starredGateways {
            if let rest = dropStarredGateway(gw, from: current), !rest.isEmpty {
                current = rest
                continue stripping
            }
        }
        for gw in spacedGateways where current.hasPrefix(gw) {
            let rest = String(current.dropFirst(gw.count)).trimmingCharacters(in: CharacterSet(charactersIn: " *_/."))
            if !rest.isEmpty {
                current = rest
                continue stripping
            }
        }
        break
    }
    return current
}

private func dropStarredGateway(_ gateway: String, from text: String) -> String? {
    guard text.hasPrefix(gateway) else { return nil }
    var rest = text.dropFirst(gateway.count)
    rest = rest.drop(while: { $0 == " " })
    guard let first = rest.first, first == "*" || first == "_" else { return nil }
    rest = rest.drop(while: { $0 == "*" || $0 == "_" || $0 == " " })
    return String(rest)
}

// MARK: - Tokenización, formas jurídicas, ciudades y códigos de tienda

private func cleanTokens(from text: String) -> String {
    // Eliminamos formas jurídicas con puntos antes de perder los puntos, solo si van tras la primera palabra.
    let withoutDottedLegal = stripInternalDottedLegal(text)
    var tokens = tokenizeASCII(withoutDottedLegal)
    guard !tokens.isEmpty else { return "" }

    // 1. Quitar formas jurídicas inequívocas en posición interior (tras la primera palabra), p. ej. «PRIMARK TIENDAS SLU GRAN VIA MADRID».
    if tokens.count > 1 {
        let first = tokens[0]
        let rest = tokens.dropFirst().filter { !unambiguousInternalLegalTokens.contains($0) }
        tokens = [first] + rest
    }

    // 2. Pelar sufijos desde el final en bucle: país, ciudades/provincias, formas jurídicas, etiquetas/números de tienda y códigos de referencia.
    peeling: while tokens.count > 1 {
        // 2a. Código país al final (`ES`, `ESP`).
        if let last = tokens.last, trailingCountryCodes.contains(last) {
            tokens.removeLast()
            continue peeling
        }

        // 2b. Ciudades y provincias españolas de varias palabras al final.
        for place in multiWordSpanishPlaces where place.count < tokens.count && Array(tokens.suffix(place.count)) == place {
            tokens.removeLast(place.count)
            continue peeling
        }

        // 2c. Ciudades y provincias españolas de una palabra al final.
        if let last = tokens.last, singleWordSpanishPlaces.contains(last) {
            tokens.removeLast()
            continue peeling
        }

        // 2d. Formas jurídicas al final (de varias palabras o de una palabra, incluida `SA`).
        for suffix in trailingLegalSuffixes where suffix.count < tokens.count && Array(tokens.suffix(suffix.count)) == suffix {
            tokens.removeLast(suffix.count)
            continue peeling
        }

        // 2e. Etiqueta de tienda/sucursal + número o código al final (`TIENDA 12`, `SUC 05`, `REF 9981`).
        if tokens.count > 2,
           storeNumberLabels.contains(tokens[tokens.count - 2]),
           isStoreNumberOrCode(tokens[tokens.count - 1]) {
            tokens.removeLast(2)
            continue peeling
        }

        // 2f. Número de tienda o código de referencia al final, protegiendo «Todo a 100».
        if let last = tokens.last, isStoreNumberOrCode(last) {
            let prev = tokens[tokens.count - 2]
            if last == "100" && prev == "a" { break peeling }
            tokens.removeLast()
            continue peeling
        }

        break
    }

    return tokens.joined(separator: " ")
}

/// Quita formas jurídicas con puntos (`s.l.u.`, `s.a.u.`, `s.l.`, `s.a.`, `s.r.l.`, `s.a.s.`, `b.v.`, `s.coop.`)
/// cuando aparecen como palabra separada después del primer token.
private func stripInternalDottedLegal(_ text: String) -> String {
    let rawWords = text.split(separator: " ").map(String.init)
    guard rawWords.count > 1 else { return text }
    var kept: [String] = [rawWords[0]]
    for word in rawWords.dropFirst() {
        let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: "*/_#"))
        if dottedLegalForms.contains(trimmed) { continue }
        kept.append(word)
    }
    return kept.joined(separator: " ")
}

private func tokenizeASCII(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for ch in text {
        if ch.isASCII && (ch.isLetter || ch.isNumber) {
            current.append(ch)
        } else if !current.isEmpty {
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

/// true si el token parece un número de tienda/sucursal (`1234`, `05`, `42`) o un código de referencia alfanumérico (`p1a2b3c4`, `2k4`, `es93821a`),
/// sin tocar nombres cortos legítimos como `o2`, `ps5`, `3d` o `24h`.
private func isStoreNumberOrCode(_ token: String) -> Bool {
    guard !token.isEmpty else { return false }
    var letters = 0
    var digits = 0
    for ch in token {
        if ch.isASCII && ch.isNumber {
            digits += 1
        } else if ch.isASCII && ch.isLetter {
            letters += 1
        } else {
            return false
        }
    }
    if letters == 0 { return digits > 0 }
    guard digits > 0 else { return false }
    if token == "24h" { return false }
    if token.count >= 5 { return true }
    if let first = token.first, first.isNumber, token.count >= 3 { return true }
    if token.count >= 4, digits >= 2 { return true }
    return false
}

// MARK: - Tablas de sufijos y lugares

private let dottedLegalForms: Set<String> = [
    "s.l.", "s.l", "s.l.u.", "s.l.u", "s.l.l.", "s.l.l", "s.l.n.e.", "s.l.n.e",
    "s.a.", "s.a", "s.a.u.", "s.a.u", "s.r.l.", "s.r.l", "s.a.s.", "s.a.s",
    "b.v.", "b.v", "c.b.", "c.b", "s.c.p.", "s.c.p", "s.coop.", "s.coop",
]

/// Formas jurídicas inequívocas que pueden borrarse incluso en posición interior (nunca `sa`, que en Baleares es artículo).
private let unambiguousInternalLegalTokens: Set<String> = [
    "sl", "slu", "sll", "slne", "sau", "srl", "sas", "ltd", "limited", "gmbh", "bv", "inc", "llc", "plc", "corp", "sarl", "scoop",
]

private let trailingLegalSuffixes: [[String]] = [
    ["s", "l", "n", "e"],
    ["s", "l", "u"], ["s", "a", "u"], ["s", "l", "l"], ["s", "r", "l"], ["s", "a", "s"], ["s", "c", "p"],
    ["s", "coop"], ["s", "l"], ["s", "a"], ["b", "v"], ["c", "b"],
    ["sl"], ["slu"], ["sll"], ["slne"], ["sa"], ["sau"], ["srl"], ["sas"], ["ltd"], ["limited"],
    ["gmbh"], ["bv"], ["inc"], ["llc"], ["plc"], ["corp"], ["ag"], ["cb"], ["scp"], ["sarl"], ["scoop"],
]

private let trailingCountryCodes: Set<String> = ["es", "esp"]

private let storeNumberLabels: Set<String> = [
    "tienda", "tda", "suc", "sucursal", "num", "nro", "no", "ref", "local", "loc",
]

/// Lugares compuestos (ordenados de más palabras a menos para pelar la forma completa antes que un trozo).
private let multiWordSpanishPlaces: [[String]] = [
    ["san", "sebastian", "de", "los", "reyes"],
    ["las", "palmas", "de", "gran", "canaria"],
    ["san", "cristobal", "de", "la", "laguna"],
    ["san", "bartolome", "de", "tirajana"],
    ["san", "lorenzo", "de", "el", "escorial"],
    ["el", "puerto", "de", "santa", "maria"],
    ["san", "vicente", "del", "raspeig"],
    ["santa", "cruz", "de", "tenerife"],
    ["jerez", "de", "la", "frontera"],
    ["puerto", "de", "santa", "maria"],
    ["castellon", "de", "la", "plana"],
    ["talavera", "de", "la", "reina"],
    ["santiago", "de", "compostela"],
    ["puerto", "del", "rosario"],
    ["el", "prat", "de", "llobregat"],
    ["sant", "cugat", "del", "valles"],
    ["vilanova", "i", "la", "geltru"],
    ["donostia", "san", "sebastian"],
    ["palma", "de", "mallorca"],
    ["alcala", "de", "henares"],
    ["torrejon", "de", "ardoz"],
    ["las", "rozas", "de", "madrid"],
    ["pozuelo", "de", "alarcon"],
    ["boadilla", "del", "monte"],
    ["hospitalet", "de", "llobregat"],
    ["roquetas", "de", "mar"],
    ["molina", "de", "segura"],
    ["comunidad", "de", "madrid"],
    ["castilla", "la", "mancha"],
    ["castilla", "y", "leon"],
    ["san", "sebastian"],
    ["a", "coruna"],
    ["la", "coruna"],
    ["las", "palmas"],
    ["gran", "canaria"],
    ["santa", "cruz"],
    ["ciudad", "real"],
    ["las", "rozas"],
    ["rivas", "vaciamadrid"],
    ["collado", "villalba"],
    ["dos", "hermanas"],
    ["la", "linea"],
    ["el", "ejido"],
    ["san", "fernando"],
    ["la", "laguna"],
    ["l", "hospitalet"],
    ["sant", "cugat"],
    ["santa", "coloma"],
    ["vitoria", "gasteiz"],
    ["la", "rioja"],
    ["pais", "vasco"],
    ["illes", "balears"],
    ["islas", "baleares"],
    ["islas", "canarias"],
    ["el", "prat"],
    ["velez", "malaga"],
    ["torre", "pacheco"],
    ["el", "escorial"],
    ["tres", "cantos"],
]

private let singleWordSpanishPlaces: Set<String> = [
    // Capitales, provincias y ciudades principales
    "madrid", "barcelona", "valencia", "sevilla", "zaragoza", "malaga", "murcia", "palma", "bilbao", "bilbo",
    "alicante", "alacant", "cordoba", "valladolid", "vigo", "gijon", "xixon", "hospitalet", "vitoria", "gasteiz",
    "coruna", "elche", "elx", "granada", "terrassa", "tarrasa", "badalona", "oviedo", "sabadell", "cartagena",
    "jerez", "mostoles", "pamplona", "iruna", "almeria", "alcala", "fuenlabrada", "leganes", "donostia", "getafe",
    "burgos", "albacete", "santander", "castellon", "castello", "alcorcon", "logrono", "badajoz", "marbella",
    "salamanca", "huelva", "lleida", "lerida", "tarragona", "torrejon", "parla", "mataro", "algeciras", "reus",
    "ourense", "orense", "girona", "gerona", "barakaldo", "lugo", "caceres", "cadiz", "jaen", "guadalajara",
    "toledo", "pontevedra", "palencia", "segovia", "avila", "cuenca", "huesca", "teruel", "soria", "zamora", "leon",
    // Comunidades, islas y ciudades autónomas
    "alava", "araba", "vizcaya", "bizkaia", "guipuzcoa", "gipuzkoa", "navarra", "asturias", "cantabria", "rioja",
    "galicia", "cataluna", "catalunya", "aragon", "andalucia", "extremadura", "canarias", "baleares", "balears",
    "euskadi", "tenerife", "mallorca", "menorca", "ibiza", "eivissa", "lanzarote", "fuerteventura", "ceuta", "melilla",
    // Otros municipios frecuentes en extractos
    "coslada", "alcobendas", "pozuelo", "majadahonda", "valdemoro", "aranjuez", "arganda", "boadilla", "pinto",
    "getxo", "irun", "benidorm", "torrevieja", "orihuela", "gandia", "paterna", "torrent", "sagunto", "fuengirola",
    "torremolinos", "benalmadena", "estepona", "mijas", "roquetas", "lorca", "chiclana", "sanlucar", "linares",
    "motril", "merida", "plasencia", "talavera", "ponferrada", "ferrol", "naron", "viladecans", "castelldefels",
    "cornella", "rubi", "manresa", "granollers", "vilanova", "sitges", "figueres", "blanes", "lloret", "salou",
    "cambrils", "cullera", "denia", "javea", "xabia", "calpe", "altea", "telde", "arona", "adeje", "arrecife",
]
