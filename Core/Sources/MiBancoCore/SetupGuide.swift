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

    /// Lugares de la pantalla que nadie ha visto todavía en un iPhone con iOS 27 (para la lista de comprobación del móvil).
    public static let unverifiedPlaces: [String] = [
        "ficha «\(notificationVariable)» bajo el campo",
        "ficha «\(transactionVariable)» bajo el campo",
    ]

    /// Los que no se han visto en un iPhone con iOS 27 (para el informe y para revisarlos con el móvil en la mano).
    /// Sin los que el dueño ya confirmó en su móvil: «Atajos», «Cartera» y los disparadores «Notificación» y «Transacción».
    public static let unverified: [String] = [
        automationTab, newAutomation, appField, ok, runImmediately, notifyWhenRun, next,
        blankAutomation, addAction, shortcutInput,
        propertyTitle, propertySubtitle, propertyBody, propertyAmount, propertyMerchant,
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

/// Una guía por pantalla de la lista. OJO: `rawValue` es una clave de persistencia (el registro `guideSightings` del libro
/// y el último paso de cada guía en las preferencias): no se renombra sin migrar lo guardado.
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

    /// Revolut y Trade Republic ya avisan por su notificación: su guía de Apple Pay es opcional.
    /// imagin no avisa de otra forma: para él, la de Apple Pay es la única.
    public var isOptional: Bool { self == .walletRevolut || self == .walletTradeRepublic }

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
    case openShortcuts, automationTab, plusButton, triggerType, triggerSearch
    case appField, appPicker, appOK
    case walletCards, walletNext
    case runImmediately, notifyOff, runNext
    case blankAutomation
    case addActionButton, addActionSearch, addActionType, addAction
    case bankPicker, bankChoice, variablePicker, done
}

/// Qué hay que hacer en la pantalla: tocar algo, escribir en el buscador o tocar el buscador.
public enum GuideGesture: Sendable {
    case tap, type, search
}

/// Las cuatro partes de cada guía, en orden.
public let guideParts: [String] = [
    "Crear la automatización", "Que funcione sola", "Añadir la acción", "Rellenar los datos",
]

/// Lo último que dice la ayuda de cada paso.
public let guideHelpTail = "Si tu pantalla se ve distinta, toca la opción con el nombre más parecido. Si no hay ninguna, para aquí. Puedes borrar la automatización en Atajos y empezar de nuevo cuando quieras."

/// Qué guía hacer, en líneas cortas (encima de la lista).
public let guideListAdvice: [String] = [
    "Revolut y Trade Republic: haz la guía que lleva su nombre. La de Apple Pay es opcional, por si un aviso no llega.",
    "imagin: solo funciona con la guía de Apple Pay.",
]

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
    /// Parte de la guía, de 1 a 4 (`guideParts`).
    public let part: Int
    public let gesture: GuideGesture
    /// El campo de la acción que se está rellenando (solo en los pasos de datos).
    public let focus: String

    public init(id: String, title: String, instruction: String, tapTarget: String, place: String,
                illustration: GuideIllustration, help: String, part: Int = 1, gesture: GuideGesture = .tap,
                focus: String = "") {
        self.id = id
        self.title = title
        self.instruction = instruction
        self.tapTarget = tapTarget
        self.place = place
        self.illustration = illustration
        self.help = help
        self.part = part
        self.gesture = gesture
        self.focus = focus
    }

    /// Lo que lee VoiceOver del dibujo: qué hacer y dónde.
    public var spokenLabel: String {
        switch gesture {
        case .tap: "Dibujo de la pantalla. Toca «\(tapTarget)», \(place)."
        case .type: "Dibujo de la pantalla. Escribe «\(tapTarget)» en el buscador, \(place)."
        case .search: "Dibujo de la pantalla. Toca el buscador, \(place)."
        }
    }
}

/// «Parte 2 de 4 · Paso 9 de 22»
public func guideProgressLabel(_ step: GuideStep, number: Int, total: Int) -> String {
    "Parte \(step.part) de \(guideParts.count) · Paso \(number) de \(total)"
}

/// El paso (contando desde 0) en el que continuar una guía dejada a medias; nil si no hay nada que retomar.
/// Tolerante con lo guardado: un valor ilegible o fuera de rango no rompe nada.
/// Lo guardado lleva el número de pasos que tenía la guía en ese momento: si la guía ha cambiado, no se retoma.
public func guideResumeIndex(saved: GuideSavedStep?, total: Int) -> Int? {
    guard let saved, saved.of == total, total > 1, saved.step >= 1, saved.step < total else { return nil }
    return saved.step
}

/// El paso guardado de una guía y cuántos pasos tenía entonces (se guarda así: «9/22»).
public struct GuideSavedStep: Equatable, Sendable {
    public let step: Int
    public let of: Int

    public init(step: Int, of: Int) {
        self.step = step
        self.of = of
    }

