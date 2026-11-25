import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date { date(11, day, hour, minute) }

private func pay(_ cents: Int, _ merchant: String?, _ when: Date, bank: BankID = .rev, isShop: Bool = false) -> Movement {
    Movement(bank: bank, amountCents: -cents, merchant: merchant, kind: .payment, source: .notification, date: when,
             isShop: isShop)
}

private func income(_ cents: Int, _ merchant: String?, _ when: Date) -> Movement {
    Movement(bank: .ima, amountCents: cents, merchant: merchant, kind: .income, source: .notification, date: when)
}

private func state(_ movements: [Movement], balances: [BankID: ManualBalance] = [:], budgets: Budgets = Budgets()) -> LedgerState {
    LedgerState(balances: balances, movements: movements, unread: [], alertSettings: AlertSettings(), mutedMerchants: [],
                budgets: budgets)
}

/// Lo que publica la app tras guardar el último movimiento de `movements` (`immediateAlerts`).
private func immediate(_ movements: [Movement], balances: [BankID: ManualBalance] = [:], budgets: Budgets = Budgets(),
                       now: Date? = nil) -> [Insight] {
    let last = movements.last!
    return immediateAlerts(afterStoring: last, in: state(movements, balances: balances, budgets: budgets),
                           now: now ?? last.date, calendar: cal)
}

/// El feed de «Avisos» (`insights`).
private func feed(_ movements: [Movement], balances: [BankID: ManualBalance] = [:], budgets: Budgets = Budgets(),
                  now: Date) -> [Insight] {
    insights(for: state(movements, balances: balances, budgets: budgets), now: now, calendar: cal)
}

/// Ideas que salen de los generadores DE VERDAD (`immediateAlerts` e `insights`), no copias de su redacción: si alguien
/// cambia un título (añade una cifra, reordena «Netflix: 13,99 € mañana»), estas pruebas ven el texto nuevo.
/// `merchantSuffix` se añade a cada comercio (para probar comercios con cifras).
private func generatedInsights(merchantSuffix s: String = "") -> [Insight] {
    let low = [BankID.rev: ManualBalance(cents: 10_500, setAt: nov(1), fromBank: true)]
    let zara = [pay(3_000, "Zara\(s)", nov(1)), pay(4_000, "Zara\(s)", nov(5)), pay(5_000, "Zara\(s)", nov(9))]
    let netflix = [pay(1_399, "Netflix\(s)", date(9, 22)), pay(1_399, "Netflix\(s)", date(10, 22))]
    let pace = { (cents: Int) in [pay(5_000, nil, date(10, 2)), pay(cents, nil, nov(18))] }
    let week = [pay(7_994, nil, nov(17)), pay(5_000, nil, nov(19)), pay(14_194, nil, nov(10))]
    let budgets = Budgets(monthlyCents: 70_000, byCategory: [.comerFuera: 12_000])
    // Un pago en comercio de «Comer fuera» (como en las pruebas de presupuestos).
    let glovo = { (cents: Int, when: Date) in pay(cents, "Glovo\(s)", when, isShop: true) }
    var out: [Insight] = []
    out += immediate([pay(501, "Mercadona\(s)", nov(19))], balances: low)                                  // saldo bajo
    out += immediate([pay(32_000, "MediaMarkt\(s)", nov(19))])                                            // pago grande
    out += immediate(zara + [pay(12_000, "Zara\(s)", nov(19))])                                          // poco habitual
    out += immediate([income(185_000, "Nómina ACME\(s)", nov(19))])                                       // nómina
    out += immediate([income(90_000, "Transferencia\(s)", nov(19))])                                      // ingreso grande
    out += immediate([pay(1_250, "Mercadona\(s)", nov(19, 12, 0)), pay(1_250, "Mercadona\(s)", nov(19, 12, 10))]) // duplicado
    out += immediate([pay(1_099, "Spotify\(s)", date(10, 19)), pay(1_199, "Spotify\(s)", nov(19))])        // sube
    out += immediate([pay(1_199, "Spotify\(s)", date(10, 19)), pay(1_099, "Spotify\(s)", nov(19))])        // baja
    // Presupuestos: de categoría al 80 % y al 100 %, y el del mes.
    out += immediate([glovo(9_000, nov(10)), glovo(1_000, nov(19, 12, 30))], budgets: budgets,
                     now: nov(19, 13))
    out += immediate([glovo(9_000, nov(10)), glovo(4_200, nov(19, 12, 30))], budgets: budgets,
                     now: nov(19, 13))
    out += immediate([pay(55_000, "Mercadona\(s)", nov(5)), pay(1_700, "Mercadona\(s)", nov(19, 12, 30))],
                     budgets: Budgets(monthlyCents: 70_000), now: nov(19, 13))
    out += immediate([pay(55_000, "Mercadona\(s)", nov(5)), pay(20_000, "Mercadona\(s)", nov(19, 12, 30))],
                     budgets: Budgets(monthlyCents: 70_000), now: nov(19, 13))
    // El feed: suscripción «el domingo», «mañana» y «hoy»; ritmo por debajo y por encima; resumen semanal; presupuestos.
    for day in [19, 21, 22] { out += feed(netflix, now: nov(day)) }
    out += feed(pace(4_000), now: nov(19))
    out += feed(pace(9_000), now: nov(19))
    out += feed(week, now: nov(22))
    out += feed([glovo(9_000, nov(10)), glovo(4_200, nov(11))], budgets: budgets, now: nov(19, 13))
    return out
}

