import Foundation
import Testing
@testable import MiBancoCore

// Pruebas de comercios exactos: tabla MCC (ISO 18245), limpieza de nombres de extracto/aviso,
// directorio ampliado de cadenas españolas, casos negativos y compatibilidad con datos guardados.

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func pay(
    _ merchant: String?,
    isShop: Bool = true,
    mcc: String? = nil,
    personPayment: Bool? = nil,
    category: SpendingCategory? = nil,
    source: Movement.Source = .bank
) -> Movement {
    Movement(
        bank: .ima,
        amountCents: -1_990,
        merchant: merchant,
        kind: .payment,
        source: source,
        date: at(11, 18),
        isShop: isShop,
        category: category,
        personPayment: personPayment,
        merchantCategoryCode: mcc
    )
}

private func classify(
    _ movement: Movement,
    overrides: [String: SpendingCategory] = [:],
    subscriptions: Set<String> = []
) -> SpendingCategory? {
    spendingCategory(of: movement, overrides: overrides, subscriptionKeys: subscriptions)
}

private func ebDebit(
    _ amount: String,
    creditor: String? = nil,
    mcc: String? = nil,
    remittance: [String]? = nil,
    status: EBTransactionStatus = .book,
    entry: String
) -> EBTransaction {
    EBTransaction(
        transactionAmount: EBAmount(currency: "EUR", amount: amount),
        creditDebitIndicator: "DBIT",
        status: status,
        entryReference: entry,
        transactionDate: "2026-11-18",
        remittanceInformation: remittance,
        creditor: creditor.map { EBParty(name: $0) },
        merchantCategoryCode: mcc
    )
}

private let trHeaders = [
    "datetime", "date", "account_type", "category", "type", "asset_class", "name", "symbol", "shares", "price",
    "amount", "fee", "tax", "currency", "original_amount", "original_currency", "fx_rate", "description",
    "transaction_id", "counterparty_name", "counterparty_iban", "payment_reference", "mcc_code",
]

private func trCSV(_ rows: [[String: String]]) -> String {
    let lines = rows.map { values in
        trHeaders.map { values[$0] ?? "" }.joined(separator: ",")
    }
    return ([trHeaders.joined(separator: ",")] + lines).joined(separator: "\n") + "\n"
}

@Suite struct MerchantClassificationTests {
    // MARK: 1. Tabla MCC (ISO 18245)

    @Test(arguments: [
        // Comer fuera
        ("5811", SpendingCategory.comerFuera),
        ("5812", .comerFuera),
        ("5813", .comerFuera),
        ("5814", .comerFuera),
        // Supermercado
        ("5411", .supermercado),
        ("5422", .supermercado),
        ("5441", .supermercado),
        ("5451", .supermercado),
        ("5462", .supermercado),
        ("5499", .supermercado),
        // Transporte
        ("4111", .transporte),
        ("4112", .transporte),
        ("4121", .transporte),
        ("4131", .transporte),
        ("4784", .transporte),
        ("5541", .transporte),
        ("5542", .transporte),
        ("7523", .transporte),
        // Viajes
        ("3000", .viajes),
        ("3022", .viajes),
        ("3299", .viajes),
        ("3351", .viajes),
        ("3500", .viajes),
        ("3501", .viajes),
        ("3751", .viajes),
        ("3999", .viajes),
        ("4411", .viajes),
        ("4511", .viajes),
        ("4722", .viajes),
        ("7011", .viajes),
        ("7512", .viajes),
        // Salud
        ("5912", .salud),
        ("5975", .salud),
        ("5976", .salud),
        ("8011", .salud),
        ("8021", .salud),
        ("8043", .salud),
        ("8062", .salud),
        ("8099", .salud),
        // Ocio
        ("7832", .ocio),
        ("7922", .ocio),
        ("7932", .ocio),
        ("7933", .ocio),
        ("7991", .ocio),
        ("7996", .ocio),
        ("7997", .ocio),
        ("7998", .ocio),
        ("7999", .ocio),
        // Compras
        ("5200", .compras),
        ("5211", .compras),
        ("5251", .compras),
        ("5611", .compras),
        ("5651", .compras),
        ("5661", .compras),
        ("5699", .compras),
        ("5712", .compras),
        ("5722", .compras),
        ("5732", .compras),
        ("5734", .compras),
        ("5735", .compras),
        ("5941", .compras),
        ("5942", .compras),
        ("5944", .compras),
        ("5945", .compras),
        ("5948", .compras),
        ("5977", .compras),
        // Casa y facturas
        ("4812", .casa),
        ("4814", .casa),
        ("4899", .casa),
        ("4900", .casa),
        ("6300", .casa),
        ("6513", .casa),
        // Efectivo
        ("6010", .efectivo),
        ("6011", .efectivo),
    ] as [(String, SpendingCategory)])
    func tablaMCC(_ code: String, _ expected: SpendingCategory) {
        #expect(mccCategory(code) == expected, "MCC \(code)")
        #expect(mccCategory(" \(code) ") == expected, "MCC con espacios \(code)")
    }

