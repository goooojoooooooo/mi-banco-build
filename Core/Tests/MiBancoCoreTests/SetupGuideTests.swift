import Foundation
import Testing
@testable import MiBancoCore

private struct Row {
    let title: String
    let instruction: String
    let tap: String
    let help: String
    let part: Int
}

private func steps(_ track: GuideTrack) -> [Row] {
    guideSteps(for: track).map { Row(title: $0.title, instruction: $0.instruction, tap: $0.tapTarget, help: $0.help, part: $0.part) }
}

private let tail = "Si tu pantalla se ve distinta, toca la opción con el nombre más parecido. Si no hay ninguna, para aquí: lo que llevas hecho no estropea nada."

private func row(_ part: Int, _ title: String, _ instruction: String, _ tap: String, _ help: String) -> Row {
    Row(title: title, instruction: instruction, tap: tap, help: "\(help) \(tail)", part: part)
}

private let help8 = "Si no aparece, abre Mi Banco una vez y vuelve a Atajos."
private let list = "No hay que escribir nada: es una lista."
private let atBottom = "Está abajo, en el centro de la pantalla."

private func openRows(trigger: String, triggerHelp: String, triggerLine: String) -> [Row] {
    [
        row(1, "Abre Atajos", "Toca el botón de abajo: se abre la app Atajos.", "Abrir Atajos",
            "Si no tienes Atajos, descárgala gratis del App Store: es de Apple."),
        row(1, "Ve a Automatización", "Abajo, toca «Automatización».", "Automatización",
            "Si ves tus atajos, toca «Atajos» arriba a la izquierda hasta llegar al principio."),
        row(1, "Crea una nueva", "Toca «+» arriba a la derecha.", "+", "Si es la primera, el botón dice «Nueva automatización»."),
        row(1, "Busca «\(trigger)»", "Escribe «\(trigger)» en el buscador.", trigger,
            "El buscador está arriba, con una lupa. Escribe solo esa palabra."),
        row(1, "Elige «\(trigger)»", triggerLine, trigger, triggerHelp),
    ]
}

private let runRows: [Row] = [
    row(2, "Que vaya sola", "Marca «Ejecutar inmediatamente».", "Ejecutar inmediatamente",
        "Si no lo marcas, el iPhone te preguntará cada vez."),
    row(2, "Sin avisos de Atajos", "Apaga «Notificar al ejecutar»: el interruptor debe quedar gris. Si ya está gris, no lo toques.",
        "Notificar al ejecutar", "Así Atajos no te enseña un aviso cada vez que funciona."),
    row(2, "Sigue", "Toca «Siguiente».", "Siguiente", atBottom),
]

private func actionRows(_ action: String) -> [Row] {
    [
        row(3, "Empieza en blanco", "Toca «Nueva automatización en blanco».", "Nueva automatización en blanco",
            "Si ves sugerencias, baja hasta el final."),
        row(3, "Añade una acción", "Toca «Añadir acción».", "Añadir acción", "Es el botón con un más, en el centro."),
        row(3, "Busca Mi Banco", "Toca el buscador de arriba.", "Buscar", "La lupa está arriba, debajo del título."),
        row(3, "Escribe Mi Banco", "Escribe «Mi Banco» en el buscador.", "Mi Banco", help8),
        row(3, "Elige la acción", "Toca «\(action)».", action, help8),
        row(4, "Elige el banco", "Toca «Banco».", "Banco", list),
    ]
}

private func fieldRow(_ name: String, _ chip: String, intro: String?) -> Row {
    row(4, "Rellena «\(name)»",
        "\(intro.map { $0 + " " } ?? "")Toca «\(name)». Abajo verás una ficha llamada «\(chip)»: tócala y luego elige «\(name)».", chip,
        "Si solo ves «Entrada de atajo», tócala y busca «\(name)» dentro.")
}

