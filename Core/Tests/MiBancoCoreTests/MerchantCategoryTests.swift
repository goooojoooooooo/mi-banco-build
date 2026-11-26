import Foundation
import Testing
@testable import MiBancoCore

// Comercios de barrio y pagos a personas: «Personas» solo con una prueba de que el pago fue a alguien (Bizum,
// transferencia, traspaso, envío); un comercio que no se conoce va a «Sin categoría», nunca a «Personas».

private let when = Date(timeIntervalSince1970: 1_795_000_000)

private func pay(_ merchant: String?, isShop: Bool = false, source: Movement.Source = .notification,
                 bankMerchant: String? = nil) -> Movement {
    Movement(bank: .ima, amountCents: -1_500, merchant: merchant, kind: .payment, source: source, date: when,
             isShop: isShop, bankMerchant: bankMerchant)
}

private func category(_ m: Movement, overrides: [String: SpendingCategory] = [:],
                      subscriptions: Set<String> = []) -> SpendingCategory? {
    spendingCategory(of: m, overrides: overrides, subscriptionKeys: subscriptions)
}

@Suite struct MerchantCategoryTests {
    // MARK: Comercios de barrio

    @Test func barConLaPalabraEnUnSitioRaro() {
        #expect(category(pay("EL RINCON DE PEPE BAR")) == .comerFuera)
        #expect(category(pay("Los Arcos, Cervecería-Bar")) == .comerFuera)
        #expect(category(pay("Casa Paco Taberna Andaluza")) == .comerFuera)
    }

    @Test func tabernasYMesones() {
        #expect(category(pay("Taberna La Concha")) == .comerFuera)
        #expect(category(pay("MESÓN EL CRUCE")) == .comerFuera)
        #expect(category(pay("Tasca El Puerto", source: .bank)) == .comerFuera)
        #expect(category(pay("Asador Casa Juan", source: .statement)) == .comerFuera)
    }

    @Test func bazares() {
        #expect(category(pay("BAZAR CHEN")) == .compras)
        #expect(category(pay("Multiprecio Hong", source: .bank)) == .compras)
        #expect(category(pay("Todo a 100 La Plaza")) == .compras)
    }

    @Test func tiendasDeAlimentacionPequenas() {
        #expect(category(pay("Ultramarinos Pili")) == .supermercado)
        #expect(category(pay("Colmado Ramírez", source: .bank)) == .supermercado)
        #expect(category(pay("ALIMENTACION HERMANOS LOPEZ")) == .supermercado)
        #expect(category(pay("Mini Market Sol")) == .supermercado)
    }

    // MARK: Personas solo con prueba

    @Test func compraConNombreDePersonaNoEsPersonas() {
        // Un comercio cuyo nombre en la tarjeta es el de su dueño: sin palabra de Bizum ni de transferencia.
        #expect(category(pay("Manuel García López", source: .bank)) == .sinCategoria)
        #expect(category(pay("Aitziber Zubizarreta")) == .sinCategoria)
        #expect(category(pay("Carlos")) == .sinCategoria)
        // Cartera (Apple Pay): siempre una compra en tienda.
        #expect(category(pay("Manuel García", isShop: true, source: .wallet)) == .sinCategoria)
    }

    @Test func bizumYTransferenciaSonPersonas() {
        #expect(category(pay("Bizum a Manuel García")) == .personas)
        #expect(category(pay("Transferencia a Laura Pérez", source: .bank)) == .personas)
        #expect(category(pay("TRANSF A FAVOR DE LAURA PEREZ", source: .statement)) == .personas)
        #expect(category(pay("Traspaso a ahorro")) == .personas)
        #expect(category(pay("Envío a Lucía")) == .personas)
        #expect(category(pay("Pago Bizum a Laura", source: .bank)) == .personas)
    }

    @Test func elMismoNombreComoBizumEsPersonas() {
        // El aviso dio solo el nombre; el banco, al enlazarlo, dijo que era un Bizum.
        #expect(category(pay("Manuel García López")) == .sinCategoria)
        #expect(category(pay("Manuel García López", bankMerchant: "Bizum a Manuel Garcia")) == .personas)
        #expect(category(pay("Manuel García López", bankMerchant: "TRANSFERENCIA A MANUEL GARCIA")) == .personas)
    }

    @Test func unaTiendaConPalabraDeEnvioNoEsPersonas() {
        // La señal de tienda (código de comercio, Cartera) manda sobre la palabra.
        #expect(category(pay("Bizum Pepe", isShop: true)) == .sinCategoria)
    }

