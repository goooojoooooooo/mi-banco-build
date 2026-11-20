import Foundation

// La guía de los avisos al instante, paso a paso. Todo lo que aparece en pantalla y que NO es nuestro
// (los nombres de Atajos) está en `GuideNames`, en un solo sitio: si iOS lo llama de otra forma, se corrige aquí.

/// Nombre de la app dentro de la guía. Una sola constante: el cambio de nombre es una línea.
public let guideAppName = "Mi Banco"

/// Nombres de las pantallas y botones de Atajos que la guía nombra.
/// SIN VERIFICAR en un iPhone con iOS 27 (salvo lo que el dueño ha visto en su móvil: «Atajos», «Notificación»
/// y «Transacción» como disparadores): ver `unverified`.
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
    /// Los de nuestras acciones se comprueban en CI contra los intents (`guideNoticeIntentNames`, `guideWalletIntentNames`).
    public static let noticeAction = "Registrar aviso"
    public static let walletAction = "Registrar pago con Cartera"
    public static let bankField = "Banco"
    public static let titleField = "Título"
    public static let subtitleField = "Subtítulo"
    public static let bodyField = "Cuerpo"
    public static let amountField = "Importe"
    public static let merchantField = "Comercio"
    /// De dónde sale cada dato al rellenar un campo: la variable del disparador y su propiedad (SIN VERIFICAR en iOS 27).
    public static let notificationVariable = "Notificación"
    public static let transactionVariable = "Transacción"
    public static let propertyTitle = "Título"
    public static let propertySubtitle = "Subtítulo"
    public static let propertyBody = "Cuerpo"
    public static let propertyAmount = "Importe"
    public static let propertyMerchant = "Comercio"

    /// Los que no se han visto en un iPhone con iOS 27 (para el informe y para revisarlos con el móvil en la mano).
    public static let unverified: [String] = [
        shortcutsApp, automationTab, newAutomation, appField, ok, runImmediately, notifyWhenRun, next,
        blankAutomation, addAction, shortcutInput, walletApp,
        notificationVariable, transactionVariable, propertyTitle, propertySubtitle, propertyBody, propertyAmount,
        propertyMerchant,
    ]
}

// Los nombres de nuestras acciones y parámetros: CI comprueba que los intents los usan tal cual
// (`@Parameter(title: "…")` y el título de la acción). El primero de cada lista es la acción; el resto, sus parámetros.
// Una cadena por línea y el `]` en la primera columna: el script de CI lee estas listas tal cual.
public let guideNoticeIntentNames: [String] = [
    "Registrar aviso",
    "Banco",
    "Título",
    "Subtítulo",
    "Cuerpo",
]

public let guideWalletIntentNames: [String] = [
    "Registrar pago con Cartera",
    "Banco",
    "Importe",
    "Comercio",
]

/// Todos los nombres sin repetir, en el orden en que aparecen.
public let guideIntentNames: [String] = {
    var seen = Set<String>()
    return (guideNoticeIntentNames + guideWalletIntentNames).filter { seen.insert($0).inserted }
}()

public enum GuideTrack: String, CaseIterable, Sendable {
    case revolut, tradeRepublic, walletImagin, walletRevolut, walletTradeRepublic

    /// Una guía de Apple Pay por banco: cada automatización registra los pagos de un solo banco.
    public static func applePay(for bank: BankID) -> GuideTrack {
        switch bank {
        case .rev: .walletRevolut
        case .ima: .walletImagin
        case .tr: .walletTradeRepublic
        }
    }

    public var isApplePay: Bool {
        switch self {
        case .revolut, .tradeRepublic: false
        case .walletImagin, .walletRevolut, .walletTradeRepublic: true
        }
    }

    public var bank: BankID {
        switch self {
        case .revolut, .walletRevolut: .rev
        case .tradeRepublic, .walletTradeRepublic: .tr
        case .walletImagin: .ima
        }
    }

