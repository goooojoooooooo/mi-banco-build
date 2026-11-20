import Foundation
import Testing
@testable import MiBancoCore

private struct Row {
    let title: String
    let instruction: String
    let tap: String
    let help: String
}

private func steps(_ track: GuideTrack) -> [Row] {
    guideSteps(for: track).map { Row(title: $0.title, instruction: $0.instruction, tap: $0.tapTarget, help: $0.help) }
}

private let retry = "Si no te sale, vuelve un paso atrás y repítelo."
private let shared1 = Row(title: "Abre Atajos", instruction: "Toca el botón de abajo: se abre la app Atajos.",
                          tap: "Abrir Atajos", help: "Si no tienes Atajos, descárgala gratis del App Store: es de Apple.")
private let shared2 = Row(title: "Ve a Automatización", instruction: "Abajo, toca «Automatización».", tap: "Automatización",
                          help: "Si ves tus atajos, toca «Atajos» arriba a la izquierda hasta llegar al principio.")
private let shared3 = Row(title: "Crea una nueva", instruction: "Toca «+» arriba a la derecha.", tap: "+",
                          help: "Si es la primera, el botón dice «Nueva automatización».")
private let runRows: [Row] = [
    Row(title: "Que vaya sola", instruction: "Marca «Ejecutar inmediatamente».", tap: "Ejecutar inmediatamente",
        help: "Si no lo marcas, el iPhone te preguntará cada vez."),
    Row(title: "Sin avisos de Atajos", instruction: "Apaga «Notificar al ejecutar».", tap: "Notificar al ejecutar",
        help: "Así Atajos no te enseña un aviso cada vez que funciona. El interruptor debe quedar apagado."),
    Row(title: "Sigue", instruction: "Toca «Siguiente».", tap: "Siguiente", help: retry),
    Row(title: "Empieza en blanco", instruction: "Toca «Nueva automatización en blanco».", tap: "Nueva automatización en blanco",
        help: "Si ves sugerencias, baja hasta el final."),
    Row(title: "Añade una acción", instruction: "Toca «Añadir acción».", tap: "Añadir acción", help: retry),
]
private let help8 = "Si no aparece, abre Mi Banco una vez y vuelve a Atajos."
private let help9 = "No hay que escribir nada: es una lista."

private func fieldRow(_ name: String, _ source: String) -> Row {
    Row(title: "Rellena «\(name)»",
        instruction: "Toca «\(name)». En la lista de abajo, elige \(source) y después su propiedad \(name).", tap: name,
        help: "Si solo te sale una variable (por ejemplo «Entrada de atajo»), tócala y busca dentro «\(name)». \(retry)")
}

private func bankSteps(_ bank: String) -> [Row] {
    [shared1, shared2, shared3,
     Row(title: "Busca «Notificación»", instruction: "Escribe «Notificación» en el buscador y tócala.", tap: "Notificación",
         help: retry),
     Row(title: "Elige la app", instruction: "Toca «Aplicación».", tap: "Aplicación", help: "Si no la ves, baja un poco con el dedo."),
     Row(title: "Elige \(bank)", instruction: "Toca «\(bank)» en la lista.", tap: bank,
         help: "Si \(bank) no sale en la lista, ábrelo una vez y vuelve."),
     Row(title: "Confirma", instruction: "Toca «OK» arriba a la derecha.", tap: "OK", help: retry)]
        + runRows + [
            Row(title: "Busca Mi Banco", instruction: "Toca el buscador y escribe «Mi Banco».", tap: "Mi Banco", help: help8),
            Row(title: "Elige la acción", instruction: "Toca «Registrar aviso».", tap: "Registrar aviso", help: help8),
            Row(title: "Elige el banco", instruction: "Toca «Banco».", tap: "Banco", help: help9),
            Row(title: "Elige \(bank)", instruction: "Toca «\(bank)» en la lista.", tap: bank, help: help9),
            fieldRow("Título", "la notificación"),
            fieldRow("Subtítulo", "la notificación"),
            fieldRow("Cuerpo", "la notificación"),
            Row(title: "Listo", instruction: "Toca «OK» arriba a la derecha. Cuando \(bank) te avise, Mi Banco se enterará.",
                tap: "OK", help: "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada."),
        ]
}