private func noDigits(_ text: String) -> Bool { !text.contains { $0.isNumber } }

/// «Avisos con el ojo cerrado»: con el ojo abierto, el texto de cada aviso es EXACTAMENTE el de hoy; con el ojo cerrado,
/// ningún dígito en el título ni en el cuerpo de ningún tipo de aviso que compone la app.
/// Fuera de esta prueba, a propósito: los avisos de caducidad del banco (`BankReminders`, «Caduca el …») llevan una
/// FECHA, no dinero; no tienen nada que ocultar con el ojo y se quedan como están. El resumen de la mañana y el aviso de
/// «sin leer» no llevan cifras.
@Suite struct PrivateNotificationTextTests {
    private let t0 = Date(timeIntervalSince1970: 1_764_000_000)

    private func movement(_ cents: Int, _ merchant: String?, _ kind: MovementKind, _ bank: BankID) -> Movement {
        Movement(bank: bank, amountCents: cents, merchant: merchant, kind: kind, source: .notification, date: t0)
    }

    // MARK: Cobertura: el generador real produce todos los tipos

    @Test func theGeneratorsProduceEveryKind() {
        let produced = Set(generatedInsights().map(\.kind))
        let missing = Set(InsightKind.allCases).subtracting(produced)
        #expect(missing.isEmpty, "Tipos de aviso que la prueba no hace salir del generador: \(missing)")
    }

    // MARK: Ojo abierto: el texto de hoy, idéntico (cadenas fijas)

    @Test func withTheEyeOpenEveryTextIsTodaysText() {
        for i in generatedInsights() {
            let open = notificationText(for: i, hidden: false)
            #expect(open.title == i.title && open.body == (i.detail ?? ""))
        }
        let digest = (title: "Esta semana has gastado 179,92\u{00A0}€", body: "20,00\u{00A0}€ menos que la anterior")
        let openDigest = weeklyDigestNotificationText(digest, hidden: false)
        #expect(openDigest.title == digest.title && openDigest.body == digest.body)
    }

    /// Cadenas doradas: el aviso con el ojo abierto dice, letra a letra, lo de siempre (M-7).
    @Test func goldenOpenTexts() {
        let pay = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: 32_770, estimated: false, hidden: false)
        #expect(pay.title == "Has pagado 12,50\u{00A0}€ en Mercadona")
        #expect(pay.body == "Te quedan 327,70\u{00A0}€ en Revolut")
        let estimated = alertText(for: movement(3500, "Bizum de Carlos", .income, .ima), balance: 32_770, estimated: true,
                                  hidden: false)
        #expect(estimated.title == "Has recibido 35,00\u{00A0}€: Bizum de Carlos")
        #expect(estimated.body == "Te quedan unos 327,70\u{00A0}€ en imagin")
        let noBalance = alertText(for: movement(-1250, nil, .payment, .tr), balance: nil, estimated: false, hidden: false)
        #expect(noBalance.title == "Has pagado 12,50\u{00A0}€" && noBalance.body == "Saldo de Trade Republic sin configurar")
        let sub = subscriptionReminderText(merchant: "Netflix", amountCents: 1_399, bank: .rev, hidden: false)
        #expect(sub.title == "Mañana se cobra Netflix: 13,99\u{00A0}€" && sub.body == "En Revolut")