    @Test func conceptosGenericosQueNoSonPersonas() {
        #expect(category(pay("Recibo")) == .sinCategoria)
        #expect(category(pay("Comisión de mantenimiento", source: .bank)) == .sinCategoria)
        #expect(category(pay("Adeudo SEPA 123456")) == .sinCategoria)
    }

    @Test func sinComercioEIngresos() {
        #expect(category(pay(nil)) == .sinCategoria)
        #expect(category(pay("")) == .sinCategoria)
        let income = Movement(bank: .ima, amountCents: 2_000, merchant: "Bizum de Laura", kind: .income,
                              source: .notification, date: when)
        #expect(category(income) == nil)
        let shopIncome = Movement(bank: .ima, amountCents: 2_000, merchant: "Bar Pepe", kind: .income,
                                  source: .bank, date: when)
        #expect(category(shopIncome) == nil)
    }

    // MARK: Orden de prioridad

    @Test func laCategoriaRecordadaSigueGanando() {
        #expect(category(pay("Bazar Chen"), overrides: ["bazar chen": .casa]) == .casa)
        #expect(category(pay("Manuel García López"), overrides: ["manuel garcia lopez": .comerFuera]) == .comerFuera)
        #expect(category(pay("Bizum a Ana"), overrides: ["bizum a ana": .ocio]) == .ocio)
        var own = pay("Taberna La Concha")
        own.category = .viajes
        #expect(category(own, overrides: ["taberna la concha": .casa]) == .viajes)
    }

    @Test func elDirectorioGanaALaPalabraClave() {
        // «Repsol» está en el directorio (transporte); «cafetería» diría comer fuera.
        #expect(category(pay("Repsol Cafetería", isShop: true)) == .transporte)
        #expect(category(pay("Mercadona Moda", isShop: true)) == .supermercado)
    }

    @Test func lasSuscripcionesGananALaPalabraClave() {
        #expect(category(pay("Pub Irlandés"), subscriptions: ["pub irlandes"]) == .suscripciones)
        #expect(category(pay("Pub Irlandés")) == .comerFuera)
    }

    @Test func variasPalabrasAntesQueUna() {
        // «comida rápida» (comer fuera) antes que «mercado» (supermercado).
        #expect(keywordCategory(for: "Comida Rápida El Mercado") == .comerFuera)
        // «super bazar» (compras) antes que «super» (supermercado).
        #expect(keywordCategory(for: "Super Bazar Chen") == .compras)
        // «tienda china» (compras): «china» sola no dice nada.
        #expect(keywordCategory(for: "Tienda China Hua") == .compras)
        #expect(keywordCategory(for: "Comida China Gran Muralla") == .comerFuera)
        // «taller mecánico» (transporte): «taller» solo no.
        #expect(keywordCategory(for: "Taller Mecánico Hermanos Gil") == .transporte)
    }

    @Test func tildesYMayusculas() {
        #expect(keywordCategory(for: "MARISQUERÍA O PORTO") == .comerFuera)
        #expect(keywordCategory(for: "pescaderia hermanos") == .supermercado)
        #expect(keywordCategory(for: "PELUQUERÍA") == nil)
        #expect(keywordCategory(for: "Zapatería Ñandú") == .compras)
        #expect(keywordCategory(for: "HELADERÍA LA JIJONENCA") == .comerFuera)
        #expect(keywordCategory(for: "Tintorería Express") == .casa)
    }

    // MARK: Casos negativos: las palabras nuevas no se comen lo que no son

    @Test func palabrasNuevasEnterasNoSubcadenas() {
        #expect(keywordCategory(for: "Pubilla Cases") == nil)
        #expect(keywordCategory(for: "Hornos Industriales") == nil)
        #expect(keywordCategory(for: "Tabacalera Holdings") == nil)
        #expect(keywordCategory(for: "Modesto Ruiz") == nil)
        #expect(keywordCategory(for: "Bodeguero Martínez") == nil)
        #expect(keywordCategory(for: "Juan Tascón") == nil)
        #expect(keywordCategory(for: "Wokingham Ltd") == nil)
    }

    @Test func chinaYChinoSolosNoSonCategoria() {
        #expect(keywordCategory(for: "China Mobile") == nil)
        #expect(keywordCategory(for: "Chino Pérez") == nil)
        #expect(category(pay("Bizum a Ana China")) == .personas)
    }