private func bankSteps(_ bank: String) -> [Row] {
    openRows(trigger: "Notificación", triggerHelp: "Si no aparece, comprueba que has escrito «Notificación» sin errores.",
             triggerLine: "Toca «Notificación» en la lista.")
        + [
            row(1, "Elige la app", "Toca «Aplicación».", "Aplicación", "Si no la ves, baja un poco con el dedo."),
            row(1, "Elige \(bank)", "Toca «\(bank)» en la lista.", bank, "Si \(bank) no sale en la lista, ábrelo una vez y vuelve."),
            row(1, "Confirma", "Toca «OK» arriba a la derecha.", "OK", "Está arriba a la derecha, junto al título."),
        ]
        + runRows + actionRows("Registrar aviso")
        + [
            row(4, "Elige \(bank)", "Toca «\(bank)» en la lista.", bank, list),
            fieldRow("Título", "Notificación", intro: "Es elegir de qué parte del aviso sale cada dato."),
            fieldRow("Subtítulo", "Notificación", intro: nil),
            fieldRow("Cuerpo", "Notificación", intro: nil),
            row(4, "Listo", "Toca «OK» arriba a la derecha. Cuando \(bank) te avise, Mi Banco se enterará.", "OK",
                "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada."),
        ]
}

private func applePaySteps(_ bank: String, bankLine: String) -> [Row] {
    openRows(trigger: "Transacción", triggerHelp: "Tiene el icono de Cartera.",
             triggerLine: "Toca «Transacción» en la lista (es la de Cartera).")
        + [
            row(1, "Tu tarjeta de \(bank)", "Marca la tarjeta de «\(bank)».", bank,
                "La reconocerás por el nombre o por los últimos números. Si tienes dos tarjetas de «\(bank)», marca las dos. Si alguna otra aparece marcada, tócala para quitarle la marca. Si no tienes tarjeta de «\(bank)» en Cartera, sáltate esta guía."),
            row(1, "Sigue", "Toca «Siguiente».", "Siguiente", atBottom),
        ]
        + runRows + actionRows("Registrar pago con Cartera")
        + [
            row(4, "Elige \(bank)", bankLine, bank, list),
            fieldRow("Importe", "Transacción", intro: "Es elegir de qué parte del pago sale cada dato."),
            fieldRow("Comercio", "Transacción", intro: nil),
            row(4, "Listo",
                "Toca «OK» arriba a la derecha. Cuando pagues con la tarjeta de \(bank), Mi Banco se enterará.", "OK",
                "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada. Para otro banco, repite su guía de Apple Pay."),
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

/// Cuántos verbos de «hacer algo en la pantalla» tiene un texto (cada verbo cuenta cada vez que sale).
private func tapVerbs(_ text: String) -> Int {
    let verbs: Set<String> = ["toca", "marca", "escribe", "elige", "activa", "desactiva", "apaga"]
    let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    return words.filter { verbs.contains($0) }.count
}

private func sightingState(_ track: GuideTrack, first: Date, last: Date) -> LedgerState {
    LedgerState(guideSightings: [track.rawValue: GuideSighting(first: first, last: last)])
}

private let day: TimeInterval = 86_400
/// Un mediodía UTC, para que contar días no dependa de la hora.
private let t0 = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: day) + day / 2)

@Suite struct SetupGuideTests {
    private func compare(_ got: [Row], _ expected: [Row]) {
        #expect(got.count == expected.count)
        for (a, b) in zip(got, expected) {
            #expect(a.title == b.title)
            #expect(a.instruction == b.instruction)
            #expect(a.tap == b.tap)
            #expect(a.help == b.help)
            #expect(a.part == b.part)
        }
    }

    @Test func pasosDeLasGuiasDeAvisos() {
        for (track, bank) in [(GuideTrack.revolut, "Revolut"), (.tradeRepublic, "Trade Republic")] {
            #expect(steps(track).count == 22)
            compare(steps(track), bankSteps(bank))
        }
    }