    @Test(arguments: [
        // Transferencias / envíos: siguen siendo señal de persona, nunca categoría fija
        "4829", "6540",
        // Ambiguos / genéricos: pasan al siguiente paso (directorio / palabras clave)
        "5311", "5399", "5999", "7299", "7399", "8999",
        // Financieros no comerciales
        "6012", "6051",
        // Inválidos o vacíos
        "", "   ", "0000", "581", "58120", "ABCD",
    ])
    func mccNoDecideCuandoEsTransferenciaAmbiguoOInvalido(_ code: String) {
        #expect(mccCategory(code) == nil, "MCC \(code) no debería decidir")
    }

    @Test func mccNilDevuelveNil() {
        #expect(mccCategory(nil) == nil)
    }

    @Test func ordenDePrioridadConMCC() {
        // Un comercio con nombre opaco («Inversiones del Norte») se clasifica por su MCC 5812 (restaurante).
        let byMCC = pay("Inversiones del Norte", isShop: true, mcc: "5812")
        #expect(classify(byMCC) == .comerFuera)

        // El MCC (paso 4) gana sobre el directorio (paso 5).
        let mccOverDir = pay("El Corte Inglés", isShop: true, mcc: "5411")
        #expect(classify(mccOverDir) == .supermercado)
        // Una suscripción reconocida (paso 3) gana al MCC (paso 4), ver `suscripcionReconocidaGanaAlMCC`.
        let subOverMCC = pay("Tienda Misteriosa", isShop: true, mcc: "5945")
        #expect(classify(subOverMCC, subscriptions: ["tienda misteriosa"]) == .suscripciones)

        // La categoría recordada para el comercio (paso 2) gana sobre el MCC (paso 3).
        #expect(classify(byMCC, overrides: ["inversiones del norte": .ocio]) == .ocio)

        // La categoría elegida por el dueño en el movimiento (paso 1) gana sobre recordada y MCC.
        var own = byMCC
        own.category = .viajes
        #expect(classify(own, overrides: ["inversiones del norte": .ocio]) == .viajes)

        // Un MCC ambiguo (5999, 7399) NO decide y pasa al directorio o palabras clave.
        #expect(classify(pay("GAME STORES IBERIA SL MADRID", isShop: true, mcc: "5999")) == .compras)
        #expect(classify(pay("SUMUP *BAR PEPE", isShop: true, mcc: "7399")) == .comerFuera)
        #expect(classify(pay("Comercio Desconocido", isShop: true, mcc: "5999")) == .sinCategoria)

        // Los MCC de transferencia (4829, 6540) siguen siendo señal de persona, no categoría fija.
        let transfer4829 = pay("Ana López", isShop: false, mcc: "4829", personPayment: true)
        #expect(classify(transfer4829) == .personas)
        let transfer6540 = pay("Pepe Sánchez", isShop: false, mcc: "6540", personPayment: true)
        #expect(classify(transfer6540) == .personas)
    }

    @Test func suscripcionReconocidaGanaAlMCC() {
        // Plataformas de vídeo con MCC 4899 (que por sí solo es «Casa») siguen en Suscripciones.
        for name in ["NETFLIX.COM", "HBO MAX", "DAZN", "Disney+"] {
            #expect(classify(pay(name, isShop: true, mcc: "4899")) == .suscripciones, "\(name)")
        }
        // Software con MCC 5734/5735 (que por sí solo es «Compras»), reconocido como suscripción por el directorio.
        #expect(classify(pay("MICROSOFT*365", isShop: true, mcc: "5734")) == .suscripciones)
        #expect(classify(pay("ADOBE SYSTEMS", isShop: true, mcc: "5735")) == .suscripciones)
        // Una suscripción detectada como cobro recurrente también gana al MCC.
        #expect(classify(pay("Plataforma Rara", isShop: true, mcc: "4899"), subscriptions: ["plataforma rara"]) == .suscripciones)
        // Un comercio desconocido con 4899 y sin señal de suscripción sigue la categoría del MCC.
        #expect(classify(pay("Operador Desconocido", isShop: true, mcc: "4899")) == .casa)
        // La categoría del dueño y la recordada siguen ganando a una suscripción.
        #expect(classify(pay("NETFLIX.COM", isShop: true, mcc: "4899", category: .ocio)) == .ocio)
        #expect(classify(pay("NETFLIX.COM", isShop: true, mcc: "4899"), overrides: [normalizeMerchant("NETFLIX.COM"): .ocio]) == .ocio)
        #expect(classify(pay("Plataforma Rara", isShop: true, mcc: "4899", category: .ocio), subscriptions: ["plataforma rara"]) == .ocio)
    }

