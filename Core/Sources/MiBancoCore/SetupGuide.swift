import Foundation

// La guía de los avisos al instante, paso a paso. Todo lo que aparece en pantalla y que NO es nuestro
// (los nombres de Atajos) está en `GuideNames`, en un solo sitio: si iOS lo llama de otra forma, se corrige aquí.

/// Nombre de la app dentro de la guía. Una sola constante: el cambio de nombre es una línea.
public let guideAppName = "Mi Banco"

/// Nombres de las pantallas y botones de Atajos que la guía nombra.
/// SIN VERIFICAR en un iPhone con iOS 27 (salvo lo que el dueño ha visto en su móvil: «Atajos», «Notificación»,
/// «Transacción»): `shortcutsApp`, `automationTab`, `newAutomation`, `appField`, `runImmediately`, `notifyWhenRun`,
/// `next`, `blankAutomation`, `addAction`, `shortcutInput`, `walletApp`, `ok`.
public enum GuideNames {
    public static let shortcutsApp = "Atajos"
    public static let automationTab = "Automatización"
    public static let plus = "+"
    public static let newAutomation = "Nueva automatización"
    public static let notificationTrigger = "Notificación"
    /// En iOS el disparador de Apple Pay aparece como «Transacción» (es el de Cartera).
    public static let transactionTrigger = "Transacción"
    public static let walletApp = "Cartera"
    public static let appField = "Aplicación"
    public static let ok = "OK"
    public static let runImmediately = "Ejecutar inmediatamente"
    public static let notifyWhenRun = "Notificar al ejecutar"
    public static let next = "Siguiente"
    public static let blankAutomation = "Nueva automatización en blanco"
    public static let addAction = "Añadir acción"
    public static let shortcutInput = "Entrada de atajo"
    /// Los de nuestras acciones se comprueban en CI contra los intents (`guideIntentNames`).
    public static let noticeAction = "Registrar aviso"
    public static let walletAction = "Registrar pago con Cartera"
    public static let bankField = "Banco"
    public static let titleField = "Título"
    public static let subtitleField = "Subtítulo"
    public static let bodyField = "Cuerpo"
    public static let amountField = "Importe"
    public static let merchantField = "Comercio"

    /// Los que no se han visto en un iPhone con iOS 27 (para el informe y para revisarlos con el móvil en la mano).
    public static let unverified: [String] = [
        shortcutsApp, automationTab, newAutomation, appField, ok, runImmediately, notifyWhenRun, next,
        blankAutomation, addAction, shortcutInput, walletApp,
    ]
}

/// Los nombres de nuestras acciones y parámetros: CI comprueba que los intents los usan tal cual.
public let guideIntentNames: [String] = [
    "Registrar aviso", "Banco", "Título", "Subtítulo", "Cuerpo", "Registrar pago con Cartera", "Importe", "Comercio",
]

public enum GuideTrack: String, CaseIterable, Sendable {
    case revolut, tradeRepublic, wallet

    public var title: String {
        switch self {
        case .revolut: "Revolut"
        case .tradeRepublic: "Trade Republic"
        case .wallet: "Pagos con Apple Pay (\(GuideNames.transactionTrigger))"
        }
    }

    /// Nombre del banco de los avisos; nil para Apple Pay (el banco se elige al configurar).
    public var bankName: String? {
        switch self {
        case .revolut: "Revolut"
        case .tradeRepublic: "Trade Republic"
        case .wallet: nil
        }
    }
}

public enum GuideIllustration: String, Sendable {
    case openShortcuts, automationTab, plusButton, triggerSearch, appPicker, runImmediately, blankAutomation
    case addAction, bankPicker, variablePicker, done
}

public struct GuideStep: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let instruction: String
    /// Lo que hay que tocar en la pantalla de Atajos (lo que se resalta en el dibujo).
    public let tapTarget: String
    public let illustration: GuideIllustration
    /// La línea de «¿No te sale esto?».
    public let help: String

    public init(id: String, title: String, instruction: String, tapTarget: String, illustration: GuideIllustration, help: String) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.tapTarget = tapTarget
        self.illustration = illustration
        self.help = help
    }
}

private typealias N = GuideNames