    public var bankName: String { bank.displayName }

    public var title: String {
        isApplePay ? "Apple Pay de \(bankName)" : bankName
    }
}

public enum GuideIllustration: String, Sendable {
    case openShortcuts, automationTab, plusButton, triggerSearch
    case appField, appPicker, appOK
    case walletCards, walletNext
    case runImmediately, notifyOff, runNext
    case blankAutomation
    case addActionButton, addActionSearch, addAction
    case bankPicker, bankChoice, variablePicker, done
}

public struct GuideStep: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let instruction: String
    /// Lo que hay que tocar en la pantalla de Atajos (lo que se resalta en el dibujo).
    public let tapTarget: String
    /// Dónde está en la pantalla («arriba a la derecha»): lo lee VoiceOver con el dibujo.
    public let place: String
    public let illustration: GuideIllustration
    /// La línea de «¿No te sale esto?».
    public let help: String

    public init(id: String, title: String, instruction: String, tapTarget: String, place: String,
                illustration: GuideIllustration, help: String) {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.tapTarget = tapTarget
        self.place = place
        self.illustration = illustration
        self.help = help
    }
}

private typealias N = GuideNames

/// Una sola acción por pantalla: cada instrucción nombra, entre «», lo único que se toca (sin repetirse).
public func guideSteps(for track: GuideTrack) -> [GuideStep] {
    var out: [GuideStep] = []
    func add(_ title: String, _ instruction: String, _ tap: String, _ place: String, _ picture: GuideIllustration,
             _ help: String) {
        out.append(GuideStep(id: "\(track.rawValue)-\(out.count + 1)", title: title, instruction: instruction,
                             tapTarget: tap, place: place, illustration: picture, help: help))
    }

    let bank = track.bankName
    let retry = "Si no te sale, vuelve un paso atrás y repítelo."

    // Hasta elegir el disparador, igual en todas las guías.
    add("Abre \(N.shortcutsApp)", "Toca el botón de abajo: se abre la app \(N.shortcutsApp).", "Abrir \(N.shortcutsApp)",
        "abajo, en esta pantalla", .openShortcuts,
        "Si no tienes \(N.shortcutsApp), descárgala gratis del App Store: es de Apple.")
    add("Ve a \(N.automationTab)", "Abajo, toca «\(N.automationTab)».", N.automationTab, "abajo, en el centro",
        .automationTab, "Si ves tus atajos, toca «\(N.shortcutsApp)» arriba a la izquierda hasta llegar al principio.")
    add("Crea una nueva", "Toca «\(N.plus)» arriba a la derecha.", N.plus, "arriba a la derecha", .plusButton,
        "Si es la primera, el botón dice «\(N.newAutomation)».")

    if track.isApplePay {
        add("Busca «\(N.transactionTrigger)»",
            "Escribe «\(N.transactionTrigger)» en el buscador y tócala (es la de \(N.walletApp)).", N.transactionTrigger,
            "en la lista de resultados", .triggerSearch, "Tiene el icono de \(N.walletApp). \(retry)")
        add("Tus tarjetas de \(bank)", "Marca solo las tarjetas de «\(bank)». Quita la marca a las demás.", bank,
            "en la lista de tarjetas", .walletCards,
            "Cada banco tiene su propia automatización: así \(guideAppName) sabe de cuál es cada pago.")
        add("Sigue", "Toca «\(N.next)».", N.next, "abajo", .walletNext, retry)
    } else {
        add("Busca «\(N.notificationTrigger)»", "Escribe «\(N.notificationTrigger)» en el buscador y tócala.",
            N.notificationTrigger, "en la lista de resultados", .triggerSearch, retry)
        add("Elige la app", "Toca «\(N.appField)».", N.appField, "en el centro de la pantalla", .appField,
            "Si no la ves, baja un poco con el dedo.")
        add("Elige \(bank)", "Toca «\(bank)» en la lista.", bank, "en la lista", .appPicker,
            "Si \(bank) no sale en la lista, ábrelo una vez y vuelve.")
        add("Confirma", "Toca «\(N.ok)» arriba a la derecha.", N.ok, "arriba a la derecha", .appOK, retry)
    }

    add("Que vaya sola", "Marca «\(N.runImmediately)».", N.runImmediately, "en el centro de la pantalla",
        .runImmediately, "Si no lo marcas, el iPhone te preguntará cada vez.")
    add("Sin avisos de \(N.shortcutsApp)", "Apaga «\(N.notifyWhenRun)»: el interruptor debe quedar gris.", N.notifyWhenRun, "en el centro de la pantalla",
        .notifyOff, "Así \(N.shortcutsApp) no te enseña un aviso cada vez que funciona. El interruptor debe quedar apagado.")
    add("Sigue", "Toca «\(N.next)».", N.next, "abajo", .runNext, retry)
    add("Empieza en blanco", "Toca «\(N.blankAutomation)».", N.blankAutomation, "en el centro de la pantalla",
        .blankAutomation, "Si ves sugerencias, baja hasta el final.")

    let action = track.isApplePay ? N.walletAction : N.noticeAction
    let addHelp = "Si no aparece, abre \(guideAppName) una vez y vuelve a \(N.shortcutsApp)."
    add("Añade una acción", "Toca «\(N.addAction)».", N.addAction, "en el centro de la pantalla", .addActionButton, retry)
    add("Busca \(guideAppName)", "Toca el buscador y escribe «\(guideAppName)».", guideAppName, "arriba",
        .addActionSearch, addHelp)
    add("Elige la acción", "Toca «\(action)».", action, "en la lista de resultados", .addAction, addHelp)

    add("Elige el banco", "Toca «\(N.bankField)».", N.bankField, "en la tarjeta de la acción", .bankPicker,
        "No hay que escribir nada: es una lista.")
    if track == .walletImagin {
        add("Elige \(bank)",
            "Toca «\(bank)» en la lista. Recuerda: \(bank) solo avisa de sus pagos a través de Apple Pay.", bank,
            "en la lista", .bankChoice, "No hay que escribir nada: es una lista.")
    } else if track.isApplePay {
        add("Elige \(bank)", "Toca «\(bank)» en la lista: esta automatización es solo de sus tarjetas.", bank,
            "en la lista", .bankChoice, "No hay que escribir nada: es una lista.")
    } else {
        add("Elige \(bank)", "Toca «\(bank)» en la lista.", bank, "en la lista", .bankChoice,
            "No hay que escribir nada: es una lista.")
    }

    // Cada campo se rellena con el dato que le corresponde. Los nombres de la lista son SIN VERIFICAR en iOS 27.
    func field(_ name: String, _ source: String) {
        add("Rellena «\(name)»",
            "Toca «\(name)». En la lista de abajo, elige \(source) y después su propiedad \(name).", name,
            "en la tarjeta de la acción", .variablePicker,
            "Si solo te sale una variable (por ejemplo «\(N.shortcutInput)»), tócala y busca dentro «\(name)». \(retry)")
    }
    if track.isApplePay {
        field(N.amountField, "la transacción")
        field(N.merchantField, "la transacción")
        add("Listo",
            "Toca «\(N.ok)» arriba a la derecha. Cuando pagues con la tarjeta de \(bank), \(guideAppName) se enterará.",
            N.ok, "arriba a la derecha", .done,
            "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada. Para otro banco, repite su guía de Apple Pay.")
    } else {
        field(N.titleField, "la notificación")
        field(N.subtitleField, "la notificación")
        field(N.bodyField, "la notificación")
        add("Listo", "Toca «\(N.ok)» arriba a la derecha. Cuando \(bank) te avise, \(guideAppName) se enterará.", N.ok,
            "arriba a la derecha", .done,
            "Si algo no cuadra, borra la automatización y empieza otra vez: no pasa nada.")
    }
    return out
}

