import Foundation

/// Normaliza un código MCC (ISO 18245): recorta espacios y exige exactamente 4 dígitos ASCII distintos de «0000».
public func cleanMCC(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 4, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }), trimmed != "0000" else { return nil }
    return trimmed
}

/// Categoría de gasto a partir del código de tipo de comercio (MCC, ISO 18245 / Visa / Mastercard).
///
/// Devuelve `nil` cuando:
/// - el código falta o no es un MCC de 4 dígitos;
/// - es un código de transferencia o envío de dinero (`4829`, `6540`), que sigue siendo señal de pago a persona;
/// - es financiero no comercial (`6012`, `6051`) o genérico/ambiguo (`5311`, `5399`, `5999`, `7299`, `7399`, `8999`),
///   o bienes digitales (`5815`–`5818`), para que decidan el directorio, las suscripciones o las palabras clave.
public func mccCategory(_ raw: String?) -> SpendingCategory? {
    guard let cleaned = cleanMCC(raw), let code = Int(cleaned) else { return nil }
    switch code {
    // Comer fuera: catering, restaurantes, bares/tabernas, comida rápida.
    case 5811, 5812, 5813, 5814:
        return .comerFuera

    // Supermercado y alimentación: supermercados, carnicerías/pescaderías, confiterías, lácteos, panaderías, alimentación variada.
    case 5411, 5422, 5441, 5451, 5462, 5499:
        return .supermercado

    // Transporte: transporte local, trenes de pasajeros (coherente con Renfe en el directorio), taxis/VTC, autobuses,
    // peajes, gasolineras, aparcamientos y mantenimiento del coche.
    case 4111, 4112, 4121, 4131, 4784, 4789,
         5532, 5533, 5541, 5542,
         7523, 7531, 7534, 7535, 7538, 7542:
        return .transporte

    // Viajes: aerolíneas nominales (3000–3299) y genérica (4511), alquiler de coches nominal (3351–3500) y genérico (7512),
    // hoteles nominales (3501–3999) y genéricos (7011–7033), cruceros (4411), aeropuertos (4582) y agencias de viaje (4722–4723).
    case 3000...3299, 3351...3500, 3501...3999,
         4411, 4511, 4582, 4722, 4723,
         7011, 7012, 7032, 7033, 7512:
        return .viajes

    // Salud: veterinaria (0742), farmacias (5912), audífonos/ortopedia (5975, 5976) y médicos/dentistas/ópticas/clínicas/hospitales (8011–8099).
    case 742, 5912, 5975, 5976, 8011...8099:
        return .salud

    // Ocio: cines, teatros/entradas, espectáculos, billares/boleras, deportes, atracciones/museos, parques, gimnasios/clubes y recreación.
    // (Se deja fuera 7995 —juego/apuestas— a propósito.)
    case 7832, 7911, 7922, 7929, 7932, 7933, 7941,
         7991, 7992, 7993, 7994, 7996, 7997, 7998, 7999:
        return .ocio

    // Compras: hogar/bricolaje/ferretería/muebles/electrodomésticos, ropa/calzado (5611–5699), electrónica/informática/software/música,
    // deporte, librerías/papelerías, joyerías, videojuegos/juguetes (5945), regalos, marroquinería, cosmética/perfumería, floristería, estancos y mascotas.
    case 5045, 5200, 5211, 5231, 5251, 5261,
         5611...5699,
         5712, 5713, 5714, 5718, 5719, 5722,
         5732, 5733, 5734, 5735,
         5931, 5941, 5942, 5943, 5944, 5945, 5946, 5947, 5948, 5949,
         5970, 5977, 5992, 5993, 5994, 5995:
        return .compras

    // Casa y facturas: telefonía/telecom, cable/streaming/telecom (4899), luz/agua/gas (4900), seguros (6300), alquiler/inmobiliaria (6513) y lavandería/tintorería.
    case 4812, 4814, 4816, 4899, 4900, 6300, 6513, 7210, 7211, 7216:
        return .casa

    // Efectivo: retirada en ventanilla y cajeros automáticos.
    case 6010, 6011:
        return .efectivo

    default:
        return nil
    }
}