private func applePaySteps(_ bank: String, bankLine: String) -> [Row] {
    [shared1, shared2, shared3,
     Row(title: "Busca «Transacción»", instruction: "Escribe «Transacción» en el buscador y tócala (es la de Cartera).",
         tap: "Transacción", help: "Tiene el icono de Cartera. \(retry)"),
     Row(title: "Tus tarjetas de \(bank)", instruction: "Marca solo las tarjetas de «\(bank)». Quita la marca a las demás.", tap: bank,
         help: "Cada banco tiene su propia automatización: así Mi Banco sabe de cuál es cada pago."),
     Row(title: "Sigue", instruction: "Toca «Siguiente».", tap: "Siguiente", help: retry)]
        + runRows + [
            Row(title: "Busca Mi Banco", instruction: "Toca el buscador y escribe «Mi Banco».", tap: "Mi Banco", help: help8),
            Row(title: "Elige la acción", instruction: "Toca «Registrar pago con Cartera».", tap: "Registrar pago con Cartera",
                help: help8),
            Row(title: "Elige el banco", instruction: "Toca «Banco».", tap: "Banco", help: help9),
            Row(title: "Elige \(bank)", instruction: bankLine, tap: bank, help: help9),
            fieldRow("Importe", "la transacción"),
            fieldRow("Comercio", "la transacción"),
            Row(title: "Listo",
                instruction: "Toca «OK» arriba a la derecha. Cuando pagues con la tarjeta de \(bank), Mi Banco se enterará.",
                tap: "OK",
                help: "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada. Para otro banco, repite su guía de Apple Pay."),
        ]
}

private let applePayExpected: [(GuideTrack, [Row])] = [
    (.walletImagin, applePaySteps("imagin",
                                  bankLine: "Toca «imagin» en la lista. Recuerda: imagin solo avisa de sus pagos a través de Apple Pay.")),
    (.walletRevolut, applePaySteps("Revolut", bankLine: "Toca «Revolut» en la lista: esta automatización es solo de sus tarjetas.")),
    (.walletTradeRepublic, applePaySteps("Trade Republic",
                                         bankLine: "Toca «Trade Republic» en la lista: esta automatización es solo de sus tarjetas.")),
]

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// Lo que va entre «» en un texto.
private func quoted(_ text: String) -> [String] {
    var out: [String] = []
    var current: String?
    for ch in text {
        if ch == "«" { current = "" } else if ch == "»" {
            if let c = current { out.append(c) }
            current = nil
        } else if current != nil { current?.append(ch) }
    }
    return out
}

private func sightingState(_ track: GuideTrack, first: Date, last: Date) -> LedgerState {
    LedgerState(guideSightings: [track.rawValue: GuideSighting(first: first, last: last)])
}

private let day: TimeInterval = 86_400
/// Un mediodía UTC, para que contar días no dependa de la hora.
private let t0 = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: day) + day / 2)

@Suite struct SetupGuideTests {
    @Test func pasosDeLasGuiasDeAvisos() {
        for (track, bank) in [(GuideTrack.revolut, "Revolut"), (.tradeRepublic, "Trade Republic")] {
            let got = steps(track)
            let expected = bankSteps(bank)
            #expect(got.count == 20)
            #expect(expected.count == 20)
            for (a, b) in zip(got, expected) {
                #expect(a.title == b.title)
                #expect(a.instruction == b.instruction)
                #expect(a.tap == b.tap)
                #expect(a.help == b.help)
            }
        }
    }

    @Test func pasosDeApplePayUnoPorBanco() {
        #expect(GuideTrack.allCases.filter(\.isApplePay).count == 3)
        for (track, expected) in applePayExpected {
            let got = steps(track)
            #expect(got.count == 18)
            #expect(expected.count == 18)
            for (a, b) in zip(got, expected) {
                #expect(a.title == b.title)
                #expect(a.instruction == b.instruction)
                #expect(a.tap == b.tap)
                #expect(a.help == b.help)
            }
        }
        #expect(Set(GuideTrack.allCases.flatMap { guideSteps(for: $0).map(\.id) }).count == 20 * 2 + 18 * 3)
    }

    @Test func applePayMarcaSoloLasTarjetasDeSuBanco() {
        for track in GuideTrack.allCases where track.isApplePay {
            let cards = guideSteps(for: track)[4]
            #expect(cards.instruction.contains("solo las tarjetas de «\(track.bankName)»"))
            #expect(!cards.instruction.contains("todas") && !cards.help.contains("todas"))
            // El paso del banco nombra el banco; el de imagin repite que solo funciona por Apple Pay.
            let pick = guideSteps(for: track)[14]
            #expect(pick.instruction.contains("«\(track.bankName)»"))
            #expect(pick.instruction.contains("Apple Pay") == (track == .walletImagin))
        }
        #expect(GuideTrack.walletImagin.title == "Apple Pay de imagin")
    }