// MARK: Estado de cada guía

/// Cuándo se vio el primer y el último aviso de una guía. Se guarda en el libro (no se deduce de los avisos sin leer,
/// que se vacían al descartarlos).
public struct GuideSighting: Codable, Equatable, Sendable {
    public var first: Date
    public var last: Date

    public init(first: Date, last: Date) {
        self.first = first
        self.last = last
    }
}

extension GuideTrack {
    /// La guía a la que pertenece una entrada: el aviso de Revolut o de Trade Republic, o el pago de Apple Pay de ese
    /// banco. Los avisos de imagin no tienen guía (no avisa).
    static func forInput(_ input: IngestInput) -> GuideTrack? {
        switch input {
        case .notification(let bank, _, _, _):
            switch bank {
            case .rev: .revolut
            case .tr: .tradeRepublic
            case .ima: nil
            }
        case .wallet(let bank, _, _):
            .applePay(for: bank)
        }
    }
}

extension LedgerState {
    /// Apunta que ha llegado algo por esa guía (también si era un duplicado o no se pudo leer: lo que importa es que
    /// el atajo funciona). Solo marca su guía: un pago de un banco no marca a otro.
    mutating func recordGuideSighting(for input: IngestInput, now: Date) {
        guard let track = GuideTrack.forInput(input) else { return }
        if var sighting = guideSightings[track.rawValue] {
            sighting.first = min(sighting.first, now)
            sighting.last = max(sighting.last, now)
            guideSightings[track.rawValue] = sighting
        } else {
            guideSightings[track.rawValue] = GuideSighting(first: now, last: now)
        }
    }
}