        // Una por cada tipo de idea, tal cual sale del generador.
        let golden: [InsightKind: (String, String)] = [
            .lowBalance: ("Saldo bajo en Revolut", "Te quedan 99,99\u{00A0}€"),
            .largePayment: ("Pago grande: 320,00\u{00A0}€ en MediaMarkt", ""),
            .unusualPayment: ("Pago poco habitual en Zara: 120,00\u{00A0}€", "Sueles gastar unos 40,00\u{00A0}€"),
            .salary: ("Has recibido tu nómina: 1.850,00\u{00A0}€", ""),
            .largeIncome: ("Ingreso grande: 900,00\u{00A0}€ de Transferencia", ""),
            .duplicateCharge: ("Posible cobro duplicado: 12,50\u{00A0}€ en Mercadona", "Dos cargos iguales en pocos minutos"),
            .subscriptionPriceChange: ("Spotify ha subido 1,00\u{00A0}€", "Ahora 11,99\u{00A0}€ al mes"),
            .subscriptionUpcoming: ("Netflix se cobra el domingo: 13,99\u{00A0}€", ""),
            .spendingPace: ("Vas 10,00\u{00A0}€ por debajo del mes pasado", "Llevas 40,00\u{00A0}€ este mes"),
            .weeklyDigest: ("Esta semana has gastado 129,94\u{00A0}€", "12,00\u{00A0}€ menos que la anterior"),
            .budgetWarning: ("Llevas el 83\u{00A0}% de tu presupuesto de Comer fuera",
                             "Te quedan 20,00\u{00A0}€ para lo que queda de mes"),
            .budgetExceeded: ("Te has pasado del presupuesto de Comer fuera", "Llevas 132,00\u{00A0}€ de 120,00\u{00A0}€"),
        ]
        let all = generatedInsights()
        for kind in InsightKind.allCases {
            guard let (title, body) = golden[kind] else { Issue.record("\(kind) sin cadena dorada"); continue }
            let first = all.first { $0.kind == kind }
            let open = first.map { notificationText(for: $0, hidden: false) }
            #expect(open?.title == title && open?.body == body, "\(kind): «\(open?.title ?? "nil")» / «\(open?.body ?? "nil")»")
        }
    }

    // MARK: Ojo cerrado: ningún dígito en ningún aviso

    @Test func withTheEyeClosedNoNotificationHasADigit() {
        var all: [(String, String, String)] = []
        for m in [movement(-1250, "Mercadona", .payment, .rev), movement(3500, "Bizum de Carlos", .income, .ima),
                  movement(-1250, nil, .payment, .tr), movement(185_000, "Nómina ACME", .income, .ima)] {
            for (balance, estimated) in [(nil, false), (32_770, false), (32_770, true)] as [(Int?, Bool)] {
                let t = alertText(for: m, balance: balance, estimated: estimated, hidden: true)
                all.append(("movimiento", t.title, t.body))
            }
        }
        for i in generatedInsights() {
            let t = notificationText(for: i, hidden: true)
            all.append((i.kind.rawValue, t.title, t.body))
        }
        for kind in InsightKind.allCases {
            let bare = Insight(id: "x", kind: kind, severity: .info, title: "1", detail: "2", date: t0, bank: nil,
                               merchant: nil, movementID: nil)
            let t = neutralText(for: bare)
            all.append(("neutro \(kind.rawValue)", t.title, t.body))
        }
        let digest = weeklyDigestNotificationText((title: "Esta semana has gastado 179,92\u{00A0}€", body: "x"), hidden: true)
        all.append(("resumen semanal programado", digest.title, digest.body))
        let sub = subscriptionReminderText(merchant: "Netflix", amountCents: 1_399, bank: .rev, hidden: true)
        all.append(("suscripción programada", sub.title, sub.body))
        all.append(("resumen de la mañana", morningReminderText.title, morningReminderText.body))
        for (kind, title, body) in all {
            #expect(noDigits(title) && noDigits(body), "\(kind): «\(title)» / «\(body)»")
            #expect(!title.isEmpty, "\(kind): sin título")
            #expect(!title.contains("•") && !body.contains("•"), "\(kind): puntos de máscara en el texto del sistema")
        }
    }

    /// M-3 (decisión del controlador): un comercio con cifras (teléfono, referencia) no sale con el ojo cerrado; sale el
    /// texto neutro del tipo, sin el comercio.
    @Test func aMerchantWithDigitsFallsBackToTheNeutralText() {
        let insights = generatedInsights(merchantSuffix: " Ref 4532")
        #expect(Set(insights.map(\.kind)) == Set(InsightKind.allCases))
        for i in insights {
            let t = notificationText(for: i, hidden: true)
            #expect(noDigits(t.title) && noDigits(t.body), "\(i.kind): «\(t.title)» / «\(t.body)»")
            #expect(!t.title.contains("Ref"), "\(i.kind): el comercio con cifras sigue en «\(t.title)»")
        }
        let pay = alertText(for: movement(-1250, "Bizum 612345678", .payment, .rev), balance: 100, estimated: false, hidden: true)
        #expect(pay.title == "Pago" && pay.body == "Revolut")
        let income = alertText(for: movement(1250, "Ref 4532", .income, .ima), balance: nil, estimated: false, hidden: true)
        #expect(income.title == "Ingreso" && income.body == "imagin")
        let sub = subscriptionReminderText(merchant: "Netflix 4K", amountCents: 1_399, bank: .rev, hidden: true)
        #expect(sub.title == "Mañana se cobra una suscripción" && sub.body == "En Revolut")
    }

    /// Los textos exactos con el ojo cerrado (lo mínimo que dice qué ha pasado y dónde), sacados del generador real.
    @Test func theClosedTextsSayWhatHappenedAndWhere() {
        let pay = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: 32_770, estimated: false, hidden: true)
        #expect(pay.title == "Pago en Mercadona" && pay.body == "Revolut")
        let income = alertText(for: movement(3500, "Bizum de Carlos", .income, .ima), balance: nil, estimated: false, hidden: true)
        #expect(income.title == "Ingreso de Bizum de Carlos" && income.body == "imagin")
        #expect(alertText(for: movement(-1250, nil, .payment, .rev), balance: nil, estimated: false, hidden: true).title == "Pago")
        let closed = generatedInsights().map { notificationText(for: $0, hidden: true) }
        let titles = closed.map(\.title)
        for expected in [
            "Saldo bajo en Revolut", "Pago grande en MediaMarkt", "Pago poco habitual en Zara", "Has recibido tu nómina",
            "Ingreso grande de Transferencia", "Posible cobro duplicado en Mercadona", "Spotify ha subido de precio",
            "Spotify ha bajado de precio", "Netflix se cobra el domingo", "Netflix se cobra mañana", "Netflix se cobra hoy",
            "Vas por encima del mes pasado", "Vas por debajo del mes pasado", "Cerca del límite de tu presupuesto del mes",
            "Cerca del límite de tu presupuesto de Comer fuera", "Te has pasado del presupuesto de Comer fuera",
            "Te has pasado del presupuesto del mes", "Resumen semanal",
        ] {
            #expect(titles.contains(expected), "Falta «\(expected)» en \(titles)")
        }
        let duplicate = closed.first { $0.title.hasPrefix("Posible cobro duplicado") }
        #expect(duplicate?.body == "Dos cargos iguales en pocos minutos", "el detalle sin cifras se queda")
    }

    /// El sentido (sube/baja, encima/debajo) sale de los campos, no del texto: cambiar la redacción del título no le da
    /// la vuelta al aviso cerrado.
    @Test func theDirectionComesFromTheFactsNotTheTitle() {
        let up = Insight(id: "x", kind: .spendingPace, severity: .info, title: "Vas 4,00 € por debajo… (texto cambiado)",
                         detail: nil, date: t0, bank: nil, merchant: nil, movementID: nil, facts: InsightFacts(up: true))
        #expect(notificationText(for: up, hidden: true).title == "Vas por encima del mes pasado")
        let down = Insight(id: "x", kind: .subscriptionPriceChange, severity: .info, title: "Netflix ha subido (cambiado)",
                           detail: nil, date: t0, bank: nil, merchant: "Netflix", movementID: nil, facts: InsightFacts(up: false))
        #expect(notificationText(for: down, hidden: true).title == "Netflix ha bajado de precio")
    }
}