    @Test func pasosDeApplePayUnoPorBanco() {
        #expect(GuideTrack.allCases.filter(\.isApplePay).count == 3)
        for (track, expected) in applePayExpected {
            #expect(steps(track).count == 20)
            compare(steps(track), expected)
        }
        #expect(Set(GuideTrack.allCases.flatMap { guideSteps(for: $0).map(\.id) }).count == 22 * 2 + 20 * 3)
    }

    @Test func applePayMarcaLaTarjetaDeSuBanco() {
        for track in GuideTrack.allCases where track.isApplePay {
            let cards = guideSteps(for: track)[5]
            #expect(cards.instruction == "Marca la tarjeta de «\(track.bankName)».")
            #expect(cards.help.contains("Si alguna otra aparece marcada, tócala para quitarle la marca."))
            #expect(!cards.instruction.contains("todas") && !cards.help.contains("todas"))
            #expect(cards.illustration == .walletCards)
            // El paso del banco nombra el banco; el de imagin repite que solo funciona por Apple Pay.
            let pick = guideSteps(for: track)[16]
            #expect(pick.instruction.contains("«\(track.bankName)»"))
            #expect(pick.instruction.contains("Apple Pay") == (track == .walletImagin))
        }
        #expect(GuideTrack.walletImagin.title == "Apple Pay de imagin")
    }