/// Días sin ningún aviso a partir de los cuales la guía deja de decir «Funciona».
public let guideSilentAfterDays = 14

public enum GuideStatus: Equatable, Sendable {
    /// Todavía no ha llegado nada.
    case notYet
    case working(since: Date, last: Date)
    /// Llegó algo, pero hace `days` días o más que no llega nada.
    case silent(days: Int, last: Date)
}

/// «Funciona» sale del registro guardado de cada guía (primer y último aviso), que no se borra al descartar avisos.
/// Los libros anteriores al registro se completan con sus movimientos. Con `guideSilentAfterDays` días o más sin
/// avisos, pasa a `silent`.
public func guideStatus(_ track: GuideTrack, in state: LedgerState, now: Date, calendar: Calendar = .current) -> GuideStatus {
    var dates: [Date] = []
    if let sighting = state.guideSightings[track.rawValue] {
        dates += [sighting.first, sighting.last]
    }
    dates += state.movements.filter { movement in
        guard movement.bank == track.bank else { return false }
        return track.isApplePay ? movement.source == .wallet : movement.source == .notification
    }.map(\.date)
    guard let first = dates.min(), let last = dates.max() else { return .notYet }
    let from = calendar.startOfDay(for: last)
    let to = calendar.startOfDay(for: now)
    let days = max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    if days >= guideSilentAfterDays { return .silent(days: days, last: last) }
    return .working(since: first, last: last)
}

/// «20 nov»
public func guideShortDate(_ date: Date, calendar: Calendar = .current) -> String {
    let months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    let c = calendar.dateComponents([.day, .month], from: date)
    return "\(c.day ?? 1) \(months[min(max((c.month ?? 1) - 1, 0), 11)])"
}

/// La línea de estado de una fila de la lista.
public func guideStatusLine(_ status: GuideStatus, calendar: Calendar = .current) -> String {
    switch status {
    case .notYet: "Aún no ha llegado ningún aviso"
    case .working(_, let last): "Funciona · Último aviso: \(guideShortDate(last, calendar: calendar))"
    case .silent(let days, _): "Hace \(days) días que no llega ningún aviso"
    }
}
