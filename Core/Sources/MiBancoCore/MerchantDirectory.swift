/// Directorio de comercios comunes en España -> dominio web principal, para poner su logo en la lista.
/// Puro y sin red: `tools/fetch_logos.py` lee los dominios de esta tabla y baja los logos que van en la app.

/// "MERCADONA Torrejón, S.A." -> "mercadona torrejon".
/// Minúsculas, sin tildes, sin apóstrofos, el resto de signos como espacio y sin sufijos societarios al final.
public func normalizeMerchant(_ raw: String) -> String {
    var out = ""
    for ch in raw.lowercased() {
        if ch == "'" || ch == "’" || ch == "`" || ch == "´" { continue }
        if let plain = accentFree[ch] {
            out.append(plain)
        } else if ch.isASCII && (ch.isLetter || ch.isNumber) {
            out.append(ch)
        } else {
            out.append(" ")
        }
    }
    var tokens = out.split(separator: " ").map(String.init)
    // Sufijos societarios al final ("S.A.", "s.l.u.", "SL", "Inc"...), tantos como haya.
    removing: while tokens.count > 1 {
        for suffix in legalSuffixes where suffix.count < tokens.count && Array(tokens.suffix(suffix.count)) == suffix {
            tokens.removeLast(suffix.count)
            continue removing
        }
        break
    }
    return tokens.joined(separator: " ")
}

/// Dominio del comercio si el directorio lo conoce ("AMZN Mktp ES*2K4" -> "amazon.es"); nil si no.
/// Supone una compra en tienda; para un movimiento real usar `logoDomain(merchant:isShop:isIncome:)`.
public func merchantDomain(for merchant: String) -> String? {
    merchantDomain(for: merchant, isShop: true)
}

/// Con `isShop` false (envíos, ingresos, avisos sin " en "), los alias cortos o ambiguos ("Zara", "Mango", "HM", "Game"...)
/// no casan nunca: pueden ser una persona o una "HM Hospitales". Con `isShop` true casan si lo que sigue
/// solo parece tienda/ciudad/número ("ZARA ES 1234 MADRID"), no otro negocio ("Mango Bar", "Shell Mercado").
public func merchantDomain(for merchant: String, isShop: Bool) -> String? {
    // Primero sobre el nombre limpio (sin pasarelas, formas jurídicas, ciudades ni códigos de tienda).
    let cleaned = cleanMerchantName(merchant).split(separator: " ").map(String.init)
    if !cleaned.isEmpty, let hit = longestAlias(in: cleaned, isShop: isShop) { return hit }

    // Respaldo sobre el nombre normalizado (cubre p. ej. «GOOGLE *Play» -> google.com, «PAYPAL *1234» -> paypal.com, «Uber BV»).
    let tokens = normalizeMerchant(merchant).split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return nil }
    var start = 0
    while start < tokens.count - 1, processorPrefixes.contains(tokens[start]) { start += 1 }
    if start > 0, let hit = longestAlias(in: Array(tokens[start...]), isShop: isShop) { return hit }
    return longestAlias(in: tokens, isShop: isShop)
}

/// El dominio cuyo logo (de la app) puede llevar un movimiento. Un ingreso que no es de una tienda
/// ("de Carlos", "Nómina") solo lleva logo si es de un servicio de pagos (Bizum, PayPal), nunca una marca.
public func logoDomain(merchant: String?, isShop: Bool, isIncome: Bool) -> String? {
    guard let merchant, let domain = merchantDomain(for: merchant, isShop: isShop) else { return nil }
    if isIncome && !isShop && !paymentServiceDomains.contains(domain) { return nil }
    return domain
}

public extension Movement {
    /// Ver `logoDomain(merchant:isShop:isIncome:)`.
    var logoDomain: String? {
        MiBancoCore.logoDomain(merchant: merchant, isShop: isShop, isIncome: kind == .income)
    }
}

/// Nombre limpio con pinta de marca ("Bershka") -> "bershka", para probar `<slug>.es` y `<slug>.com`.
/// Segunda barrera (la primera: solo se busca para pagos en tienda): nil si es genérico, corto, largo,
/// un nombre de pila ("Carlos", "Pepe García") o una palabra de diario ("Gasolina", "Regalo").
public func guessedLogoSlug(for merchant: String) -> String? {
    let tokens = normalizeMerchant(merchant).split(separator: " ").map(String.init)
    guard (1...2).contains(tokens.count) else { return nil }
    guard !tokens.contains(where: { genericMerchantWords.contains($0) || everydayWords.contains($0) }) else { return nil }
    guard let first = tokens.first, !firstNames.contains(first) else { return nil }
    if tokens.count == 1 && firstNames.contains(first) { return nil }
    let slug = tokens.joined()
    guard slug.count >= 4, slug.count <= 24, slug.contains(where: \.isLetter) else { return nil }
    return slug
}