    @Test func cadaPasoUnaSolaAccion() {
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) where step.tapTarget != "Abrir Atajos" {
                #expect(quoted(step.instruction) == [step.tapTarget], "\(step.id): \(step.instruction)")
            }
        }
        // El detector de dos toques funciona: «A» y «B» distintos fallarían.
        #expect(Set(quoted("Toca «A» y elige «B».")).count == 2)
        #expect(Set(quoted("Toca «Título» y su propiedad «Título».")).count == 1)
    }

    @Test func cadaCampoSeMapeaEnSuPaso() {
        for track in GuideTrack.allCases {
            let fields = track.isApplePay ? ["Importe", "Comercio"] : ["Título", "Subtítulo", "Cuerpo"]
            for name in fields {
                let step = guideSteps(for: track).first { $0.title == "Rellena «\(name)»" }
                #expect(step != nil, "\(track) \(name)")
                guard let step else { continue }
                #expect(step.instruction.hasPrefix("Toca «\(name)»."))
                #expect(step.instruction.contains("elige"))
                #expect(step.instruction.contains("su propiedad \(name)"))
                #expect(step.help.contains("solo te sale una variable"))
            }
        }
    }

    @Test func nadaDeDirigirseAlDesarrollador() {
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) {
                for text in [step.title, step.instruction, step.help] {
                    for forbidden in ["mándame", "captura", "avísame", "desarrollador"] {
                        #expect(!text.lowercased().contains(forbidden), "\(step.id): \(text)")
                    }
                }
                #expect(!step.place.isEmpty)
            }
        }
    }

    @Test func nombresDeLasAcciones() {
        #expect(guideNoticeIntentNames == ["Registrar aviso", "Banco", "Título", "Subtítulo", "Cuerpo"])
        #expect(guideWalletIntentNames == ["Registrar pago con Cartera", "Banco", "Importe", "Comercio"])
        #expect(guideIntentNames == ["Registrar aviso", "Banco", "Título", "Subtítulo", "Cuerpo",
                                     "Registrar pago con Cartera", "Importe", "Comercio"])
        let all = GuideTrack.allCases.flatMap { guideSteps(for: $0).map(\.instruction) }
        for name in guideIntentNames {
            #expect(all.contains { $0.contains("«\(name)»") }, "\(name)")
        }
        #expect(GuideNames.noticeAction == guideNoticeIntentNames[0])
        #expect(GuideNames.walletAction == guideWalletIntentNames[0])
        #expect(GuideNames.bankField == "Banco")
    }

    @Test func nombresSinVerificarFijados() {
        #expect(GuideNames.unverified == [
            "Atajos", "Automatización", "Nueva automatización", "Aplicación", "OK", "Ejecutar inmediatamente",
            "Notificar al ejecutar", "Siguiente", "Nueva automatización en blanco", "Añadir acción", "Entrada de atajo",
            "Cartera", "Notificación", "Transacción", "Título", "Subtítulo", "Cuerpo", "Importe", "Comercio",
        ])
        // Cada nombre sin verificar sale de verdad en algún texto de la guía.
        let text = GuideTrack.allCases.flatMap { guideSteps(for: $0).flatMap { [$0.title, $0.instruction, $0.help] } }
        for name in GuideNames.unverified {
            #expect(text.contains { $0.contains(name) }, "\(name)")
        }
        // Los nuestros no están entre los sin verificar: los comprueba CI contra los intents.
        for name in [GuideNames.noticeAction, GuideNames.walletAction, GuideNames.bankField] {
            #expect(!GuideNames.unverified.contains(name))
        }
    }

    // MARK: Estado

    @Test func sinAvisosEsNotYet() {
        for track in GuideTrack.allCases {
            #expect(guideStatus(track, in: LedgerState(), now: t0, calendar: utc) == .notYet)
        }
    }

    @Test func catorceDiasSinAvisosEsSilencio() {
        let state = sightingState(.revolut, first: t0 - 30 * day, last: t0)
        #expect(guideStatus(.revolut, in: state, now: t0 + 13 * day, calendar: utc) == .working(since: t0 - 30 * day, last: t0))
        #expect(guideStatus(.revolut, in: state, now: t0 + 14 * day, calendar: utc) == .silent(days: 14, last: t0))
        #expect(guideStatus(.revolut, in: state, now: t0 + 15 * day, calendar: utc) == .silent(days: 15, last: t0))
        #expect(guideStatus(.revolut, in: state, now: t0, calendar: utc) == .working(since: t0 - 30 * day, last: t0))
    }

    @Test func lasLineasDeEstado() {
        let state = sightingState(.revolut, first: t0, last: t0)
        let working = guideStatus(.revolut, in: state, now: t0 + day, calendar: utc)
        #expect(guideStatusLine(working, calendar: utc) == "Funciona · Último aviso: \(guideShortDate(t0, calendar: utc))")
        #expect(guideStatusLine(guideStatus(.revolut, in: state, now: t0 + 20 * day, calendar: utc), calendar: utc)
            == "Hace 20 días que no llega ningún aviso")
        #expect(guideStatusLine(.notYet, calendar: utc) == "Aún no ha llegado ningún aviso")
        // 1 de enero y 31 de diciembre de 2027.
        #expect(guideShortDate(Date(timeIntervalSince1970: 1_798_800_000), calendar: utc) == "1 ene")
        #expect(guideShortDate(Date(timeIntervalSince1970: 1_830_254_400), calendar: utc) == "31 dic")
    }

    @Test func descartarAvisosNoCambiaElEstado() {
        var ledger = Ledger()
        // Un aviso que no se entiende queda sin leer; al descartarlo, la guía sigue funcionando.
        #expect(ledger.ingest(.notification(bank: .tr, title: nil, subtitle: nil, body: "Paid $5.00 at Starbucks"), now: t0) == .unread)
        let before = guideStatus(.tradeRepublic, in: ledger.state, now: t0 + day, calendar: utc)
        #expect(before == .working(since: t0, last: t0))
        for notice in ledger.state.unread { ledger.removeUnread(id: notice.id) }
        #expect(ledger.state.unread.isEmpty)
        #expect(guideStatus(.tradeRepublic, in: ledger.state, now: t0 + day, calendar: utc) == before)
    }

    @Test func unPagoMarcaSoloSuBanco() {
        var ledger = Ledger()
        _ = ledger.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"), now: t0)
        #expect(guideStatus(.walletRevolut, in: ledger.state, now: t0, calendar: utc) == .working(since: t0, last: t0))
        for track in GuideTrack.allCases where track != .walletRevolut {
            #expect(guideStatus(track, in: ledger.state, now: t0, calendar: utc) == .notYet, "\(track)")
        }
        _ = ledger.ingest(.wallet(bank: .ima, amount: "3,00 €", merchant: "Kiosco"), now: t0 + 2 * day)
        #expect(guideStatus(.walletImagin, in: ledger.state, now: t0 + 2 * day, calendar: utc)
            == .working(since: t0 + 2 * day, last: t0 + 2 * day))
        #expect(guideStatus(.walletRevolut, in: ledger.state, now: t0 + 2 * day, calendar: utc)
            == .working(since: t0, last: t0))
        // Los avisos de imagin no marcan ninguna guía: imagin no avisa.
        var other = Ledger()
        _ = other.ingest(.notification(bank: .ima, title: "x", subtitle: nil, body: "y"), now: t0)
        for track in GuideTrack.allCases { #expect(guideStatus(track, in: other.state, now: t0, calendar: utc) == .notYet) }
    }

    @Test func elRegistroNoSeBorraAlEliminarElMovimiento() {
        var ledger = Ledger()
        guard case .stored(let m) = ledger.ingest(.wallet(bank: .tr, amount: "5,00 €", merchant: "Bar"), now: t0) else {
            Issue.record("no se guardó")
            return
        }
        ledger.deleteMovement(id: m.id)
        #expect(guideStatus(.walletTradeRepublic, in: ledger.state, now: t0, calendar: utc) == .working(since: t0, last: t0))
    }

    @Test func librosAnterioresSeCompletanConSusMovimientos() {
        let old = LedgerState(movements: [
            Movement(bank: .rev, amountCents: -500, merchant: "X", kind: .payment, source: .notification, date: t0),
            Movement(bank: .rev, amountCents: -500, merchant: "X", kind: .payment, source: .notification, date: t0 + day),
        ])
        #expect(guideStatus(.revolut, in: old, now: t0 + 2 * day, calendar: utc) == .working(since: t0, last: t0 + day))
        #expect(guideStatus(.walletRevolut, in: old, now: t0 + 2 * day, calendar: utc) == .notYet)
        #expect(guideStatus(.tradeRepublic, in: old, now: t0 + 2 * day, calendar: utc) == .notYet)
    }

    @Test func elRegistroSeLeeConTolerancia() throws {
        var ledger = Ledger()
        _ = ledger.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: nil), now: t0)
        let data = try JSONEncoder().encode(ledger.state)
        #expect(try JSONDecoder().decode(LedgerState.self, from: data) == ledger.state)

        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["guideSightings"] = "estropeado"
        let broken = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(LedgerState.self, from: broken).guideSightings.isEmpty)

        object.removeValue(forKey: "guideSightings")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(LedgerState.self, from: legacy)
        #expect(decoded.guideSightings.isEmpty)
        #expect(decoded.movements.count == 1)
    }
}