    @Test func cadaPasoUnaSolaAccion() {
        let forbidden = ["y después", "y tócala", "Quita la marca"]
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) where step.tapTarget != "Abrir Atajos" {
                let marks = quoted(step.instruction)
                if step.illustration == .variablePicker {
                    // Los campos: «Título» … ficha «Notificación» … «Título», con ese texto y no otro.
                    #expect(marks == [step.focus, step.tapTarget, step.focus], "\(step.id): \(step.instruction)")
                    continue
                }
                if step.gesture == .search {
                    #expect(marks.isEmpty, "\(step.id)")
                } else {
                    #expect(marks == [step.tapTarget], "\(step.id): \(step.instruction)")
                }
                #expect(tapVerbs(step.instruction) <= 1, "\(step.id): \(step.instruction)")
                for text in forbidden { #expect(!step.instruction.contains(text), "\(step.id): \(step.instruction)") }
            }
        }
        // Los detectores funcionan.
        #expect(Set(quoted("Toca «A» y elige «B».")).count == 2)
        #expect(tapVerbs("Toca «A» y elige «B».") == 2)
        #expect(tapVerbs("Abajo, toca «Automatización».") == 1)
        #expect(tapVerbs("No lo toques.") == 0)
    }

    @Test func cadaCampoSeRellenaEnSuPaso() {
        for track in GuideTrack.allCases {
            let fields = track.isApplePay ? ["Importe", "Comercio"] : ["Título", "Subtítulo", "Cuerpo"]
            let chip = track.isApplePay ? "Transacción" : "Notificación"
            for (n, name) in fields.enumerated() {
                let step = guideSteps(for: track).first { $0.focus == name }
                #expect(step != nil, "\(track) \(name)")
                guard let step else { continue }
                #expect(step.tapTarget == chip)
                #expect(step.instruction.contains("Toca «\(name)». Abajo verás una ficha llamada «\(chip)»: tócala y luego elige «\(name)»."))
                // Solo el primer campo explica de qué va.
                #expect(step.instruction.hasPrefix("Es elegir de qué parte del") == (n == 0))
                #expect(step.help.hasPrefix("Si solo ves «Entrada de atajo», tócala y busca «\(name)» dentro."))
            }
        }
    }

    @Test func lenguajeSencilloYAyudaCompleta() {
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) {
                for text in [step.title, step.instruction, step.help] {
                    for banned in ["variable", "propiedad", "mándame", "captura", "avísame", "desarrollador"] {
                        #expect(!text.lowercased().contains(banned), "\(step.id): \(text)")
                    }
                }
                // Toda ayuda termina con la misma línea.
                #expect(step.help.hasSuffix(guideHelpTail), "\(step.id)")
                #expect(!step.place.isEmpty)
            }
        }
        #expect(guideHelpTail == tail)
    }

    @Test func cuatroPartesConNombre() {
        #expect(guideParts == ["Crear la automatización", "Que funcione sola", "Añadir la acción", "Rellenar los datos"])
        for track in GuideTrack.allCases {
            let all = guideSteps(for: track)
            #expect(all.map(\.part) == all.map(\.part).sorted())
            #expect(Set(all.map(\.part)) == [1, 2, 3, 4])
        }
        let revolut = guideSteps(for: .revolut)
        #expect(guideProgressLabel(revolut[8], number: 9, total: revolut.count) == "Parte 2 de 4 · Paso 9 de 22")
        #expect(guideProgressLabel(revolut[0], number: 1, total: 22) == "Parte 1 de 4 · Paso 1 de 22")
    }

    @Test func retomarDondeSeDejo() {
        #expect(guideResumeIndex(saved: nil, total: 22) == nil)
        #expect(guideResumeIndex(saved: 0, total: 22) == nil)
        #expect(guideResumeIndex(saved: -3, total: 22) == nil)
        #expect(guideResumeIndex(saved: 8, total: 22) == 8)
        #expect(guideResumeIndex(saved: 21, total: 22) == 21)
        // Si la guía se acortó, no se sale de rango.
        #expect(guideResumeIndex(saved: 99, total: 22) == 21)
        #expect(guideResumeLine(index: 8, total: 22) == "Vas por el paso 9 de 22")
    }

    @Test func queGuiaHacer() {
        #expect(guideListAdvice == [
            "Revolut y Trade Republic: haz la guía de avisos. La de Apple Pay es opcional, por si un aviso no llega.",
            "imagin: solo funciona con la guía de Apple Pay.",
        ])
        #expect(GuideTrack.allCases.filter(\.isOptional) == [.walletRevolut, .walletTradeRepublic])
    }

    @Test func labelDelDibujo() {
        let revolut = guideSteps(for: .revolut)
        #expect(revolut[1].spokenLabel == "Dibujo de la pantalla. Toca «Automatización», abajo, en el centro.")
        #expect(revolut[3].spokenLabel == "Dibujo de la pantalla. Escribe «Notificación» en el buscador, arriba.")
        #expect(revolut[13].spokenLabel == "Dibujo de la pantalla. Toca el buscador, arriba.")
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
            "Automatización", "Nueva automatización", "Aplicación", "OK", "Ejecutar inmediatamente",
            "Notificar al ejecutar", "Siguiente", "Nueva automatización en blanco", "Añadir acción", "Entrada de atajo",
            "Cartera", "Título", "Subtítulo", "Cuerpo", "Importe", "Comercio",
        ])
        // Lo que el dueño ya vio en su móvil no está en la lista.
        for confirmed in [GuideNames.shortcutsApp, GuideNames.notificationTrigger, GuideNames.transactionTrigger] {
            #expect(!GuideNames.unverified.contains(confirmed))
        }
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

    @Test func elMismoPagoPorAvisoYPorCarteraEsUnMovimiento() {
        // El aviso del banco y la transacción de Cartera del mismo pago acaban en UN movimiento (ver también
        // LedgerTests: duplicadoDeWalletYAvisoDentroDeLaVentana, carteraYAvisoA90sSonUnMovimiento).
        var ledger = Ledger()
        _ = ledger.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Paid €12.50 at Mercadona"), now: t0)
        #expect(ledger.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"), now: t0 + 30) == .duplicate)
        #expect(ledger.state.movements.count == 1)
        var reverse = Ledger()
        _ = reverse.ingest(.wallet(bank: .rev, amount: "12,50 €", merchant: "Mercadona"), now: t0)
        #expect(reverse.ingest(.notification(bank: .rev, title: nil, subtitle: nil, body: "Paid €12.50 at Mercadona"),
                               now: t0 + 30) == .duplicate)
        #expect(reverse.state.movements.count == 1)
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
            == "Hace 20 días que no llega ningún aviso. Si has pagado con este banco desde entonces, repasa la guía.")
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