/// Todos los dominios del directorio, sin repetir y ordenados (para el script de logos y los tests).
public var merchantDirectoryDomains: [String] {
    Array(Set(merchantAliases.map(\.domain))).sorted()
}

// MARK: - Tabla

private func longestAlias(in tokens: [String], isShop: Bool) -> String? {
    var best: (length: Int, domain: String)?
    for entry in aliasTable {
        let alias = entry.tokens
        guard alias.count <= tokens.count, Array(tokens[0..<alias.count]) == alias else { continue }
        // Algunos alias solo valen como nombre completo ("Bizum" sí; "Bizum de Laura" es una persona).
        if entry.exactOnly && alias.count != tokens.count { continue }
        if entry.ambiguous {
            guard isShop else { continue }
            let rest = tokens[alias.count...]
            if rest.contains(where: { genericMerchantWords.contains($0) || otherBusinessWords.contains($0) }) { continue }
        }
        if alias.count > (best?.length ?? 0) { best = (alias.count, entry.domain) }
    }
    return best?.domain
}

private struct AliasEntry: Sendable {
    let tokens: [String]
    let domain: String
    let exactOnly: Bool
    /// Alias corto o palabra corriente: solo en una compra en tienda (ver `merchantDomain(for:isShop:)`).
    let ambiguous: Bool
}

private let aliasTable: [AliasEntry] = merchantAliases.flatMap { entry in
    entry.aliases.map { alias in
        let normalized = normalizeMerchant(alias)
        return AliasEntry(tokens: normalized.split(separator: " ").map(String.init), domain: entry.domain,
                          exactOnly: exactOnlyDomains.contains(entry.domain), ambiguous: ambiguousAliases.contains(normalized))
    }
}

/// Alias cortos o que son palabras/nombres corrientes.
private let ambiguousAliases: Set<String> = [
    "hm", "h m", "h and m", "bp", "dia", "digi", "mango", "orange", "apple", "steam", "bolt", "shell", "zara",
    "vips", "consum", "galp", "nike", "max", "hbo", "primor", "lowi", "yelmo", "alsa", "uber", "temu", "fnac",
    "game", "tgb", "kfc", "ikea", "o2", "cex", "jysk", "tiger", "rodilla", "ginos", "lateral", "spar", "lupa",
    "veritas", "melia",
]

/// Otros negocios que pueden empezar como una marca corta ("HM Hospitales", "BP Consulting", "Orange Garden").
private let otherBusinessWords: Set<String> = [
    "hospital", "hospitales", "consulting", "consultoria", "garden", "jardin", "grill", "pub", "club", "lounge",
    "beach", "burger", "pizza", "sushi", "tapas", "studio", "estudio", "shop", "store", "bakery", "coffee",
    "academia", "escuela", "abogados", "asesoria", "inmobiliaria", "reformas", "spa", "salon",
]

/// Servicios de pago: un ingreso por ellos sí lleva su logo.
private let paymentServiceDomains: Set<String> = ["bizum.es", "paypal.com"]

