import Foundation

/// Categorías de gasto (ver spec de los planes 3 y 4, §2.3).
public enum SpendingCategory: String, Codable, CaseIterable, Sendable {
    case supermercado, comerFuera, transporte, compras, casa, suscripciones, ocio, viajes, salud, personas, efectivo, sinCategoria

    public var displayName: String {
        switch self {
        case .supermercado: "Supermercado"
        case .comerFuera: "Comer fuera"
        case .transporte: "Transporte"
        case .compras: "Compras"
        case .casa: "Casa y facturas"
        case .suscripciones: "Suscripciones"
        case .ocio: "Ocio"
        case .viajes: "Viajes"
        case .salud: "Salud"
        case .personas: "Personas"
        case .efectivo: "Efectivo"
        case .sinCategoria: "Sin categoría"
        }
    }

    public var symbolName: String {
        switch self {
        case .supermercado: "cart"
        case .comerFuera: "fork.knife"
        case .transporte: "car"
        case .compras: "bag"
        case .casa: "house"
        case .suscripciones: "repeat"
        case .ocio: "ticket"
        case .viajes: "airplane"
        case .salud: "cross.case"
        case .personas: "person.2"
        case .efectivo: "banknote"
        case .sinCategoria: "circle.dashed"
        }
    }
}

private struct KeywordRule: Sendable {
    let words: [String]
    let category: SpendingCategory
}

/// Palabras clave -> categoría. Una regla casa si todas sus palabras aparecen seguidas y enteras en el comercio.
/// Se escriben como quedan tras `normalizeMerchant` (minúsculas, sin tildes, «ñ» -> «n»). A igual número de palabras gana
/// la lista que va antes. Fuera a propósito: «china»/«chino» solas (nombres y apodos), «taller» solo (también son
/// clases), «24 horas» (le quitaría la farmacia o el parking a «Farmacia 24 horas»), «envio» (mensajerías) y peluquería,
/// barbería o estética (ninguna categoría les va: se quedan sin categoría).
private let keywordRules: [KeywordRule] = {
    let lists: [(SpendingCategory, [String])] = [
        (.supermercado, ["super", "supermercado", "mercado", "alimentacion", "fruteria", "carniceria", "panaderia",
                         // Tiendas de comida del barrio (la pastelería y la confitería, como la panadería: se compra para casa).
                         "ultramarinos", "verduleria", "charcuteria", "pescaderia", "horno", "colmado", "tienda de barrio",
                         "minimarket", "mini market", "minimercado", "hipermercado", "polleria", "pasteleria", "confiteria",
                         "frutas"]),
        (.comerFuera, ["bar", "restaurante", "cafe", "cafeteria", "pizzeria", "burger", "kebab", "taberna", "cerveceria",
                       "just eat", "uber eats", "deliveroo",
                       // Hostelería de barrio (la heladería, la churrería y la chocolatería: se toma allí).
                       "tasca", "meson", "bodega", "bodegon", "asador", "marisqueria", "heladeria", "churreria",
                       "chocolateria", "hamburgueseria", "wok", "sushi", "ramen", "tapas", "taperia", "bocateria",
                       "sidreria", "vermuteria", "gastrobar", "restaurant", "trattoria", "pub", "cocteleria",
                       "chiringuito", "cantina", "comidas", "comida rapida", "braseria", "creperia", "arroceria",
                       "pulperia", "freiduria", "bistro", "restaurante chino", "comida china", "wok chino",
                       // «Asador Horno de Leña», «Pizzería Horno de Leña»: no es una panadería.
                       "horno de lena"]),
        (.transporte, ["gasolinera", "parking", "aparcamiento", "taxi", "metro", "emt", "bus", "peaje", "cabify", "uber",
                       "autoescuela", "taller mecanico", "neumaticos", "itv"]),
        (.casa, ["luz", "agua", "iberdrola", "endesa", "naturgy", "alquiler", "comunidad", "seguro", "seguros",
                 "movistar", "vodafone", "fibra", "lavanderia", "tintoreria"]),
        (.salud, ["farmacia", "clinica", "dentista", "optica", "hospital", "fisio", "fisioterapia",
                  "herbolario", "parafarmacia", "ortopedia", "veterinario", "veterinaria"]),
        (.viajes, ["hotel", "hostal", "airbnb", "booking", "vueling", "iberia", "ryanair", "aeropuerto"]),
        (.ocio, ["cine", "teatro", "concierto", "entradas", "gimnasio", "gym", "museo"]),
        (.efectivo, ["cajero", "retirada", "atm", "reintegro"]),
        // Tiendas de todo tipo: la última lista, así «Bar La Moda» sigue siendo un bar.
        (.compras, ["bazar", "super bazar", "bazar chino", "tienda china", "multiprecio", "multiprecios", "todo a 100",
                    "todo a cien", "ferreteria", "papeleria", "libreria", "estanco", "tabacos", "drogueria", "perfumeria",
                    "zapateria", "calzados", "merceria", "jugueteria", "floristeria", "electronica", "moda", "modas",
                    "boutique", "joyeria", "relojeria", "regalos"]),
    ]
    var rules: [KeywordRule] = []
    for (category, list) in lists {
        for entry in list { rules.append(KeywordRule(words: entry.split(separator: " ").map(String.init), category: category)) }
    }
    // Las reglas de varias palabras se miran antes que las de una ("uber eats" antes que "uber").
    return rules.enumerated().sorted { a, b in
        a.element.words.count != b.element.words.count ? a.element.words.count > b.element.words.count : a.offset < b.offset
    }.map(\.element)
}()

