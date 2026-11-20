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
private let keywordRules: [KeywordRule] = {
    let lists: [(SpendingCategory, [String])] = [
        (.supermercado, ["super", "supermercado", "mercado", "alimentacion", "fruteria", "carniceria", "panaderia"]),
        (.comerFuera, ["bar", "restaurante", "cafe", "cafeteria", "pizzeria", "burger", "kebab", "taberna", "cerveceria",
                       "just eat", "uber eats", "deliveroo"]),
        (.transporte, ["gasolinera", "parking", "aparcamiento", "taxi", "metro", "emt", "bus", "peaje", "cabify", "uber"]),
        (.casa, ["luz", "agua", "iberdrola", "endesa", "naturgy", "alquiler", "comunidad", "seguro", "seguros",
                 "movistar", "vodafone", "fibra"]),
        (.salud, ["farmacia", "clinica", "dentista", "optica", "hospital", "fisio", "fisioterapia"]),
        (.viajes, ["hotel", "hostal", "airbnb", "booking", "vueling", "iberia", "ryanair", "aeropuerto"]),
        (.ocio, ["cine", "teatro", "concierto", "entradas", "gimnasio", "gym", "museo"]),
        (.efectivo, ["cajero", "retirada", "atm", "reintegro"]),
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
/// las suscripciones, las palabras clave, una persona (no tienda) y por último sin categoría.
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
        if !movement.isShop { return .personas }
    }
    return .sinCategoria
}
