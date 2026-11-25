import Foundation
import Testing
@testable import MiBancoCore

/// «Avisos con el ojo cerrado»: con el ojo abierto, el texto de cada aviso es EXACTAMENTE el de hoy; con el ojo cerrado,
/// ningún dígito en el título ni en el cuerpo de ningún tipo de aviso que compone la app.
@Suite struct PrivateNotificationTextTests {
    private let t0 = Date(timeIntervalSince1970: 1_764_000_000)

    private func movement(_ cents: Int, _ merchant: String?, _ kind: MovementKind, _ bank: BankID) -> Movement {
        Movement(bank: bank, amountCents: cents, merchant: merchant, kind: kind, source: .notification, date: t0)
    }

    private func insight(_ kind: InsightKind, _ title: String, _ detail: String? = nil, bank: BankID? = .rev,
                         merchant: String? = nil) -> Insight {
        Insight(id: "\(kind.rawValue)|x", kind: kind, severity: .info, title: title, detail: detail, date: t0,
                bank: bank, merchant: merchant, movementID: nil)
    }

    /// Un ejemplo de cada aviso de idea, con sus textos tal cual los compone `Insights.swift` (cifras incluidas).
    private var everyInsight: [Insight] {
        let e = { (cents: Int) in formatEUR(cents) }
        return [
            insight(.lowBalance, "Saldo bajo en Revolut", "Te quedan \(e(4_210))"),
            insight(.largePayment, "Pago grande: \(e(32_000)) en Zara", merchant: "Zara"),
            insight(.unusualPayment, "Pago poco habitual en Mercadona: \(e(12_050))", "Sueles gastar unos \(e(3_000))",
                    merchant: "Mercadona"),
            insight(.salary, "Has recibido tu nómina: \(e(185_000))", merchant: "Nómina ACME"),
            insight(.largeIncome, "Ingreso grande: \(e(90_000)) de Carlos", merchant: "Carlos"),
            insight(.duplicateCharge, "Posible cobro duplicado: \(e(1_250)) en Mercadona", "Dos cargos iguales en pocos minutos",
                    merchant: "Mercadona"),
            insight(.subscriptionPriceChange, "Netflix ha subido \(e(200))", "Ahora \(e(1_399)) al mes", merchant: "Netflix"),
            insight(.subscriptionPriceChange, "Spotify ha bajado \(e(100))", "Ahora \(e(999)) al mes", merchant: "Spotify"),
            insight(.subscriptionUpcoming, "Netflix se cobra mañana: \(e(1_399))", merchant: "Netflix"),
            insight(.spendingPace, "Vas \(e(4_500)) por encima del mes pasado", "Llevas \(e(28_752)) este mes", bank: nil),
            insight(.spendingPace, "Vas \(e(4_500)) por debajo del mes pasado", "Llevas \(e(18_752)) este mes", bank: nil),
            insight(.weeklyDigest, "Esta semana has gastado \(e(17_992))", "\(e(2_000)) menos que la anterior", bank: nil),
            insight(.budgetWarning, "Llevas el 85\u{00A0}% de tu presupuesto del mes",
                    "Te quedan \(e(7_500)) para lo que queda de mes", bank: nil),
            insight(.budgetWarning, "Llevas el 92\u{00A0}% de tu presupuesto de Supermercado",
                    "Te quedan \(e(1_500)) para lo que queda de mes", bank: nil),
            insight(.budgetExceeded, "Te has pasado del presupuesto del mes", "Llevas \(e(52_000)) de \(e(50_000))", bank: nil),
        ]
    }

    private func noDigits(_ text: String) -> Bool { !text.contains { $0.isNumber } }

    // MARK: Ojo abierto: el texto de hoy, idéntico