private func containsRun(_ tokens: [String], _ words: [String]) -> Bool {
    guard !words.isEmpty, words.count <= tokens.count else { return false }
    for start in 0...(tokens.count - words.count) where Array(tokens[start..<(start + words.count)]) == words {
        return true
    }
    return false
}

/// Categoría por palabras enteras del nombre del comercio ("Bar Manolo" -> comer fuera); nil si ninguna casa.
public func keywordCategory(for merchant: String) -> SpendingCategory? {
    let tokens = normalizeMerchant(merchant).split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return nil }
    return keywordRules.first { containsRun(tokens, $0.words) }?.category
}

/// Categoría de un pago; nil para los ingresos. Orden: la del movimiento, la recordada del comercio, el directorio,
/// las suscripciones, las palabras clave, una persona (solo con prueba, ver `isPersonPayment`) y por último sin
/// categoría. Un comercio que no se conoce NO es una persona: el bar del barrio cuyo nombre en la tarjeta es el de su
/// dueño va a «Sin categoría» hasta que el dueño lo elija.
public func spendingCategory(of movement: Movement, overrides: [String: SpendingCategory],
                             subscriptionKeys: Set<String>) -> SpendingCategory? {
    guard movement.kind == .payment else { return nil }
    if let own = movement.category { return own }
    let merchant = movement.merchant ?? ""
    let key = normalizeMerchant(merchant)
    if !key.isEmpty, let remembered = overrides[key] { return remembered }
    if !key.isEmpty {
        if let domain = merchantDomain(for: merchant, isShop: movement.isShop),
           let fromDirectory = directoryCategory(forDomain: domain) { return fromDirectory }
        if subscriptionKeys.contains(key) { return .suscripciones }
        if let byWord = keywordCategory(for: merchant) { return byWord }
    }
    if isPersonPayment(movement) { return .personas }
    return .sinCategoria
}

/// Palabras de un pago A UNA PERSONA: Bizum, transferencia (y la abreviatura «transf» de los extractos), traspaso,
/// «enviado/a». «envio» solo no (hay mensajerías «Envíos Express»): cuenta como «envío a …».
private let personPaymentWords: Set<String> = [
    "bizum", "bizums", "transferencia", "transferencias", "transfer", "transf", "traspaso", "traspasos",
    "enviado", "enviada",
]

/// Palabras de un concepto genérico (Bizum, transferencias, recibos…): el «comercio» no es un comercio, así que elegir una
/// categoría para un pago así no debería aplicarse por defecto a todo lo que lleva ese texto.
private let genericPayeeWords: Set<String> = personPaymentWords.union([
    "recibo", "domiciliacion", "adeudo", "cajero", "retirada", "ingreso", "pago", "pagos", "cargo", "devolucion", "comision",
])

/// Palabras enteras del texto, sin mayúsculas ni tildes.
private func foldedWords(_ text: String) -> [String] {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}

private func saysPersonPayment(_ text: String?) -> Bool {
    guard let text else { return false }
    let words = foldedWords(text)
    return words.contains { personPaymentWords.contains($0) } || containsRun(words, ["envio", "a"])
}

/// true si hay prueba de que el pago fue a una persona: no es una compra en tienda (`isShop`) y el texto del aviso o del
/// banco lo dice («Bizum a Ana», «Transferencia a Laura», «TRANSF A FAVOR DE…», «Traspaso a ahorro», «Envío a Lucía»).
/// Se mira también el nombre que dio el banco al enlazar (`bankMerchant`): el aviso puede traer solo «Ana».
/// Un nombre a secas («Manuel García») no prueba nada.
public func isPersonPayment(_ movement: Movement) -> Bool {
    guard movement.kind == .payment, !movement.isShop else { return false }
    return saysPersonPayment(movement.merchant) || saysPersonPayment(movement.bankMerchant)
}

/// true si el texto del comercio es un concepto genérico («Bizum a Ana», «Transferencia enviada», «Recibo»): palabra
/// entera, sin mayúsculas ni tildes.
public func isGenericPayee(_ merchant: String?) -> Bool {
    guard let merchant else { return false }
    return foldedWords(merchant).contains { genericPayeeWords.contains($0) }
}