/// Nombres de pila frecuentes en España (sin tildes): nunca se buscan como web.
private let firstNames: Set<String> = [
    "maria", "carmen", "ana", "isabel", "laura", "lucia", "cristina", "marta", "elena", "sara", "paula", "raquel",
    "rosa", "pilar", "dolores", "lola", "teresa", "angela", "beatriz", "julia", "alba", "irene", "silvia", "patricia",
    "nuria", "andrea", "sandra", "monica", "eva", "rocio", "sofia", "claudia", "carla", "marina", "noelia", "alicia",
    "veronica", "natalia", "lorena", "esther", "susana", "ines", "yolanda", "montse", "montserrat", "mercedes",
    "victoria", "amparo", "concepcion", "josefa", "francisca", "antonia", "manuela", "nerea", "ainhoa", "miriam",
    "celia", "olga", "rebeca", "blanca", "aurora", "emma", "valeria", "daniela", "martina", "alejandra", "sonia",
    "gloria", "belen", "lidia", "leire", "ariadna", "judith", "estela", "noa", "chloe", "jimena", "carlota",
    "antonio", "jose", "manuel", "francisco", "juan", "david", "javier", "daniel", "carlos", "jesus", "alejandro",
    "miguel", "rafael", "pedro", "pablo", "angel", "sergio", "fernando", "jorge", "luis", "alberto", "alvaro",
    "adrian", "diego", "raul", "enrique", "ramon", "vicente", "ivan", "ruben", "oscar", "andres", "joaquin",
    "santiago", "eduardo", "victor", "roberto", "jaime", "mario", "ignacio", "alfonso", "salvador", "ricardo",
    "marcos", "jordi", "emilio", "julian", "guillermo", "gabriel", "tomas", "agustin", "gonzalo", "hugo", "mateo",
    "martin", "lucas", "leo", "marc", "alex", "nicolas", "samuel", "hector", "cristian", "aitor", "iker", "unai",
    "borja", "ismael", "felix", "pepe", "paco", "manolo", "nacho", "kike", "quique", "toni", "dani", "rafa",
    "nico", "fran", "chema", "juanma", "luismi", "lucho", "mohamed", "ahmed", "andrei", "ion",
]

/// Palabras de diario que la gente escribe como concepto; no son una tienda.
private let everydayWords: Set<String> = [
    "gasolina", "regalo", "regalos", "cena", "comida", "almuerzo", "desayuno", "alquiler", "luz", "agua", "piso",
    "viaje", "fiesta", "cumple", "cumpleanos", "boda", "cerveza", "cervezas", "copas", "entradas", "deuda",
    "prestamo", "loteria", "compras", "varios", "gastos", "hucha", "ahorro", "ahorros", "familia", "mama", "papa",
]

private let accentFree: [Character: Character] = [
    "á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a",
    "é": "e", "è": "e", "ê": "e", "ë": "e",
    "í": "i", "ì": "i", "î": "i", "ï": "i",
    "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
    "ú": "u", "ù": "u", "û": "u", "ü": "u",
    "ñ": "n", "ç": "c",
]

private let legalSuffixes: [[String]] = [
    ["s", "a", "u"], ["s", "l", "u"], ["s", "a"], ["s", "l"],
    ["sa"], ["sl"], ["slu"], ["sau"], ["inc"], ["ltd"], ["llc"], ["gmbh"], ["bv"], ["srl"], ["sas"], ["plc"], ["ag"], ["cb"], ["scp"],
]

private let processorPrefixes: Set<String> = ["paypal", "pp", "sumup", "zettle", "izettle", "sq", "stripe", "www", "compra", "pago", "en", "redsys", "tpv"]

/// Palabras que delatan un comercio genérico (o un concepto, no una tienda): sin búsqueda de logo en internet.
private let genericMerchantWords: Set<String> = [
    "bar", "bares", "restaurante", "rest", "cafeteria", "cafe", "farmacia", "taxi", "parking", "aparcamiento",
    "kiosko", "kiosco", "estanco", "panaderia", "pasteleria", "fruteria", "carniceria", "pescaderia", "tienda",
    "supermercado", "super", "mercado", "bazar", "peluqueria", "gasolinera", "hotel", "hostal", "cerveceria",
    "taberna", "meson", "pizzeria", "churreria", "heladeria", "libreria", "papeleria", "ferreteria", "lavanderia",
    "clinica", "dentista", "optica", "gimnasio", "garaje", "taller", "casa", "el", "la", "los", "las", "de", "del",
    "nomina", "intereses", "interes", "transferencia", "bizum", "recibo", "pago", "ingreso", "cajero", "comision",
    "devolucion", "reembolso", "prueba", "compra", "traspaso", "abono", "cargo", "retirada", "efectivo", "cuota",
    "impuesto", "seguro", "alquiler", "luz", "agua", "gas",
]

/// Dominios cuyo alias solo casa con el nombre entero: "Bizum de Laura" es un amigo, no la marca.
private let exactOnlyDomains: Set<String> = ["bizum.es"]