public func guideSteps(for track: GuideTrack) -> [GuideStep] {
    func step(_ n: Int, _ title: String, _ instruction: String, _ tap: String, _ picture: GuideIllustration,
              _ help: String) -> GuideStep {
        GuideStep(id: "\(track.rawValue)-\(n)", title: title, instruction: instruction, tapTarget: tap,
                  illustration: picture, help: help)
    }

    // Pasos iguales en las tres guías.
    let open = step(1, "Abre \(N.shortcutsApp)", "Toca el botón de abajo: se abre la app \(N.shortcutsApp).", "Abrir \(N.shortcutsApp)",
                    .openShortcuts, "Si no tienes \(N.shortcutsApp), descárgala gratis del App Store: es de Apple.")
    let tab = step(2, "Ve a \(N.automationTab)", "Abajo, toca «\(N.automationTab)».", N.automationTab, .automationTab,
                   "Si ves tus atajos, toca «\(N.shortcutsApp)» arriba a la izquierda hasta llegar al principio.")
    let plus = step(3, "Crea una nueva", "Toca «\(N.plus)» arriba a la derecha.", N.plus, .plusButton,
                    "Si es la primera, el botón dice «\(N.newAutomation)».")
    let immediately = step(6, "Que vaya sola",
                           "Marca «\(N.runImmediately)», apaga «\(N.notifyWhenRun)» y toca «\(N.next)».", N.runImmediately,
                           .runImmediately, "Si no lo marcas, el iPhone te preguntará cada vez.")
    let blank = step(7, "Empieza en blanco", "Toca «\(N.blankAutomation)».", N.blankAutomation, .blankAutomation,
                     "Si ves sugerencias, baja hasta el final.")
    let addHelp = "Si no aparece, abre \(guideAppName) una vez y vuelve a \(N.shortcutsApp)."
    let finishHelp = "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada."

    switch track {
    case .revolut, .tradeRepublic:
        let bank = track.bankName ?? ""
        return [
            open, tab, plus,
            step(4, "Busca «\(N.notificationTrigger)»", "Escribe «\(N.notificationTrigger)» en el buscador y tócala.",
                 N.notificationTrigger, .triggerSearch, "Si no aparece, mándame una captura de esa lista."),
            step(5, "Elige \(bank)", "Toca «\(N.appField)», elige «\(bank)» y pulsa «\(N.ok)».", bank, .appPicker,
                 "Si \(bank) no sale en la lista, ábrelo una vez y vuelve."),
            immediately, blank,
            step(8, "Añade \(guideAppName)",
                 "Toca «\(N.addAction)», escribe «\(guideAppName)» y elige «\(N.noticeAction)».", N.noticeAction, .addAction, addHelp),
            step(9, "Elige el banco", "Toca «\(N.bankField)» y elige «\(bank)» en la lista.", N.bankField, .bankPicker,
                 "No hay que escribir nada: es una lista."),
            step(10, "Pasa el aviso",
                 "Toca «\(N.titleField)» y elige «\(N.shortcutInput)». Haz lo mismo en «\(N.subtitleField)» y «\(N.bodyField)».",
                 N.titleField, .variablePicker,
                 "Si sale «\(N.notificationTrigger)» en lugar de «\(N.shortcutInput)», elígela: es lo mismo."),
            step(11, "Listo", "Toca «\(N.ok)» arriba a la derecha. Cuando \(bank) te avise, \(guideAppName) se enterará.",
                 N.ok, .done, finishHelp),
        ]
    case .wallet:
        return [
            open, tab, plus,
            step(4, "Busca «\(N.transactionTrigger)»",
                 "Escribe «\(N.transactionTrigger)» en el buscador y tócala (es la de \(N.walletApp)).", N.transactionTrigger,
                 .triggerSearch, "Tiene el icono de \(N.walletApp). Si no aparece, mándame una captura."),
            step(5, "Tus tarjetas", "Deja marcadas las tarjetas que quieras y toca «\(N.next)».", N.next, .appPicker,
                 "Puedes marcarlas todas."),
            immediately, blank,
            step(8, "Añade \(guideAppName)",
                 "Toca «\(N.addAction)», escribe «\(guideAppName)» y elige «\(N.walletAction)».", N.walletAction, .addAction, addHelp),
            step(9, "Elige el banco", "Toca «\(N.bankField)» y elige el banco de esa tarjeta.", N.bankField, .bankPicker,
                 "No hay que escribir nada: es una lista."),
            step(10, "Importe y comercio",
                 "Toca «\(N.amountField)» y elige «\(N.amountField)»; toca «\(N.merchantField)» y elige «\(N.merchantField)».",
                 N.amountField, .variablePicker,
                 "Si sale «\(N.shortcutInput)», tócala y elige «\(N.amountField)» o «\(N.merchantField)»."),
            step(11, "Listo", "Toca «\(N.ok)». Cuando pagues con el iPhone, \(guideAppName) se enterará.", N.ok, .done, finishHelp),
        ]
    }
}

public enum GuideStatus: Equatable, Sendable {
    case notYet
    case working(since: Date)
}

/// Funciona cuando ya ha llegado un aviso real: movimiento (o aviso sin leer) de ese banco, o un pago de Cartera.
/// `since` es el primero que llegó.
public func guideStatus(_ track: GuideTrack, in state: LedgerState) -> GuideStatus {
    let dates: [Date]
    switch track {
    case .revolut, .tradeRepublic:
        let bank: BankID = track == .revolut ? .rev : .tr
        dates = state.movements.filter { $0.bank == bank && $0.source == .notification }.map(\.date)
            + state.unread.filter { $0.bank == bank }.map(\.date)
    case .wallet:
        dates = state.movements.filter { $0.source == .wallet }.map(\.date)
    }
    guard let first = dates.min() else { return .notYet }
    return .working(since: first)
}