    @Test func tallerY24HorasSolosNoSonCategoria() {
        #expect(keywordCategory(for: "Taller de Cerámica") == nil)
        // «24 horas» no es una regla: no le quita la farmacia a la farmacia.
        #expect(keywordCategory(for: "Farmacia 24 Horas") == .salud)
        #expect(keywordCategory(for: "Parking 24 Horas") == .transporte)
    }

    @Test func envioSoloNoEsUnaPersona() {
        // Una mensajería («Envíos Express») no es un pago a una persona.
        #expect(keywordCategory(for: "Envíos Express") == nil)
        #expect(category(pay("Envíos Express")) == .sinCategoria)
    }

    @Test func peluqueriaYBarberiaNoSeFuerzan() {
        #expect(category(pay("Peluquería Marisa")) == .sinCategoria)
        #expect(category(pay("Barbería Kike")) == .sinCategoria)
    }

    @Test func conceptosGenericosAmpliados() {
        #expect(isGenericPayee("TRANSF A FAVOR DE LAURA"))
        #expect(isGenericPayee("Bizum enviado"))
        #expect(isGenericPayee("Traspasos"))
        #expect(!isGenericPayee("Envíos Express"))
        #expect(!isGenericPayee("Taberna La Concha"))
        #expect(!isGenericPayee("Manuel García López"))
    }

    // MARK: El léxico entero, fijado

    static let lexicon: [(String, SpendingCategory)] = [
        // Supermercado
        ("ultramarinos", .supermercado), ("verduleria", .supermercado), ("charcuteria", .supermercado),
        ("pescaderia", .supermercado), ("horno", .supermercado), ("colmado", .supermercado),
        ("tienda de barrio", .supermercado), ("minimarket", .supermercado), ("mini market", .supermercado),
        ("minimercado", .supermercado), ("hipermercado", .supermercado), ("polleria", .supermercado),
        ("pasteleria", .supermercado), ("confiteria", .supermercado), ("frutas", .supermercado),
        // Comer fuera
        ("tasca", .comerFuera), ("meson", .comerFuera), ("bodega", .comerFuera), ("bodegon", .comerFuera),
        ("asador", .comerFuera), ("marisqueria", .comerFuera), ("heladeria", .comerFuera), ("churreria", .comerFuera),
        ("chocolateria", .comerFuera), ("hamburgueseria", .comerFuera), ("wok", .comerFuera), ("sushi", .comerFuera),
        ("ramen", .comerFuera), ("tapas", .comerFuera), ("taperia", .comerFuera), ("bocateria", .comerFuera),
        ("sidreria", .comerFuera), ("vermuteria", .comerFuera), ("gastrobar", .comerFuera), ("restaurant", .comerFuera),
        ("trattoria", .comerFuera), ("pub", .comerFuera), ("cocteleria", .comerFuera), ("chiringuito", .comerFuera),
        ("cantina", .comerFuera), ("comidas", .comerFuera), ("comida rapida", .comerFuera), ("braseria", .comerFuera),
        ("creperia", .comerFuera), ("arroceria", .comerFuera), ("pulperia", .comerFuera), ("freiduria", .comerFuera),
        ("bistro", .comerFuera), ("restaurante chino", .comerFuera), ("comida china", .comerFuera),
        ("wok chino", .comerFuera),
        // Transporte
        ("autoescuela", .transporte), ("taller mecanico", .transporte), ("neumaticos", .transporte), ("itv", .transporte),
        // Casa y facturas
        ("lavanderia", .casa), ("tintoreria", .casa),
        // Salud
        ("herbolario", .salud), ("parafarmacia", .salud), ("ortopedia", .salud), ("veterinario", .salud),
        ("veterinaria", .salud),
        // Compras
        ("bazar", .compras), ("super bazar", .compras), ("bazar chino", .compras), ("tienda china", .compras),
        ("multiprecio", .compras), ("multiprecios", .compras), ("todo a 100", .compras), ("todo a cien", .compras),
        ("ferreteria", .compras), ("papeleria", .compras), ("libreria", .compras), ("estanco", .compras),
        ("tabacos", .compras), ("drogueria", .compras), ("perfumeria", .compras), ("zapateria", .compras),
        ("calzados", .compras), ("merceria", .compras), ("jugueteria", .compras), ("floristeria", .compras),
        ("electronica", .compras), ("moda", .compras), ("modas", .compras), ("boutique", .compras),
        ("joyeria", .compras), ("relojeria", .compras), ("regalos", .compras),
    ]