/// Comercio -> dominio. Los alias se normalizan igual que el texto del aviso y casan como prefijo por palabras.
let merchantAliases: [(domain: String, aliases: [String])] = [
    // Supermercados
    ("mercadona.es", ["Mercadona"]),
    ("lidl.es", ["Lidl", "Lidl Supermercados"]),
    ("carrefour.com", ["Carrefour", "Carrefour Express", "Carrefour Market", "Carrefour Bio"]),
    ("dia.es", ["Dia", "Dia %", "Supermercados Dia", "Dia Supermercado", "Dia Supermercados", "Dia Market", "Dia & Go", "La Plaza de Dia"]),
    ("aldi.es", ["Aldi", "Aldi Supermercados"]),
    ("alcampo.es", ["Alcampo", "Mi Alcampo"]),
    ("eroski.es", ["Eroski", "Eroski Center", "Eroski City"]),
    ("consum.es", ["Consum", "Charter Consum", "Supermercados Consum", "Consum Supermercado"]),
    ("elcorteingles.es", ["El Corte Inglés", "Corte Ingles", "ECI Supermercado"]),
    ("hipercor.es", ["Hipercor"]),
    ("supercor.es", ["Supercor", "Supercor Expres"]),
    ("ahorramas.com", ["Ahorramas", "Ahorra Mas"]),
    ("bonpreuesclat.cat", ["Bonpreu", "Bon Preu", "Esclat"]),
    ("caprabo.com", ["Caprabo"]),
    ("gadis.es", ["Gadis", "Supermercados Gadis"]),
    ("froiz.com", ["Froiz", "Supermercados Froiz"]),
    ("coviran.es", ["Coviran"]),
    ("bmsupermercados.es", ["BM Supermercados", "Supermercados BM", "BM Shop"]),
    ("spar.es", ["Spar", "Eurospar", "Interspar", "Supermercados Spar", "Spar Supermercado"]),
    ("condis.es", ["Condis", "Condislife"]),
    ("lupa.com", ["Lupa", "Supermercados Lupa", "Lupa Supermercados"]),
    ("veritas.es", ["Veritas", "Supermercados Veritas", "Veritas Supermercados"]),
    ("alimerka.es", ["Alimerka"]),
    ("supermercadosmasymas.com", ["Masymas", "Mas y Mas"]),
    // Transporte y viajes
    ("renfe.com", ["Renfe", "Renfe Viajeros", "Cercanias Renfe"]),
    ("ouigo.com", ["Ouigo"]),
    ("iryo.eu", ["Iryo"]),
    ("cabify.com", ["Cabify"]),
    ("uber.com", ["Uber", "Uber Trip", "Uber BV"]),
    ("ubereats.com", ["Uber Eats", "UberEats", "Uber * Eats"]),
    ("bolt.eu", ["Bolt", "Bolt.eu"]),
    ("alsa.es", ["Alsa"]),
    ("iberia.com", ["Iberia", "Iberia Express"]),
    ("vueling.com", ["Vueling"]),
    ("ryanair.com", ["Ryanair"]),
    ("aireuropa.com", ["Air Europa"]),
    ("easyjet.com", ["easyJet", "Easy Jet"]),
    ("volotea.com", ["Volotea"]),
    ("bintercanarias.com", ["Binter", "Binter Canarias"]),
    ("metromadrid.es", ["Metro de Madrid", "Metro Madrid"]),
    ("tmb.cat", ["TMB", "Transports Metropolitans"]),
    ("blablacar.es", ["BlaBlaCar", "Bla Bla Car"]),
    ("free-now.com", ["FreeNow", "Free Now", "Mytaxi"]),
    // Combustible (gasolineras de supermercado como alias de varias palabras: ganan a la cadena de supermercado)
    ("repsol.es", ["Repsol", "Waylet", "Repsol E S", "E S Repsol"]),
    ("moeveglobal.com", ["Cepsa", "Moeve", "E S Cepsa", "E S Moeve"]),
    ("bp.com", ["BP", "BP Oil", "BP Gasolinera", "E S BP"]),
    ("shell.es", ["Shell", "Shell Gasolinera", "E S Shell"]),
    ("galp.com", ["Galp", "Galp Energia", "Galp Gasolinera", "E S Galp"]),
    ("plenoil.es", ["Plenoil", "Plenergy"]),
    ("ballenoil.es", ["Ballenoil"]),
    ("petroprix.com", ["Petroprix"]),
    ("gasolineras.carrefour.es", ["Carrefour Gasolinera", "Gasolinera Carrefour", "Carrefour E S", "E S Carrefour", "Carrefour Estacion Servicio", "Carrefour Combustible"]),
    ("gasolineras.alcampo.es", ["Alcampo Gasolinera", "Gasolinera Alcampo", "Alcampo E S", "E S Alcampo", "Alcampo Estacion Servicio", "Alcampo Combustible"]),
    // Comida a domicilio y restaurantes
    ("glovoapp.com", ["Glovo", "Glovoapp"]),
    ("just-eat.es", ["Just Eat", "JustEat"]),
    ("mcdonalds.es", ["McDonald's", "Mc Donalds", "McDonalds"]),
    ("burgerking.es", ["Burger King", "BK Espana"]),
    ("kfc.com", ["KFC", "KFC Espana", "KFC Restaurante", "Kentucky Fried Chicken"]),
    ("telepizza.es", ["Telepizza"]),
    ("dominospizza.es", ["Domino's", "Dominos Pizza"]),
    ("starbucks.es", ["Starbucks"]),
    ("vips.es", ["Vips", "Vips Smart", "Vips Cafeteria", "Vips Restaurante"]),
    ("100montaditos.com", ["100 Montaditos", "Cien Montaditos"]),
    ("thegoodburger.com", ["TGB", "The Good Burger", "TGB Burger", "TGB The Good Burger"]),
    ("rodilla.es", ["Rodilla", "Artesanos Rodilla", "Rodilla Cafe", "Rodilla Cafeteria"]),
    ("fiveguys.es", ["Five Guys"]),
    ("goiko.com", ["Goiko", "Goiko Grill"]),
    ("tacobell.com", ["Taco Bell"]),
    ("fostershollywood.es", ["Foster's Hollywood", "Fosters Hollywood"]),
    ("ginos.es", ["Ginos", "Ginos Ristorante"]),
    ("latagliatella.es", ["La Tagliatella", "Tagliatella"]),
    ("popeyes.es", ["Popeyes", "Popeyes Louisiana"]),
    ("dunkin.es", ["Dunkin", "Dunkin'", "Dunkin Coffee", "Dunkin Donuts"]),
    ("pansandcompany.com", ["Pans & Company", "Pans and Company", "Pans Company"]),
    ("lizarran.es", ["Lizarran"]),
    ("lateral.com", ["Lateral", "Grupo Lateral"]),
    ("honestgreens.com", ["Honest Greens"]),
    ("papajohns.es", ["Papa John's", "Papa Johns"]),
    ("carlsjr.es", ["Carl's Jr", "Carls Jr"]),
    ("subway.com", ["Subway"]),
    ("timhortons.es", ["Tim Hortons"]),
    ("pansgranier.com", ["Granier"]),
    ("santagloria.com", ["Santagloria"]),
    // Suscripciones y telefonía
    ("spotify.com", ["Spotify"]),
    ("netflix.com", ["Netflix"]),
    ("disneyplus.com", ["Disney+", "Disney Plus", "DisneyPlus"]),
    ("max.com", ["HBO", "HBO Max"]),
    ("primevideo.com", ["Prime Video", "Amazon Prime Video"]),
    ("apple.com", ["Apple", "Apple.com", "Apple Com Bill", "Apple Store", "App Store"]),
    ("google.com", ["Google", "Google Play", "Google One"]),
    ("youtube.com", ["YouTube", "YouTube Premium"]),
    ("dazn.com", ["DAZN"]),
    ("movistar.es", ["Movistar", "Telefonica"]),
    ("vodafone.es", ["Vodafone"]),
    ("orange.es", ["Orange", "Orange Espana", "Orange Espagne"]),
    ("masmovil.es", ["MásMóvil", "Mas Movil"]),
    ("yoigo.com", ["Yoigo"]),
    ("digimobil.es", ["Digi", "Digi Mobil", "Digi Spain"]),
    ("pepephone.com", ["Pepephone"]),
    ("o2online.es", ["O2", "O2 Espana", "O2 Telefonica", "O2 Fibra"]),
    ("simyo.es", ["Simyo"]),
    ("jazztel.com", ["Jazztel"]),
    ("finetwork.com", ["Finetwork"]),
    ("icloud.com", ["iCloud", "Apple iCloud"]),
    ("playstation.com", ["PlayStation", "PlayStation Network", "PSN", "Sony PlayStation"]),
    ("xbox.com", ["Xbox"]),
    ("nintendo.com", ["Nintendo", "Nintendo eShop"]),
    ("steampowered.com", ["Steam", "Steampowered", "Valve Steam"]),
    ("adobe.com", ["Adobe"]),
    ("microsoft.com", ["Microsoft", "MSFT"]),
    ("dropbox.com", ["Dropbox"]),
    ("openai.com", ["OpenAI", "ChatGPT"]),
    ("anthropic.com", ["Anthropic", "Claude.ai"]),
    // Tecnología, videojuegos, ropa, deporte, hogar y compras
    ("amazon.es", ["Amazon", "Amazon.es", "AMZN", "AMZN Mktp", "Amazon Mktplace", "Amazon Marketplace"]),
    ("game.es", ["GAME", "Game Store", "Game Stores", "Game Stores Iberia", "Game Espana"]),
    ("mediamarkt.es", ["MediaMarkt", "Media Markt"]),
    ("pccomponentes.com", ["PcComponentes", "PC Componentes"]),
    ("fnac.es", ["Fnac", "Fnac Espana"]),
    ("es.webuy.com", ["CeX", "CeX Webuy", "Webuy"]),
    ("worten.es", ["Worten"]),
    ("ktuin.com", ["K-tuin", "Ktuin"]),
    ("casadellibro.com", ["Casa del Libro", "La Casa del Libro"]),
    ("zara.com", ["Zara", "Zara Home", "Zara Espana"]),
    ("bershka.com", ["Bershka"]),
    ("pullandbear.com", ["Pull&Bear", "Pull and Bear", "PullandBear"]),
    ("stradivarius.com", ["Stradivarius"]),
    ("massimodutti.com", ["Massimo Dutti"]),
    ("oysho.com", ["Oysho"]),
    ("lefties.com", ["Lefties"]),
    ("mango.com", ["Mango"]),
    ("hm.com", ["H&M", "HM", "H and M", "Hennes Mauritz"]),
    ("uniqlo.com", ["Uniqlo"]),
    ("primark.com", ["Primark"]),
    ("decathlon.es", ["Decathlon"]),
    ("sprintersports.com", ["Sprinter", "Sprinter Megacentros"]),
    ("jdsports.es", ["JD Sports", "JD Sport"]),
    ("kiabi.es", ["Kiabi"]),
    ("myspringfield.com", ["Springfield"]),
    ("cortefiel.com", ["Cortefiel", "Tendam Cortefiel"]),
    ("womensecret.com", ["Women'secret", "Women Secret", "Womensecret"]),
    ("sfera.com", ["Sfera"]),
    ("footlocker.es", ["Foot Locker", "FootLocker"]),
    ("parfois.com", ["Parfois"]),
    ("scalperscompany.com", ["Scalpers"]),
    ("desigual.com", ["Desigual"]),
    ("ikea.com", ["IKEA", "Ikea Iberica", "Ikea Tienda"]),
    ("leroymerlin.es", ["Leroy Merlin"]),
    ("bauhaus.es", ["Bauhaus"]),
    ("obramat.es", ["Obramat", "Bricomart"]),
    ("bricodepot.es", ["Brico Depot", "Bricodepot"]),
    ("conforama.es", ["Conforama"]),
    ("jysk.es", ["JYSK"]),
    ("maisonsdumonde.com", ["Maisons du Monde"]),
    ("flyingtiger.com", ["Flying Tiger", "Tiger", "Tiger Stores"]),
    ("ale-hop.org", ["Ale-Hop", "Ale Hop", "Alehop"]),
    ("aliexpress.com", ["AliExpress", "Alibaba AliExpress"]),
    ("shein.com", ["Shein"]),
    ("temu.com", ["Temu"]),
    ("zalando.es", ["Zalando"]),
    ("nike.com", ["Nike"]),
    ("adidas.es", ["Adidas"]),
    ("druni.es", ["Druni"]),
    ("primor.eu", ["Primor"]),
    ("sephora.com", ["Sephora"]),
    // Salud (cadenas de farmacia y parafarmacia online; las farmacias de barrio van por palabra clave)
    ("promofarma.com", ["PromoFarma"]),
    ("atida.com", ["Atida", "Mifarma"]),
    ("dosfarma.com", ["DosFarma"]),
    // Viajes (alojamiento y agencias)
    ("booking.com", ["Booking", "Booking.com"]),
    ("airbnb.es", ["Airbnb"]),
    ("expedia.es", ["Expedia"]),
    ("edreams.es", ["eDreams"]),
    ("melia.com", ["Melia", "Melia Hotels"]),
    ("nh-hotels.com", ["NH Hoteles", "NH Hotels", "NH Hotel"]),
    // Suministros, casa y otros
    ("idealista.com", ["Idealista"]),
    ("wallapop.com", ["Wallapop"]),
    ("vinted.es", ["Vinted"]),
    ("paypal.com", ["PayPal"]),
    ("bizum.es", ["Bizum"]),
    ("endesa.com", ["Endesa", "Endesa Energia"]),
    ("iberdrola.es", ["Iberdrola"]),
    ("naturgy.es", ["Naturgy"]),
    ("totalenergies.es", ["TotalEnergies", "Total Energies"]),
    ("octopusenergy.es", ["Octopus Energy"]),
    ("holaluz.com", ["Holaluz", "Hola Luz"]),
    ("canaldeisabelsegunda.es", ["Canal de Isabel II", "Canal Isabel II", "Canal de Isabel 2", "Canal de Isabel"]),
    ("repsolluzygas.es", ["Repsol Luz", "Repsol Luz y Gas"]),
    ("aiguesdebarcelona.cat", ["Aigues de Barcelona", "Agbar"]),
    ("correos.es", ["Correos"]),
    ("lowi.es", ["Lowi"]),
    ("basic-fit.com", ["Basic-Fit", "BasicFit"]),
    ("mcfit.com", ["McFit"]),
    ("cinesa.es", ["Cinesa"]),
    ("yelmocines.es", ["Yelmo", "Yelmo Cines"]),
]