    /// «9/22». La forma antigua (un número suelto) o cualquier otra cosa no es válida: devuelve nil.
    public init?(stored: Any?) {
        guard let text = stored as? String else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let step = Int(parts[0]), let of = Int(parts[1]), step >= 1, of >= 2 else { return nil }
        self.init(step: step, of: of)
    }

    public var stored: String { "\(step)/\(of)" }
}

/// «Vas por el paso 9 de 22»
public func guideResumeLine(index: Int, total: Int) -> String {
    "Vas por el paso \(index + 1) de \(total)"
}

private typealias N = GuideNames

/// Una sola acción por pantalla: cada instrucción pide un solo toque (o escribir), nombrado entre «».
public func guideSteps(for track: GuideTrack) -> [GuideStep] {
    var out: [GuideStep] = []
    var part = 1
    func add(_ title: String, _ instruction: String, _ tap: String, _ place: String, _ picture: GuideIllustration,
             _ help: String, gesture: GuideGesture = .tap, focus: String = "") {
        out.append(GuideStep(id: "\(track.rawValue)-\(out.count + 1)", title: title, instruction: instruction,
                             tapTarget: tap, place: place, illustration: picture, help: "\(help) \(guideHelpTail)",
                             part: part, gesture: gesture, focus: focus))
    }

    let bank = track.bankName
    let trigger = track.isApplePay ? N.transactionTrigger : N.notificationTrigger
    let center = "en el centro de la pantalla"
    let list = "en la lista"
    let results = "en la lista de resultados"
    let nothingToType = "No hay que escribir nada: es una lista."

    // 1. Crear la automatización
    add("Abre \(N.shortcutsApp)", "Toca el botón de abajo: se abre la app \(N.shortcutsApp).", "Abrir \(N.shortcutsApp)",
        "abajo, en esta pantalla", .openShortcuts,
        "Si no tienes \(N.shortcutsApp), descárgala gratis del App Store: es de Apple.")
    add("Ve a \(N.automationTab)", "Abajo, toca «\(N.automationTab)».", N.automationTab, "abajo, en el centro",
        .automationTab, "Si no ves la barra de abajo, toca la flecha de arriba a la izquierda hasta que aparezca.")
    add("Crea una nueva", "Toca «\(N.plus)» arriba a la derecha.", N.plus, "arriba a la derecha", .plusButton,
        "Si nunca has creado ninguna, el botón dice «\(N.newAutomation)».")
    add("Busca «\(trigger)»", "Escribe «\(trigger)» en el buscador.", trigger, "arriba", .triggerType,
        "El buscador está arriba, con una lupa. Escribe solo esa palabra.", gesture: .type)
    add("Elige «\(trigger)»",
        track.isApplePay ? "Toca «\(trigger)» en la lista (es la de \(N.walletApp))." : "Toca «\(trigger)» en la lista.",
        trigger, results, .triggerSearch,
        track.isApplePay ? "Tiene el icono de \(N.walletApp)." : "Si no aparece, comprueba que has escrito «\(trigger)» sin errores.")
    if track.isApplePay {
        add("Tu tarjeta de \(bank)", "Marca la tarjeta de «\(bank)».", bank, "en la lista de tarjetas", .walletCards,
            "La reconocerás por el nombre o por los últimos números. Si tienes dos tarjetas de «\(bank)», marca las dos. Si alguna otra aparece marcada, tócala para quitarle la marca. Si no tienes tarjeta de «\(bank)» en \(N.walletApp), sáltate esta guía.")
        add("Sigue", "Toca «\(N.next)».", N.next, "abajo", .walletNext, "Si no está abajo, mira arriba a la derecha.")
    } else {
        add("Elige la app", "Toca «\(N.appField)».", N.appField, center, .appField, "Si no la ves, desliza la pantalla hacia arriba con el dedo.")
        add("Elige \(bank)", "Toca «\(bank)» en la lista.", bank, list, .appPicker,
            "Si «\(bank)» no sale, abre la app de \(bank) una vez y vuelve a \(N.shortcutsApp).")
        add("Confirma", "Toca «\(N.ok)» arriba a la derecha.", N.ok, "arriba a la derecha", .appOK,
            "Está arriba a la derecha, junto al título.")
    }

    // 2. Que funcione sola
    part = 2
    add("Que vaya sola", "Marca «\(N.runImmediately)».", N.runImmediately, center, .runImmediately,
        "Si no lo marcas, el iPhone te preguntará cada vez.")
    add("Sin avisos de \(N.shortcutsApp)",
        "Apaga «\(N.notifyWhenRun)»: el interruptor debe quedar gris. Si ya está gris, no lo toques.",
        N.notifyWhenRun, center, .notifyOff, "Así \(N.shortcutsApp) no te enseña un aviso cada vez que funciona.")
    add("Sigue", "Toca «\(N.next)».", N.next, "abajo", .runNext, "Si no está abajo, mira arriba a la derecha.")

    // 3. Añadir la acción
    part = 3
    let action = track.isApplePay ? N.walletAction : N.noticeAction
    let typeHelp = "Si no aparece nada, comprueba que lo has escrito sin errores."
    let addHelp = "Si no aparece, borra lo que has escrito y escríbelo otra vez."
    add("Empieza en blanco", "Toca «\(N.blankAutomation)».", N.blankAutomation, center, .blankAutomation,
        "Si ves sugerencias, búscala entre ellas: puede estar arriba o abajo del todo.")
    add("Añade una acción", "Toca «\(N.addAction)».", N.addAction, center, .addActionButton,
        "Es el botón con un más, en el centro.")
    add("Busca \(guideAppName)", "Toca el buscador de arriba.", "Buscar", "arriba", .addActionSearch,
        "La lupa está arriba, debajo del título.", gesture: .search)
    add("Escribe \(guideAppName)", "Escribe «\(guideAppName)» en el buscador.", guideAppName, "arriba", .addActionType,
        typeHelp, gesture: .type)
    add("Elige la acción", "Toca «\(action)».", action, results, .addAction, addHelp)

    // 4. Rellenar los datos
    part = 4
    add("Elige el banco", "Toca «\(N.bankField)».", N.bankField, "en la tarjeta de la acción", .bankPicker, nothingToType)
    if track == .walletImagin {
        add("Elige \(bank)",
            "Toca «\(bank)» en la lista.", bank, list,
            .bankChoice, nothingToType)
    } else if track.isApplePay {
        add("Elige \(bank)", "Toca «\(bank)» en la lista: esta automatización es solo de sus tarjetas.", bank, list,
            .bankChoice, nothingToType)
    } else {
        add("Elige \(bank)", "Toca «\(bank)» en la lista.", bank, list, .bankChoice, nothingToType)
    }

    // Cada campo se rellena eligiendo de qué parte del aviso (o del pago) sale. Nombres SIN VERIFICAR en iOS 27.
    let chip = track.isApplePay ? N.transactionVariable : N.notificationVariable
    let intro = track.isApplePay ? "Aquí eliges de qué parte del pago sale cada dato. " : "Aquí eliges de qué parte del aviso sale cada dato. "
    var first = true
    func field(_ name: String) {
        add("Rellena «\(name)»",
            "\(first ? intro : "")Toca «\(name)». Abajo verás una ficha llamada «\(chip)»: tócala y luego elige «\(name)».",
            chip, "en la lista que se abre debajo de «\(name)»", .variablePicker,
            "Si solo ves «\(N.shortcutInput)», tócala y busca «\(name)» dentro.", focus: name)
        first = false
    }
    if track.isApplePay {
        field(N.amountField)
        field(N.merchantField)
        add("Listo",
            "Toca «\(N.ok)» arriba a la derecha. Para saber si funciona, mira la lista de guías después de tu próximo pago con Apple Pay de \(bank).",
            N.ok, "arriba a la derecha", .done, "Para otro banco, repite su guía de Apple Pay.")
    } else {
        field(N.titleField)
        field(N.subtitleField)
        field(N.bodyField)
        add("Listo",
            "Toca «\(N.ok)» arriba a la derecha. Para saber si funciona, mira la lista de guías después del próximo aviso de \(bank).",
            N.ok, "arriba a la derecha", .done, "Está arriba a la derecha, junto al título.")
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

extension IngestInput {
    /// Una entrada vacía: un atajo a medio construir, que todavía no lleva ningún dato.
    var isBlank: Bool {
        func empty(_ text: String?) -> Bool { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch self {
        case .notification(_, let title, let subtitle, let body): return empty(title) && empty(subtitle) && empty(body)
        case .wallet(_, let amount, _): return empty(amount)
        }
    }
}

extension LedgerState {
    /// Apunta que ha llegado algo por esa guía (también si era un duplicado o no se pudo leer: lo que importa es que
    /// el atajo funciona). Solo marca su guía: un pago de un banco no marca a otro.
    mutating func recordGuideSighting(for input: IngestInput, now: Date) {
        guard let track = GuideTrack.forInput(input), !input.isBlank else { return }
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
/// Las guías de Apple Pay hablan de pagos; las de los bancos, de avisos.
public func guideStatusLine(_ status: GuideStatus, applePay: Bool = false, calendar: Calendar = .current) -> String {
    switch status {
    case .notYet: applePay ? "Aún no ha llegado ningún pago con Apple Pay" : "Aún no ha llegado ningún aviso"
    case .working(_, let last):
        "Funciona · Último \(applePay ? "pago" : "aviso"): \(guideShortDate(last, calendar: calendar))"
    case .silent(let days, _):
        applePay
            ? "Hace \(days) días que no llega ningún pago con Apple Pay. Si has pagado con Apple Pay de este banco desde entonces, repasa la guía."
            : "Hace \(days) días que no llega ningún aviso. Si has pagado con este banco desde entonces, repasa la guía."
    }
}