    @Test func withTheEyeOpenEveryTextIsTodaysText() {
        for m in [movement(-1250, "Mercadona", .payment, .rev), movement(3500, "Bizum de Carlos", .income, .ima),
                  movement(-1250, nil, .payment, .rev)] {
            for (balance, estimated) in [(nil, false), (32_770, false), (32_770, true)] as [(Int?, Bool)] {
                let today = alertText(for: m, balance: balance, estimated: estimated)
                let open = alertText(for: m, balance: balance, estimated: estimated, hidden: false)
                #expect(open.title == today.title && open.body == today.body)
            }
        }
        for i in everyInsight {
            let open = notificationText(for: i, hidden: false)
            #expect(open.title == i.title && open.body == (i.detail ?? ""))
        }
        let digest = (title: "Esta semana has gastado 179,92\u{00A0}€", body: "20,00\u{00A0}€ menos que la anterior")
        let openDigest = weeklyDigestNotificationText(digest, hidden: false)
        #expect(openDigest.title == digest.title && openDigest.body == digest.body)
        let openSub = subscriptionReminderText(merchant: "Netflix", amountCents: 1_399, bank: .rev, hidden: false)
        #expect(openSub.title == "Mañana se cobra Netflix: \(formatEUR(1_399))" && openSub.body == "En Revolut")
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
        for i in everyInsight {
            let t = notificationText(for: i, hidden: true)
            all.append((i.kind.rawValue, t.title, t.body))
        }
        let digest = weeklyDigestNotificationText((title: "Esta semana has gastado 179,92\u{00A0}€", body: "x"), hidden: true)
        all.append(("resumen semanal programado", digest.title, digest.body))
        let sub = subscriptionReminderText(merchant: "Netflix", amountCents: 1_399, bank: .rev, hidden: true)
        all.append(("suscripción programada", sub.title, sub.body))
        // Los que nunca llevan cifras siguen sin llevarlas.
        all.append(("resumen de la mañana", morningReminderText.title, morningReminderText.body))
        for (kind, title, body) in all {
            #expect(noDigits(title) && noDigits(body), "\(kind): «\(title)» / «\(body)»")
            #expect(!title.isEmpty, "\(kind): sin título")
            #expect(!title.contains("•") && !body.contains("•"), "\(kind): puntos de máscara en el texto del sistema")
        }
        // Todos los tipos de aviso de ideas están cubiertos.
        let kinds = Set(everyInsight.map(\.kind))
        for kind in [InsightKind.lowBalance, .largePayment, .unusualPayment, .salary, .duplicateCharge, .subscriptionUpcoming,
                     .subscriptionPriceChange, .spendingPace, .weeklyDigest, .largeIncome, .budgetWarning, .budgetExceeded] {
            #expect(kinds.contains(kind), "\(kind) sin probar")
        }
    }

    /// Los textos exactos con el ojo cerrado (lo mínimo que dice qué ha pasado y dónde).
    @Test func theClosedTextsSayWhatHappenedAndWhere() {
        let pay = alertText(for: movement(-1250, "Mercadona", .payment, .rev), balance: 32_770, estimated: false, hidden: true)
        #expect(pay.title == "Pago en Mercadona" && pay.body == "Revolut")
        let income = alertText(for: movement(3500, "Bizum de Carlos", .income, .ima), balance: nil, estimated: false, hidden: true)
        #expect(income.title == "Ingreso de Bizum de Carlos" && income.body == "imagin")
        #expect(alertText(for: movement(-1250, nil, .payment, .rev), balance: nil, estimated: false, hidden: true).title == "Pago")
        let texts = everyInsight.map { notificationText(for: $0, hidden: true).title }
        #expect(texts.contains("Saldo bajo en Revolut"))
        #expect(texts.contains("Pago grande en Zara"))
        #expect(texts.contains("Netflix ha subido de precio"))
        #expect(texts.contains("Spotify ha bajado de precio"))
        #expect(texts.contains("Netflix se cobra mañana"))
        #expect(texts.contains("Vas por encima del mes pasado"))
        #expect(texts.contains("Vas por debajo del mes pasado"))
        #expect(texts.contains("Cerca del límite de tu presupuesto del mes"))
        #expect(texts.contains("Cerca del límite de tu presupuesto de Supermercado"))
        #expect(texts.contains("Resumen semanal"))
        let duplicate = notificationText(for: everyInsight.first { $0.kind == .duplicateCharge }!, hidden: true)
        #expect(duplicate.body == "Dos cargos iguales en pocos minutos", "el detalle sin cifras se queda")
    }
}