/// Dominio -> categoría de gasto. Una entrada por cada dominio de `merchantAliases` (PayPal no: depende de lo que se pague).
let merchantDomainCategories: [String: SpendingCategory] = [
    // Supermercados
    "mercadona.es": .supermercado, "lidl.es": .supermercado, "carrefour.com": .supermercado, "dia.es": .supermercado,
    "aldi.es": .supermercado, "alcampo.es": .supermercado, "eroski.es": .supermercado, "consum.es": .supermercado,
    "elcorteingles.es": .compras, "hipercor.es": .supermercado, "supercor.es": .supermercado, "ahorramas.com": .supermercado,
    "bonpreuesclat.cat": .supermercado, "caprabo.com": .supermercado, "gadis.es": .supermercado, "froiz.com": .supermercado,
    "coviran.es": .supermercado, "bmsupermercados.es": .supermercado, "spar.es": .supermercado, "condis.es": .supermercado,
    "lupa.com": .supermercado, "veritas.es": .supermercado, "alimerka.es": .supermercado, "supermercadosmasymas.com": .supermercado,
    // Transporte y combustible
    "renfe.com": .transporte, "ouigo.com": .transporte, "iryo.eu": .transporte,
    "cabify.com": .transporte, "uber.com": .transporte, "bolt.eu": .transporte,
    "alsa.es": .transporte, "metromadrid.es": .transporte, "tmb.cat": .transporte, "blablacar.es": .transporte,
    "free-now.com": .transporte, "repsol.es": .transporte, "moeveglobal.com": .transporte, "bp.com": .transporte,
    "shell.es": .transporte, "galp.com": .transporte, "plenoil.es": .transporte, "ballenoil.es": .transporte,
    "petroprix.com": .transporte, "gasolineras.carrefour.es": .transporte, "gasolineras.alcampo.es": .transporte,
    // Viajes
    "iberia.com": .viajes, "vueling.com": .viajes, "ryanair.com": .viajes, "aireuropa.com": .viajes,
    "easyjet.com": .viajes, "volotea.com": .viajes, "bintercanarias.com": .viajes,
    "booking.com": .viajes, "airbnb.es": .viajes, "expedia.es": .viajes, "edreams.es": .viajes,
    "melia.com": .viajes, "nh-hotels.com": .viajes,
    // Comer fuera
    "ubereats.com": .comerFuera, "glovoapp.com": .comerFuera, "just-eat.es": .comerFuera, "mcdonalds.es": .comerFuera,
    "burgerking.es": .comerFuera, "kfc.com": .comerFuera, "telepizza.es": .comerFuera, "dominospizza.es": .comerFuera,
    "starbucks.es": .comerFuera, "vips.es": .comerFuera, "100montaditos.com": .comerFuera, "thegoodburger.com": .comerFuera,
    "rodilla.es": .comerFuera, "fiveguys.es": .comerFuera, "goiko.com": .comerFuera, "tacobell.com": .comerFuera,
    "fostershollywood.es": .comerFuera, "ginos.es": .comerFuera, "latagliatella.es": .comerFuera, "popeyes.es": .comerFuera,
    "dunkin.es": .comerFuera, "pansandcompany.com": .comerFuera, "lizarran.es": .comerFuera, "lateral.com": .comerFuera,
    "honestgreens.com": .comerFuera, "papajohns.es": .comerFuera, "carlsjr.es": .comerFuera, "subway.com": .comerFuera,
    "timhortons.es": .comerFuera, "pansgranier.com": .comerFuera, "santagloria.com": .comerFuera,
    // Suscripciones
    "spotify.com": .suscripciones, "netflix.com": .suscripciones, "disneyplus.com": .suscripciones,
    "max.com": .suscripciones, "primevideo.com": .suscripciones, "apple.com": .suscripciones,
    "google.com": .suscripciones, "youtube.com": .suscripciones, "dazn.com": .suscripciones,
    "icloud.com": .suscripciones, "playstation.com": .suscripciones, "xbox.com": .suscripciones,
    "nintendo.com": .suscripciones, "steampowered.com": .suscripciones, "adobe.com": .suscripciones,
    "microsoft.com": .suscripciones, "dropbox.com": .suscripciones, "openai.com": .suscripciones,
    "anthropic.com": .suscripciones,
    // Casa y facturas (telefonía, luz, agua, gas, alquiler)
    "movistar.es": .casa, "vodafone.es": .casa, "orange.es": .casa, "masmovil.es": .casa, "yoigo.com": .casa,
    "digimobil.es": .casa, "pepephone.com": .casa, "lowi.es": .casa, "o2online.es": .casa, "simyo.es": .casa,
    "jazztel.com": .casa, "finetwork.com": .casa, "endesa.com": .casa, "iberdrola.es": .casa, "naturgy.es": .casa,
    "totalenergies.es": .casa, "octopusenergy.es": .casa, "holaluz.com": .casa, "canaldeisabelsegunda.es": .casa,
    "repsolluzygas.es": .casa, "aiguesdebarcelona.cat": .casa, "idealista.com": .casa,
    // Compras (tecnología, videojuegos, ropa, deporte, hogar y bricolaje)
    "amazon.es": .compras, "game.es": .compras, "mediamarkt.es": .compras, "pccomponentes.com": .compras,
    "fnac.es": .compras, "es.webuy.com": .compras, "worten.es": .compras, "ktuin.com": .compras,
    "casadellibro.com": .compras, "zara.com": .compras, "bershka.com": .compras, "pullandbear.com": .compras,
    "stradivarius.com": .compras, "massimodutti.com": .compras, "oysho.com": .compras, "lefties.com": .compras,
    "mango.com": .compras, "hm.com": .compras, "uniqlo.com": .compras, "primark.com": .compras,
    "decathlon.es": .compras, "sprintersports.com": .compras, "jdsports.es": .compras, "kiabi.es": .compras,
    "myspringfield.com": .compras, "cortefiel.com": .compras, "womensecret.com": .compras, "sfera.com": .compras,
    "footlocker.es": .compras, "parfois.com": .compras, "scalperscompany.com": .compras, "desigual.com": .compras,
    "ikea.com": .compras, "leroymerlin.es": .compras, "bauhaus.es": .compras, "obramat.es": .compras,
    "bricodepot.es": .compras, "conforama.es": .compras, "jysk.es": .compras, "maisonsdumonde.com": .compras,
    "flyingtiger.com": .compras, "ale-hop.org": .compras, "aliexpress.com": .compras, "shein.com": .compras,
    "temu.com": .compras, "zalando.es": .compras, "nike.com": .compras, "adidas.es": .compras,
    "druni.es": .compras, "primor.eu": .compras, "sephora.com": .compras, "wallapop.com": .compras,
    "vinted.es": .compras, "correos.es": .compras,
    // Salud
    "promofarma.com": .salud, "atida.com": .salud, "dosfarma.com": .salud,
    // Ocio
    "basic-fit.com": .ocio, "mcfit.com": .ocio, "cinesa.es": .ocio, "yelmocines.es": .ocio,
    // Personas
    "bizum.es": .personas,
]

/// Categoría del dominio del directorio; nil si no se conoce o depende de lo que se pague (PayPal).
public func directoryCategory(forDomain domain: String) -> SpendingCategory? {
    merchantDomainCategories[domain]
}