    @Test func mccDeBazaresYTiendasDeTodoANivelCompras() {
        for code in ["5300", "5310", "5331"] {
            #expect(mccCategory(code) == .compras, "\(code)")
        }
        // Bazar con el nombre del titular en la tarjeta: tienda por MCC, no Personas ni sin categoría.
        #expect(classify(pay("CHEN LI SL", isShop: true, mcc: "5331")) == .compras)
        // Sin MCC y sin señal de persona no es Personas.
        #expect(classify(pay("CHEN LI SL", isShop: true)) != .personas)
    }

    @Test func mccSePropagaDesdeEnableBankingYTradeRepublicYSeConservaAlReconciliar() throws {
        // Enable Banking -> BankRecord -> Movement (paso 4 de reconcile)
        let ebRecords = bankRecords(from: [
            ebDebit("59.99", creditor: "HOLDING GAMER SL", mcc: "5945", entry: "eb-game"),
            ebDebit("24.00", creditor: "MANUEL GARCIA", mcc: "5812", entry: "eb-rest"),
            ebDebit("15.00", creditor: "ANA LOPEZ", mcc: "4829", entry: "eb-p2p"),
        ], bank: .ima, calendar: madrid)
        #expect(ebRecords.map(\.merchantCategoryCode) == ["5945", "5812", "4829"])

        var l = Ledger()
        _ = l.reconcile(ebRecords, bank: .ima, channel: .bank, coverage: nil, now: at(11, 20), calendar: madrid)
        let byRef = Dictionary(uniqueKeysWithValues: l.state.movements.map { ($0.bankRef ?? "", $0) })
        #expect(byRef["eb-game"]?.merchantCategoryCode == "5945")
        #expect(byRef["eb-game"].flatMap { classify($0) } == .compras)
        #expect(byRef["eb-rest"]?.merchantCategoryCode == "5812")
        #expect(byRef["eb-rest"].flatMap { classify($0) } == .comerFuera)
        #expect(byRef["eb-p2p"]?.merchantCategoryCode == "4829")
        #expect(byRef["eb-p2p"].flatMap { classify($0) } == .personas)

        // Aviso capturado sin MCC enlazado con registro del banco con MCC (paso 3) y re-descarga sin MCC (paso 1).
        var linkLedger = Ledger()
        let noticeOutcome = linkLedger.ingest(
            .notification(bank: .ima, title: nil, subtitle: nil, body: "Has pagado 24,00 € en Manuel García"),
            now: at(11, 18, 14)
        )
        guard case .stored(let captured) = noticeOutcome else {
            Issue.record("esperaba .stored")
            return
        }
        #expect(captured.merchantCategoryCode == nil)
        _ = linkLedger.reconcile([ebRecords[1]], bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 18), calendar: madrid)
        #expect(linkLedger.state.movements.first?.merchantCategoryCode == "5812")
        #expect(linkLedger.state.movements.first.flatMap { classify($0) } == .comerFuera)
        // Re-descarga de la misma clave sin MCC: NO borra el MCC guardado.
        let withoutMCC = bankRecords(from: [ebDebit("24.00", creditor: "MANUEL GARCIA", entry: "eb-rest")], bank: .ima, calendar: madrid)
        _ = linkLedger.reconcile(withoutMCC, bank: .ima, channel: .bank, coverage: nil, now: at(11, 19), calendar: madrid)
        #expect(linkLedger.state.movements.first?.merchantCategoryCode == "5812")