    @Test(arguments: MerchantCategoryTests.lexicon)
    func lexicoFijado(_ entry: (String, SpendingCategory)) {
        #expect(keywordCategory(for: entry.0) == entry.1, "«\(entry.0)»")
        // También dentro de un nombre real y en mayúsculas.
        #expect(keywordCategory(for: "LA " + entry.0.uppercased() + " DE PACO") == entry.1, "«\(entry.0)» en un nombre")
    }

    @Test func conTildesComoSeEscriben() {
        let written: [(String, SpendingCategory)] = [
            ("Verdulería", .supermercado), ("Charcutería", .supermercado), ("Pescadería", .supermercado),
            ("Pollería", .supermercado), ("Pastelería", .supermercado), ("Confitería", .supermercado),
            ("Mesón", .comerFuera), ("Bodegón", .comerFuera), ("Marisquería", .comerFuera), ("Heladería", .comerFuera),
            ("Churrería", .comerFuera), ("Chocolatería", .comerFuera), ("Hamburguesería", .comerFuera),
            ("Tapería", .comerFuera), ("Bocatería", .comerFuera), ("Sidrería", .comerFuera), ("Vermutería", .comerFuera),
            ("Coctelería", .comerFuera), ("Comida rápida", .comerFuera), ("Brasería", .comerFuera), ("Crepería", .comerFuera),
            ("Arrocería", .comerFuera), ("Pulpería", .comerFuera), ("Freiduría", .comerFuera), ("Bistró", .comerFuera),
            ("Taller mecánico", .transporte), ("Neumáticos", .transporte),
            ("Lavandería", .casa), ("Tintorería", .casa),
            ("Ferretería", .compras), ("Papelería", .compras), ("Librería", .compras), ("Droguería", .compras),
            ("Perfumería", .compras), ("Zapatería", .compras), ("Mercería", .compras), ("Juguetería", .compras),
            ("Floristería", .compras), ("Electrónica", .compras), ("Joyería", .compras), ("Relojería", .compras),
        ]
        for (text, expected) in written {
            #expect(keywordCategory(for: text) == expected, "«\(text)»")
        }
    }

    @Test func lasPalabrasDeAntesSiguenIgual() {
        let before: [(String, SpendingCategory)] = [
            ("super", .supermercado), ("supermercado", .supermercado), ("mercado", .supermercado),
            ("alimentacion", .supermercado), ("fruteria", .supermercado), ("carniceria", .supermercado),
            ("panaderia", .supermercado),
            ("bar", .comerFuera), ("restaurante", .comerFuera), ("cafe", .comerFuera), ("cafeteria", .comerFuera),
            ("pizzeria", .comerFuera), ("burger", .comerFuera), ("kebab", .comerFuera), ("taberna", .comerFuera),
            ("cerveceria", .comerFuera), ("just eat", .comerFuera), ("uber eats", .comerFuera), ("deliveroo", .comerFuera),
            ("gasolinera", .transporte), ("parking", .transporte), ("aparcamiento", .transporte), ("taxi", .transporte),
            ("metro", .transporte), ("emt", .transporte), ("bus", .transporte), ("peaje", .transporte),
            ("cabify", .transporte), ("uber", .transporte),
            ("luz", .casa), ("agua", .casa), ("iberdrola", .casa), ("endesa", .casa), ("naturgy", .casa),
            ("alquiler", .casa), ("comunidad", .casa), ("seguro", .casa), ("seguros", .casa), ("movistar", .casa),
            ("vodafone", .casa), ("fibra", .casa),
            ("farmacia", .salud), ("clinica", .salud), ("dentista", .salud), ("optica", .salud), ("hospital", .salud),
            ("fisio", .salud), ("fisioterapia", .salud),
            ("hotel", .viajes), ("hostal", .viajes), ("airbnb", .viajes), ("booking", .viajes), ("vueling", .viajes),
            ("iberia", .viajes), ("ryanair", .viajes), ("aeropuerto", .viajes),
            ("cine", .ocio), ("teatro", .ocio), ("concierto", .ocio), ("entradas", .ocio), ("gimnasio", .ocio),
            ("gym", .ocio), ("museo", .ocio),
            ("cajero", .efectivo), ("retirada", .efectivo), ("atm", .efectivo), ("reintegro", .efectivo),
        ]
        for (text, expected) in before {
            #expect(keywordCategory(for: text) == expected, "«\(text)»")
        }
    }
}
