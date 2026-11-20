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

private let shared1 = Row(title: "Abre Atajos", instruction: "Toca el botón de abajo: se abre la app Atajos.",
                          tap: "Abrir Atajos", help: "Si no tienes Atajos, descárgala gratis del App Store: es de Apple.")
private let shared2 = Row(title: "Ve a Automatización", instruction: "Abajo, toca «Automatización».", tap: "Automatización",
                          help: "Si ves tus atajos, toca «Atajos» arriba a la izquierda hasta llegar al principio.")
private let shared3 = Row(title: "Crea una nueva", instruction: "Toca «+» arriba a la derecha.", tap: "+",
                          help: "Si es la primera, el botón dice «Nueva automatización».")
private let shared6 = Row(title: "Que vaya sola",
                          instruction: "Marca «Ejecutar inmediatamente», apaga «Notificar al ejecutar» y toca «Siguiente».",
                          tap: "Ejecutar inmediatamente", help: "Si no lo marcas, el iPhone te preguntará cada vez.")
private let shared7 = Row(title: "Empieza en blanco", instruction: "Toca «Nueva automatización en blanco».",
                          tap: "Nueva automatización en blanco", help: "Si ves sugerencias, baja hasta el final.")
private let help8 = "Si no aparece, abre Mi Banco una vez y vuelve a Atajos."
private let help9 = "No hay que escribir nada: es una lista."
private let help11 = "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada."

private func bankSteps(_ bank: String) -> [Row] {
    [
        shared1, shared2, shared3,
        Row(title: "Busca «Notificación»", instruction: "Escribe «Notificación» en el buscador y tócala.", tap: "Notificación",
            help: "Si no aparece, mándame una captura de esa lista."),
        Row(title: "Elige \(bank)", instruction: "Toca «Aplicación», elige «\(bank)» y pulsa «OK».", tap: bank,
            help: "Si \(bank) no sale en la lista, ábrelo una vez y vuelve."),
        shared6, shared7,
        Row(title: "Añade Mi Banco", instruction: "Toca «Añadir acción», escribe «Mi Banco» y elige «Registrar aviso».",
            tap: "Registrar aviso", help: help8),
        Row(title: "Elige el banco", instruction: "Toca «Banco» y elige «\(bank)» en la lista.", tap: "Banco", help: help9),
        Row(title: "Pasa el aviso",
            instruction: "Toca «Título» y elige «Entrada de atajo». Haz lo mismo en «Subtítulo» y «Cuerpo».", tap: "Título",
            help: "Si sale «Notificación» en lugar de «Entrada de atajo», elígela: es lo mismo."),
        Row(title: "Listo", instruction: "Toca «OK» arriba a la derecha. Cuando \(bank) te avise, Mi Banco se enterará.",
            tap: "OK", help: help11),
    ]
}

private let walletSteps: [Row] = [
    shared1, shared2, shared3,
    Row(title: "Busca «Transacción»", instruction: "Escribe «Transacción» en el buscador y tócala (es la de Cartera).",
        tap: "Transacción", help: "Tiene el icono de Cartera. Si no aparece, mándame una captura."),
    Row(title: "Tus tarjetas", instruction: "Deja marcadas las tarjetas que quieras y toca «Siguiente».", tap: "Siguiente",
        help: "Puedes marcarlas todas."),
    shared6, shared7,
    Row(title: "Añade Mi Banco",
        instruction: "Toca «Añadir acción», escribe «Mi Banco» y elige «Registrar pago con Cartera».",
        tap: "Registrar pago con Cartera", help: help8),
    Row(title: "Elige el banco", instruction: "Toca «Banco» y elige el banco de esa tarjeta.", tap: "Banco", help: help9),
    Row(title: "Importe y comercio",
        instruction: "Toca «Importe» y elige «Importe»; toca «Comercio» y elige «Comercio».", tap: "Importe",
        help: "Si sale «Entrada de atajo», tócala y elige «Importe» o «Comercio»."),
    Row(title: "Listo", instruction: "Toca «OK». Cuando pagues con el iPhone, Mi Banco se enterará.", tap: "OK", help: help11),
]

private func mov(_ bank: BankID, _ source: Movement.Source, at date: Date) -> Movement {
    Movement(bank: bank, amountCents: -500, merchant: "X", kind: .payment, source: source, date: date)
}

@Suite struct SetupGuideTests {
    @Test func pasos() {
        for (track, expected) in [(GuideTrack.revolut, bankSteps("Revolut")), (.tradeRepublic, bankSteps("Trade Republic")),
                                  (.wallet, walletSteps)] {
            let got = steps(track)
            #expect(got.count == 11)
            #expect(expected.count == 11)
            for (a, b) in zip(got, expected) {
                #expect(a.title == b.title)
                #expect(a.instruction == b.instruction)
                #expect(a.tap == b.tap)
                #expect(a.help == b.help)
            }
        }
        #expect(Set(GuideTrack.allCases.flatMap { guideSteps(for: $0).map(\.id) }).count == 33)
    }

    @Test func cadaPasoUnaAccion() {
        for track in GuideTrack.allCases {
            for step in guideSteps(for: track) where step.tapTarget != "Abrir Atajos" {
                #expect(step.instruction.contains("«\(step.tapTarget)»"), "\(step.id)")
            }
        }
    }

    @Test func nombresDeLasAcciones() {
        let all = GuideTrack.allCases.flatMap { guideSteps(for: $0).map(\.instruction) }
        #expect(guideIntentNames == ["Registrar aviso", "Banco", "Título", "Subtítulo", "Cuerpo",
                                     "Registrar pago con Cartera", "Importe", "Comercio"])
        for name in guideIntentNames {
            #expect(all.contains { $0.contains(name) }, "\(name)")
        }
    }

    @Test func progreso() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let empty = LedgerState()
        for track in GuideTrack.allCases { #expect(guideStatus(track, in: empty) == .notYet) }

        let rev = LedgerState(movements: [mov(.rev, .notification, at: t.addingTimeInterval(60)), mov(.rev, .notification, at: t)])
        #expect(guideStatus(.revolut, in: rev) == .working(since: t))
        #expect(guideStatus(.tradeRepublic, in: rev) == .notYet)
        #expect(guideStatus(.wallet, in: rev) == .notYet)

        let unread = LedgerState(unread: [UnreadNotice(bank: .tr, text: "?", date: t)])
        #expect(guideStatus(.tradeRepublic, in: unread) == .working(since: t))

        let wallet = LedgerState(movements: [mov(.ima, .wallet, at: t)])
        #expect(guideStatus(.wallet, in: wallet) == .working(since: t))

        let imagin = LedgerState(movements: [mov(.ima, .notification, at: t)])
        for track in GuideTrack.allCases { #expect(guideStatus(track, in: imagin) == .notYet) }
    }
}
