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
/// clases), «24 horas» (le quitaría la farmacia o el parking a «Farmacia 24 horas»), «envio» (mensajerías), «pub»
/// (abreviatura de «público» en conceptos: «TASA ADMON PUB») y peluquería, barbería o estética (ninguna categoría les
/// va: se quedan sin categoría).
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
                       "sidreria", "vermuteria", "gastrobar", "restaurant", "trattoria", "cocteleria",
                       "chiringuito", "cantina", "comidas", "comida rapida", "braseria", "creperia", "arroceria",
                       "pulperia", "freiduria", "bistro", "comida china",
                       // «Asador Horno de Leña», «Pizzería Horno de Leña»: no es una panadería.
                       "horno de lena"]),
        (.transporte, ["gasolinera", "parking", "aparcamiento", "taxi", "metro", "emt", "bus", "peaje", "cabify", "uber",
                       "autoescuela", "taller mecanico", "neumaticos", "itv"]),
        (.casa, ["luz", "agua", "iberdrola", "endesa", "naturgy", "alquiler", "comunidad", "seguro", "seguros",
                 "movistar", "vodafone", "fibra", "lavanderia", "tintoreria"]),
        (.salud, ["farmacia", "farmacias", "clinica", "dentista", "optica", "hospital", "fisio", "fisioterapia",
                  "herbolario", "parafarmacia", "parafarmacias", "botica", "ortopedia", "veterinario", "veterinaria"]),
        (.viajes, ["hotel", "hostal", "airbnb", "booking", "vueling", "iberia", "ryanair", "aeropuerto"]),
        (.ocio, ["cine", "teatro", "concierto", "entradas", "gimnasio", "gym", "museo"]),
        (.efectivo, ["cajero", "retirada", "atm", "reintegro"]),
        // Tiendas de todo tipo: la última lista, así «Bar La Moda» sigue siendo un bar.
        (.compras, ["bazar", "super bazar", "tienda china", "multiprecio", "multiprecios", "todo a 100",
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

/// Categoría por palabras enteras del nombre limpio del comercio ("Bar Manolo" -> comer fuera); nil si ninguna casa.
public func keywordCategory(for merchant: String) -> SpendingCategory? {
    let tokens = cleanMerchantName(merchant).split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return nil }
    return keywordRules.first { containsRun(tokens, $0.words) }?.category
}

/// Las categorías de CONCEPTOS y facturas: en un pago a una persona, su palabra manda («TRANSFERENCIA ALQUILER» es la
/// casa, «Transfer Aeropuerto» un viaje). Las demás (locales: comer fuera, supermercado, compras, ocio) no: «Bizum a
/// Juan Horno» es un amigo.
private let conceptCategories: Set<SpendingCategory> = [.casa, .viajes, .transporte, .salud, .efectivo]

/// Palabras de concepto que también son nombres de pila: en un pago a una persona no cuentan («Bizum a Mari Luz»).
private let conceptWordsThatAreNames: Set<String> = ["luz"]

/// La palabra clave de concepto o factura del comercio, para un pago a una persona; nil si no hay.
func conceptKeywordCategory(for merchant: String) -> SpendingCategory? {
    let tokens = foldedWords(merchant)
    guard !tokens.isEmpty else { return nil }
    return keywordRules.first { rule in
        conceptCategories.contains(rule.category)
            && !(rule.words.count == 1 && conceptWordsThatAreNames.contains(rule.words[0]))
            && containsRun(tokens, rule.words)
    }?.category
}

/// Categoría de un pago; nil para los ingresos. Orden: la del movimiento, la recordada del comercio, el MCC (ISO 18245),
/// el directorio (sobre el nombre limpio), las suscripciones y, después:
/// - en un pago a una persona (solo con prueba, ver `isPersonPayment`): la palabra de concepto o factura si la hay
///   («TRANSFERENCIA ALQUILER» -> casa) y si no, Personas. Las palabras de un local no cuentan: «Bizum a Juan Horno»
///   es un amigo, no una panadería;
/// - en cualquier otro pago: las palabras clave de siempre (sobre el nombre limpio), en su orden de siempre, y por último sin categoría.
/// Un comercio que no se conoce NO es una persona: el bar del barrio cuyo nombre en la tarjeta es el de su dueño va a
/// «Sin categoría» hasta que el dueño lo elija.
public func spendingCategory(of movement: Movement, overrides: [String: SpendingCategory],
                             subscriptionKeys: Set<String>) -> SpendingCategory? {
    guard movement.kind == .payment else { return nil }
    if let own = movement.category { return own }
    let merchant = movement.merchant ?? ""
    let key = normalizeMerchant(merchant)
    if !key.isEmpty, let remembered = overrides[key] { return remembered }
    if let fromMCC = mccCategory(movement.merchantCategoryCode) { return fromMCC }
    if !key.isEmpty {
        if let domain = merchantDomain(for: merchant, isShop: movement.isShop),
           let fromDirectory = directoryCategory(forDomain: domain) { return fromDirectory }
        if subscriptionKeys.contains(key) { return .suscripciones }
    }
    if isPersonPayment(movement) {
        if !key.isEmpty, let concept = conceptKeywordCategory(for: merchant) { return concept }
        return .personas
    }
    if !key.isEmpty, let byWord = keywordCategory(for: merchant) { return byWord }
    return .sinCategoria
}

/// Palabras de un pago A UNA PERSONA: Bizum, transferencia (y la abreviatura «transf» de los extractos), «enviado/a».
/// «envio» solo no (hay mensajerías «Envíos Express»): cuenta como «envío a …». «traspaso» tampoco: en los bancos
/// españoles casi siempre es entre tus cuentas (sigue siendo un concepto genérico). Es LA lista: la del aviso
/// (`notificationSendWords`) y los conceptos genéricos (`genericPayeeWords`) salen de ella.
let personPaymentWords: Set<String> = [
    "bizum", "bizums", "transferencia", "transferencias", "transfer", "transf",
    "enviado", "enviada",
]

/// Palabras de un concepto genérico (Bizum, transferencias, recibos…): el «comercio» no es un comercio, así que elegir una
/// categoría para un pago así no debería aplicarse por defecto a todo lo que lleva ese texto.
private let genericPayeeWords: Set<String> = personPaymentWords.union([
    "traspaso", "traspasos", "recibo", "domiciliacion", "adeudo", "cajero", "retirada", "ingreso", "pago", "pagos", "cargo",
    "devolucion", "comision",
])

/// Palabras de un envío A TI MISMO (bolsillos, huchas, cuentas de ahorro): no es una persona aunque diga «transferencia».
private let ownAccountWords: Set<String> = ["ahorro", "ahorros", "hucha", "huchas", "savings", "vault", "pocket", "bolsillo"]

/// Palabras enteras del texto, normalizadas como los comercios (`normalizeMerchant`: sin mayúsculas ni tildes). Es la
/// única normalización de las palabras clave, del pago a persona, de los conceptos genéricos y del aviso.
func foldedWords(_ text: String) -> [String] {
    normalizeMerchant(text).split(separator: " ").map(String.init)
}

/// true si el texto habla de una cuenta propia («Traspaso a hucha», «To EUR Savings»).
func mentionsOwnAccount(_ text: String?) -> Bool {
    guard let text else { return false }
    return foldedWords(text).contains { ownAccountWords.contains($0) }
}

/// true si el texto dice que es un pago a una persona («Bizum a Ana», «TRANSF A FAVOR DE…», «Envío a Lucía») y no a
/// una cuenta propia. Lo usan la categoría y el concepto de los registros del banco.
func saysPersonPayment(_ text: String?) -> Bool {
    guard let text else { return false }
    let words = foldedWords(text)
    guard !words.contains(where: { ownAccountWords.contains($0) }) else { return false }
    return words.contains { personPaymentWords.contains($0) } || containsRun(words, ["envio", "a"])
}

/// true si hay prueba de que el pago fue a una persona: no es una compra en tienda (`isShop`) y, o bien una fuente lo
/// marcó (`personPayment`: aviso de envío, código de transferencia del banco, «Transfer» de Revolut), o bien el texto
/// del aviso o del banco lo dice («Bizum a Ana», «Transferencia a Laura», «TRANSF A FAVOR DE…», «Enviado a Juan»,
/// «Envío a Lucía»). Se mira también el nombre que dio el banco al enlazar (`bankMerchant`). Un nombre a secas
/// («Manuel García») no prueba nada.
public func isPersonPayment(_ movement: Movement) -> Bool {
    guard movement.kind == .payment, !movement.isShop else { return false }
    // Un envío a tu hucha o cuenta de ahorro no es una persona, aunque una fuente lo marcara como envío.
    guard !mentionsOwnAccount(movement.merchant), !mentionsOwnAccount(movement.bankMerchant) else { return false }
    return movement.personPayment == true || saysPersonPayment(movement.merchant) || saysPersonPayment(movement.bankMerchant)
}

/// true si el texto del comercio es un concepto genérico («Bizum a Ana», «Transferencia enviada», «Recibo»): palabra
/// entera, sin mayúsculas ni tildes.
public func isGenericPayee(_ merchant: String?) -> Bool {
    guard let merchant else { return false }
    return foldedWords(merchant).contains { genericPayeeWords.contains($0) }
}