        // Paso 2 (pendiente -> apuntado con otra clave) conserva/añade MCC.
        var step2Ledger = Ledger()
        let pending = bankRecords(from: [ebDebit("32.00", creditor: "LOCAL X", status: .pdng, entry: "p-1")], bank: .ima, calendar: madrid)
        _ = step2Ledger.reconcile(pending, bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 15), calendar: madrid)
        let booked = bankRecords(from: [ebDebit("32.00", creditor: "LOCAL X", mcc: "5812", status: .book, entry: "b-1")], bank: .ima, calendar: madrid)
        _ = step2Ledger.reconcile(booked, bank: .ima, channel: .bank, coverage: nil, now: at(11, 19), calendar: madrid)
        #expect(step2Ledger.state.movements.first?.merchantCategoryCode == "5812")

        // Fusión de pendiente desaparecido (foldCandidate) conserva MCC.
        let capture = Movement(
            bank: .ima, amountCents: -1_800, merchant: "Local Y", kind: .payment, source: .notification,
            date: at(11, 18, 10), fingerprint: "fp-fold-mcc"
        )
        var foldLedger = Ledger(state: LedgerState(movements: [capture]))
        let cov = DateInterval(start: at(11, 10, 0), end: at(11, 20, 0))
        let pRow = BankRecord(ref: "fp-p1", bank: .ima, amountCents: -1_800, timing: .transactionDay(at(11, 18)), status: .pending)
        let bRow = BankRecord(
            ref: "fp-b1", bank: .ima, amountCents: -1_800, timing: .transactionDay(at(11, 18)),
            status: .booked, merchant: "Local Y", isShop: true, merchantCategoryCode: "5912"
        )
        _ = foldLedger.reconcile([pRow, bRow], bank: .ima, channel: .bank, coverage: cov, now: at(11, 19), calendar: madrid)
        _ = foldLedger.reconcile([bRow], bank: .ima, channel: .bank, coverage: cov, now: at(11, 20), calendar: madrid)
        #expect(foldLedger.state.movements.count == 1)
        #expect(foldLedger.state.movements.first?.merchantCategoryCode == "5912")
        #expect(foldLedger.state.movements.first.flatMap { classify($0) } == .salud)

        // Extracto de Trade Republic -> BankRecord -> Movement con MCC.
        let csv = trCSV([
            [
                "datetime": "2026-11-18T11:00:00Z", "date": "2026-11-18", "account_type": "DEFAULT",
                "category": "CASH", "type": "CARD_TRANSACTION", "name": "Comercio Opaco",
                "amount": "-49.99", "currency": "EUR", "transaction_id": "tr-mcc-1",
                "counterparty_name": "Comercio Opaco", "mcc_code": "5945",
            ],
        ])
        let parsed = try parseStatement(Data(csv.utf8), expected: .tr, now: at(11, 20), calendar: madrid)
        #expect(parsed.records.first?.merchantCategoryCode == "5945")
        var trLedger = Ledger()
        _ = trLedger.importStatement(parsed, now: at(11, 20), calendar: madrid)
        let trMovement = try #require(trLedger.state.movements.first)
        #expect(trMovement.merchantCategoryCode == "5945")
        #expect(classify(trMovement) == .compras)

        // Aviso tardío que completa un movimiento del banco conserva su MCC.
        var mergeLedger = Ledger()
        _ = mergeLedger.reconcile([ebRecords[0]], bank: .ima, channel: .bank, coverage: nil, now: at(11, 18, 9), calendar: madrid)
        let mergedOutcome = mergeLedger.ingest(
            .notification(bank: .ima, title: nil, subtitle: nil, body: "Has pagado 59,99 € en Tienda Centro"),
            now: at(11, 18, 12)
        )
        guard case .merged(let merged) = mergedOutcome else {
            Issue.record("esperaba .merged")
            return
        }
        #expect(merged.merchantCategoryCode == "5945")
        #expect(classify(merged) == .compras)
    }

    // MARK: 2. Limpieza de nombres de comercio

    @Test(arguments: [
        // Ejemplos pedidos explícitamente
        ("GAME STORES IBERIA SL MADRID", "game stores iberia"),
        ("SUMUP *BAR PEPE", "bar pepe"),
        ("MERCADONA 1234 VALENCIA", "mercadona"),
        ("ZTL*CAFETERIA SOL", "cafeteria sol"),
        ("PAYPAL *FNAC ESPANA SA", "fnac espana"),
        ("100 MONTADITOS SEVILLA", "100 montaditos"),
        // Pasarelas de pago
        ("SUMUP*PANADERIA SAN JOSE", "panaderia san jose"),
        ("ZTL *MESON EL CRUCE", "meson el cruce"),
        ("ZETTLE_*HELADERIA SOL", "heladeria sol"),
        ("ZETTLE *BAR MANOLO", "bar manolo"),
        ("PAYPAL*SPOTIFY", "spotify"),
        ("SQ *CAFE CENTRAL BARCELONA", "cafe central"),
        ("SQ*TAQUERIA NORTE", "taqueria norte"),
        ("STRIPE*OPENAI", "openai"),
        ("IZ *KIOSCO LA PLAZA", "kiosco la plaza"),
        ("CRV*MERCADONA 0452 MADRID ES", "mercadona"),
        ("GOOGLE *YOUTUBE PREMIUM", "youtube premium"),
        ("APPLE.COM/BILL", "apple"),
        // No romper Apple, Google ni PayPal si van solos
        ("Apple", "apple"),
        ("Google", "google"),
        ("PayPal", "paypal"),
        // Formas jurídicas (con y sin puntos, al final y antes de ciudad)
        ("LEROY MERLIN ESPANA S.L.U. ALCORCON", "leroy merlin espana"),
        ("EL CORTE INGLES S.A. MADRID", "el corte ingles"),
        ("MEDIA MARKT SATURN S.A.U. VALENCIA", "media markt saturn"),
        ("DECATHLON ESPANA S.A. ZARAGOZA", "decathlon espana"),
        ("ACME RETAIL LTD", "acme retail"),
        ("TECH SHOP LIMITED", "tech shop"),
        ("TIENDA NORDICA GMBH", "tienda nordica"),
        ("VIAJES EUROPA B.V.", "viajes europa"),
        ("MODA PARIS S.A.S.", "moda paris"),
        ("SOFTWARE CORP INC", "software"),
        ("SERVICIOS GLOBALES LLC", "servicios globales"),
        ("COMERCIO LOCAL S.R.L. BILBAO", "comercio local"),
        ("TALLER SUR SLL SEVILLA", "taller sur"),
        ("REFORMAS NORTE SLNE OVIEDO", "reformas norte"),
        // Números de tienda, sucursal y códigos de referencia sin romper 100 Montaditos ni O2
        ("LIDL TIENDA 12 MALAGA", "lidl"),
        ("CARREFOUR SUC 05 ALICANTE", "carrefour"),
        ("ZARA #42 SAN SEBASTIAN", "zara"),
        ("SPOTIFY P1A2B3C4", "spotify"),
        ("O2 MADRID", "o2"),
        ("O2", "o2"),
        ("Todo a 100 La Plaza", "todo a 100 la plaza"),
        // Ciudades/provincias españolas y código país al final
        ("ALCAMPO A CORUNA ES", "alcampo"),
        ("PRIMARK LAS PALMAS ESP", "primark"),
        ("IKEA PALMA DE MALLORCA", "ikea"),
        ("FNAC DONOSTIA", "fnac"),
        ("VIPS SANTA CRUZ DE TENERIFE", "vips"),
    ] as [(String, String)])
    func limpiezaDeNombresReales(_ raw: String, _ expected: String) {
        #expect(cleanMerchantName(raw) == expected, "«\(raw)»")
    }

    // MARK: 3. Tabla de >= 40 textos reales de extracto o aviso

    static let realWorldCases: [(text: String, isShop: Bool, mcc: String?, expected: SpendingCategory)] = [
        // Tecnología y videojuegos (.compras)
        ("GAME STORES IBERIA SL MADRID", true, nil, .compras),
        ("GAME 0452 VALENCIA", true, nil, .compras),
        ("MEDIAMARKT SATURN S.A.U. BARCELONA", true, nil, .compras),
        ("PAYPAL *FNAC ESPANA SA", true, nil, .compras),
        ("EL CORTE INGLES S.A. CASTELLANA MADRID", true, nil, .compras),
        ("PCCOMPONENTES Y MULTIMEDIA SL MURCIA", true, nil, .compras),
        ("CEX WEBUY MADRID", true, nil, .compras),
        // Ropa y deporte (.compras)
        ("PRIMARK TIENDAS SLU GRAN VIA MADRID", true, nil, .compras),
        ("ZARA ES 1234 SEVILLA", true, nil, .compras),
        ("DECATHLON TIENDA 18 ZARAGOZA", true, nil, .compras),
        ("BERSHKA BSK ESPANA SA VALENCIA", true, nil, .compras),
        ("PULL&BEAR 0345 BILBAO", true, nil, .compras),
        ("STRADIVARIUS ESPANA SA MALAGA", true, nil, .compras),
        ("OYSHO ESPANA SA BARCELONA", true, nil, .compras),
        ("LEFTIES 0120 ALICANTE", true, nil, .compras),
        ("UNIQLO EUROPE LTD MADRID", true, nil, .compras),
        ("SPRINTER MEGACENTROS DEL DEPORTE SL", true, nil, .compras),
        ("JD SPORTS FASHION SPAIN SL", true, nil, .compras),
        ("KIABI ESPANA KSCE SA", true, nil, .compras),
        ("SPRINGFIELD MADRID", true, nil, .compras),
        ("CORTEFIEL VALENCIA", true, nil, .compras),
        ("WOMEN'SECRET SEVILLA", true, nil, .compras),
        // Hogar y bricolaje (.compras)
        ("LEROY MERLIN ESPANA SLU ALCORCON", true, nil, .compras),
        ("IKEA IBERICA SA SAN SEBASTIAN DE LOS REYES", true, nil, .compras),
        ("BAUHAUS ZARAGOZA", true, nil, .compras),
        ("OBRAMAT ALCALA DE HENARES", true, nil, .compras),
        ("BRICODEPOT GRANADA", true, nil, .compras),
        ("CONFORAMA ESPANA SA", true, nil, .compras),
        ("JYSK DBL IBERIA SLU VALENCIA", true, nil, .compras),
        ("MAISONS DU MONDE BARCELONA", true, nil, .compras),
        ("FLYING TIGER COPENHAGEN MADRID", true, nil, .compras),
        ("ALE-HOP 087 ALICANTE", true, nil, .compras),
        // Comida y restaurantes (.comerFuera)
        ("TELEPIZZA 0231 MADRID", true, nil, .comerFuera),
        ("DOMINO'S PIZZA VALENCIA", true, nil, .comerFuera),
        ("BURGER KING ESPANA SL SEVILLA", true, nil, .comerFuera),
        ("MCDONALD'S GRAN VIA MADRID", true, nil, .comerFuera),
        ("KFC 0114 BARCELONA", true, nil, .comerFuera),
        ("VIPS SMART MADRID", true, nil, .comerFuera),
        ("100 MONTADITOS SEVILLA", true, nil, .comerFuera),
        ("TGB THE GOOD BURGER VALENCIA", true, nil, .comerFuera),
        ("RODILLA MADRID", true, nil, .comerFuera),
        ("GOIKO GRILL BILBAO", true, nil, .comerFuera),
        ("FOSTER'S HOLLYWOOD ZARAGOZA", true, nil, .comerFuera),
        ("GINOS RISTORANTE MADRID", true, nil, .comerFuera),
        ("LA TAGLIATELLA SALAMANCA", true, nil, .comerFuera),
        ("POPEYES LOUISIANA KITCHEN MADRID", true, nil, .comerFuera),
        ("DUNKIN' COFFEE GRAN VIA MADRID", true, nil, .comerFuera),
        ("PANS & COMPANY BARCELONA", true, nil, .comerFuera),
        ("LIZARRAN TABERNA BILBAO", true, nil, .comerFuera),
        ("GRUPO LATERAL MADRID", true, nil, .comerFuera),
        ("HONEST GREENS BARCELONA", true, nil, .comerFuera),
        ("PAPA JOHN'S VALENCIA", true, nil, .comerFuera),
        ("SUMUP *BAR PEPE", true, nil, .comerFuera),
        ("ZTL*CAFETERIA SOL", true, nil, .comerFuera),
        // Supermercados (.supermercado)
        ("MERCADONA 1234 VALENCIA", true, nil, .supermercado),
        ("CARREFOUR EXPRESS 0123 MADRID", true, nil, .supermercado),
        ("LIDL SUPERMERCADOS SAU BARCELONA", true, nil, .supermercado),
        ("ALDI SUPERMERCADOS SL SEVILLA", true, nil, .supermercado),
        ("DIA % 0452 MADRID", true, nil, .supermercado),
        ("EROSKI CENTER BILBAO", true, nil, .supermercado),
        ("ALCAMPO 042 VIGO", true, nil, .supermercado),
        ("CONSUM S COOP VALENCIA", true, nil, .supermercado),
        ("HIPERCOR POZUELO", true, nil, .supermercado),
        ("SUPERCOR EXPRES MADRID", true, nil, .supermercado),
        ("AHORRAMAS 0198 MADRID", true, nil, .supermercado),
        ("BONPREU ESCLAT GIRONA", true, nil, .supermercado),
        ("CAPRABO BARCELONA", true, nil, .supermercado),
        ("GADIS A CORUNA", true, nil, .supermercado),
        ("FROIZ PONTEVEDRA", true, nil, .supermercado),
        ("COVIRAN GRANADA", true, nil, .supermercado),
        ("BM SUPERMERCADOS DONOSTIA", true, nil, .supermercado),
        ("SPAR 0234 LAS PALMAS", true, nil, .supermercado),
        ("CONDIS LIFE BARCELONA", true, nil, .supermercado),
        ("LUPA SUPERMERCADOS SANTANDER", true, nil, .supermercado),
        ("VERITAS SUPERMERCADOS BARCELONA", true, nil, .supermercado),
        // Gasolineras (.transporte — incluidas Carrefour/Alcampo Gasolinera frente a supermercado)
        ("REPSOL E.S. 1234 MADRID", true, nil, .transporte),
        ("CEPSA ESTACION VALENCIA", true, nil, .transporte),
        ("MOEVE 0812 SEVILLA", true, nil, .transporte),
        ("BP 0421 MALAGA", true, nil, .transporte),
        ("GALP ENERGIA ESPANA SAU", true, nil, .transporte),
        ("PLENOIL ALCORCON", true, nil, .transporte),
        ("BALLENOIL GETAFE", true, nil, .transporte),
        ("PETROPRIX CORDOBA", true, nil, .transporte),
        ("CARREFOUR GASOLINERA MADRID", true, nil, .transporte),
        ("ALCAMPO GASOLINERA VALENCIA", true, nil, .transporte),
        // Farmacias (.salud)
        ("FARMACIA LDA. GARCIA MADRID", true, nil, .salud),
        ("PARAFARMACIA CENTRAL SL SEVILLA", true, nil, .salud),
        ("SUMUP *FARMACIA DEL PARQUE", true, nil, .salud),
        // Transporte y viajes (.transporte / .viajes)
        ("RENFE VIAJEROS S.A. MADRID", true, nil, .transporte),
        ("OUIGO ESPANA SAU", true, nil, .transporte),
        ("IRYO ILSA MADRID", true, nil, .transporte),
        ("CABIFY ESPANA SL", true, nil, .transporte),
        ("UBER *TRIP HELP.UBER.COM", true, nil, .transporte),
        ("BLABLACAR PARIS", true, nil, .transporte),
        ("IBERIA LAE SA MADRID", true, nil, .viajes),
        ("VUELING AIRLINES SA BARCELONA", true, nil, .viajes),
        ("AIR EUROPA LINEAS AEREAS SAU", true, nil, .viajes),
        ("EASYJET AIRLINE COMPANY LTD", true, nil, .viajes),
        // Telefonía y suministros (.casa)
        ("MOVISTAR TELEFONICA DE ESPANA SAU", true, nil, .casa),
        ("VODAFONE ESPANA SAU", true, nil, .casa),
        ("ORANGE ESPAGNE SAU", true, nil, .casa),
        ("DIGI SPAIN TELECOM SL MADRID", true, nil, .casa),
        ("O2 MADRID", true, nil, .casa),
        ("SIMYO MADRID", true, nil, .casa),
        ("JAZZTEL TELECOM SAU", true, nil, .casa),
        ("FINETWORK ALICANTE", true, nil, .casa),
        ("IBERDROLA CLIENTES SAU", true, nil, .casa),
        ("ENDESA ENERGIA SAU", true, nil, .casa),
        ("NATURGY IBERIA SA", true, nil, .casa),
        ("TOTALENERGIES CLIENTES SAU", true, nil, .casa),
        ("OCTOPUS ENERGY ESPANA SL", true, nil, .casa),
        ("HOLALUZ CLIDOM SA BARCELONA", true, nil, .casa),
        ("CANAL DE ISABEL II MADRID", true, nil, .casa),
        // Comercios con nombre opaco salvados por MCC
        ("HERMANOS PEREZ SL MADRID", true, "5812", .comerFuera),
        ("COMERCIAL DEL SUR SA", true, "5411", .supermercado),
        ("INVERSIONES SOL SL", true, "7011", .viajes),
        ("SERVICIOS MEDICOS CENTRO", true, "8021", .salud),
        ("CAJERO AUTOMATICO 045", false, "6011", .efectivo),
    ]

    @Test func tablaRealDeAlMenosCuarentaCasos() {
        #expect(Self.realWorldCases.count >= 40)
        for item in Self.realWorldCases {
            let m = pay(item.text, isShop: item.isShop, mcc: item.mcc)
            #expect(classify(m) == item.expected, "«\(item.text)» (mcc: \(item.mcc ?? "nil"))")
        }
    }

    @Test func todoElDirectorioSigueTeniendoCategoriaValida() {
        for domain in merchantDirectoryDomains where domain != "paypal.com" {
            let cat = directoryCategory(forDomain: domain)
            #expect(cat != nil, "falta categoría para \(domain)")
            #expect(cat != .sinCategoria, "sinCategoria para \(domain)")
        }
    }

    // MARK: 4. Casos negativos

    @Test func personasConNombreOApellidoDeTiendaSiguenEnPersonas() throws {
        // Bizum y transferencias a personas apellidadas como cadenas conocidas.
        let cases = [
            "Bizum a Juan Game",
            "Bizum a Ana Dia",
            "Bizum a Carlos Vips",
            "Transferencia a Pedro Burger",
            "Bizum a Laura Rodilla",
            "Bizum a Luis Tiger",
            "Bizum a Elena Lupa",
        ]
        for text in cases {
            #expect(classify(pay(text, isShop: false)) == .personas, "«\(text)»")
        }

        // Con señal `personPayment == true` y nombre que empieza por un alias corto/ambiguo.
        let signalledNames = ["Game López", "Dia García", "Vips Martínez", "KFC Pérez", "TGB Ruiz", "Ikea Gómez", "O2 Torres", "Rodilla Sanz"]
        for name in signalledNames {
            let m = pay(name, isShop: false, personPayment: true)
            #expect(classify(m) == .personas, "señal persona para «\(name)»")
        }

        // Aviso real de Bizum a «Juan Game» y a «Game».
        var l = Ledger()
        let out1 = l.ingest(
            .notification(bank: .ima, title: nil, subtitle: nil, body: "Has enviado un Bizum de 15,00 € a Juan Game"),
            now: at(11, 18, 10)
        )
        guard case .stored(let m1) = out1 else { Issue.record("esperaba .stored"); return }
        #expect(m1.personPayment == true)
        #expect(!m1.isShop)
        #expect(classify(m1) == .personas)

        let out2 = l.ingest(
            .notification(bank: .ima, title: nil, subtitle: nil, body: "Has enviado un Bizum de 12,00 € a Game"),
            now: at(11, 18, 11)
        )
        guard case .stored(let m2) = out2 else { Issue.record("esperaba .stored"); return }
        #expect(m2.personPayment == true)
        #expect(!m2.isShop)
        #expect(classify(m2) == .personas)

        // Enable Banking: Bizum a «GAME LOPEZ» sin MCC -> no es tienda, es persona.
        let eb = bankRecords(
            from: [ebDebit("15.00", creditor: "GAME LOPEZ", remittance: ["BIZUM ENVIADO"], entry: "neg-1")],
            bank: .ima,
            calendar: madrid
        )
        #expect(eb.first?.isShop == false)
        #expect(eb.first?.personPayment == true)
        var ebLedger = Ledger()
        _ = ebLedger.reconcile(eb, bank: .ima, channel: .bank, coverage: nil, now: at(11, 20), calendar: madrid)
        #expect(ebLedger.state.movements.first.flatMap { classify($0) } == .personas)
    }

    @Test func aliasCortosConOtroNegocioDetrasNoFalsanLaTienda() {
        #expect(merchantDomain(for: "Game Bar", isShop: true) == nil)
        #expect(classify(pay("Game Bar", isShop: true)) == .comerFuera)
        #expect(merchantDomain(for: "TGB Consulting", isShop: true) == nil)
        #expect(classify(pay("TGB Consulting", isShop: true)) == .sinCategoria)
        #expect(merchantDomain(for: "Dia Consultoria", isShop: true) == nil)
        #expect(merchantDomain(for: "Rodilla Clinica", isShop: true) == nil)
    }

    // MARK: 5. Cero ruptura de compatibilidad con datos guardados

    @Test func compatibilidadByteAByteYLibrosAntiguos() throws {
        // Espejo exacto del formato codificado de Movement ANTES de añadir `merchantCategoryCode`.
        struct LegacyMovementV1: Encodable {
            let id: UUID
            let bank: BankID
            let amountCents: Int
            let merchant: String?
            let kind: MovementKind
            let source: Movement.Source
            let date: Date
            let pairedAcrossSources: Bool
            let isShop: Bool
            let flaggedNotMine: Bool
            let dayOnly: Bool
            let excludedFromSpending: Bool
        }

        // 1. Un Movement sin MCC codifica byte a byte igual que antes (sin la clave `merchantCategoryCode`).
        let fixedID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        let fixedDate = Date(timeIntervalSinceReferenceDate: 0)
        let m = Movement(
            id: fixedID,
            bank: .rev,
            amountCents: -1_250,
            merchant: "Mercadona",
            kind: .payment,
            source: .notification,
            date: fixedDate,
            isShop: true
        )
        let legacy = LegacyMovementV1(
            id: fixedID,
            bank: .rev,
            amountCents: -1_250,
            merchant: "Mercadona",
            kind: .payment,
            source: .notification,
            date: fixedDate,
            pairedAcrossSources: false,
            isShop: true,
            flaggedNotMine: false,
            dayOnly: false,
            excludedFromSpending: false
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(m)
        let legacyEncoded = try encoder.encode(legacy)
        #expect(encoded == legacyEncoded)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("merchantCategoryCode"))

        // 2. Con MCC sí se guarda y se lee en ida y vuelta.
        var withMCC = m
        withMCC.merchantCategoryCode = "5945"
        let roundTrip = try JSONDecoder().decode(Movement.self, from: JSONEncoder().encode(withMCC))
        #expect(roundTrip == withMCC)
        #expect(roundTrip.merchantCategoryCode == "5945")

        // 3. Un ledger.json antiguo sin el campo nuevo carga idéntico.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcc-compat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let oldLedgerJSON = """
        {"balances":[],"movements":[
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","bank":"rev","amountCents":-1250,"merchant":"Mercadona","kind":"payment",
        "source":"bank","date":0,"isShop":true,"bankRef":"r1","bankStatus":"booked"}
        ],"unread":[]}
        """
        try Data(oldLedgerJSON.utf8).write(to: dir.appendingPathComponent("ledger.json"))
        let loaded = try FileStore(directory: dir).load()
        #expect(loaded.movements.count == 1)
        #expect(loaded.movements[0].merchant == "Mercadona")
        #expect(loaded.movements[0].merchantCategoryCode == nil)
        #expect(categoryOf(loaded.movements[0], in: loaded, subscriptionKeys: []) == .supermercado)
    }
}
