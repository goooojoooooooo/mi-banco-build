import Foundation

/// La situación del día para elegir la frase de apertura. Se decide SOLO por reglas, con lo que ya sabe el resumen.
///
/// Precedencia (la primera que se cumple gana):
/// 1. `firstEver`: es el primer resumen que se enseña.
/// 2. `backAfterDays`: el periodo cubre 3 o más días (volvió tras unos días sin abrir).
/// 3. `bankUnreadable`: hay un banco con problema de conexión en la lista de atención.
/// 4. `needsAttention`: hay cualquier otro aviso en la lista de atención.
/// 5. `incomeArrived`: ha entrado algún ingreso.
/// 6. `busyDay`: 4 pagos o más en el periodo.
/// Y solo si el día no es nada de lo anterior (los días de calendario no pisan a los hechos):
/// 7. `weekend`: sábado o domingo (Madrid).
/// 8. `monthStart`: del 1 al 3 del mes.
/// 9. `monthEnd`: los tres últimos días del mes.
/// 10. `quietDay`: el resto.
public enum OpeningSituation: String, CaseIterable, Sendable {
    case firstEver, backAfterDays, bankUnreadable, needsAttention, incomeArrived, busyDay, weekend, monthStart, monthEnd, quietDay

    /// Cómo se nombra al modelo en el mensaje que le pide elegir (palabras, nunca cifras ni importes).
    var promptLabel: String {
        switch self {
        case .firstEver: "primer resumen"
        case .backAfterDays: "vuelta tras unos días"
        case .bankUnreadable: "un banco no se ha podido leer"
        case .needsAttention: "hay un aviso"
        case .incomeArrived: "ha entrado dinero"
        case .busyDay: "día movido"
        case .weekend: "fin de semana"
        case .monthStart: "principio de mes"
        case .monthEnd: "final de mes"
        case .quietDay: "día tranquilo"
        }
    }
}

/// Los pagos a partir de los cuales el día se considera movido.
let busyDayPayments = 4

/// Los días a partir de los cuales un periodo cuenta como «vuelta tras unos días».
let backAfterDaysThreshold = 3

/// La situación del día (ver `OpeningSituation` para el orden).
func openingSituation(for input: BriefingInput, calendar: Calendar) -> OpeningSituation {
    if input.isFirst { return .firstEver }
    let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: input.since), to: calendar.startOfDay(for: input.now)).day ?? 0
    if gap >= backAfterDaysThreshold { return .backAfterDays }
    if !bankProblemBanks(input).isEmpty { return .bankUnreadable }
    if !input.attention.isEmpty { return .needsAttention }
    if !input.income.isEmpty { return .incomeArrived }
    if input.payments.count >= busyDayPayments { return .busyDay }
    let weekday = calendar.component(.weekday, from: input.now)
    if weekday == 1 || weekday == 7 { return .weekend }
    let day = calendar.component(.day, from: input.now)
    let daysInMonth = calendar.range(of: .day, in: .month, for: input.now)?.count ?? 30
    if day <= 3 { return .monthStart }
    if day > daysInMonth - 3 { return .monthEnd }
    return .quietDay
}

/// El catálogo, escrito a mano, de frases de apertura. Sin cifras, sin palabras de inversión y sin nada que invite a hacer algo
/// con el dinero. Una prueba pasa `containsAdvice` y `containsNumber` por todas y exige como mucho 90 caracteres.
let openingCatalogue: [OpeningSituation: [String]] = [
    .firstEver: [
        "Hola, es la primera vez que nos vemos por aquí. Iré contándote cómo va todo.",
        "Bienvenido. Desde hoy te cuento cada día lo que pasa con tus cuentas.",
        "Encantado de empezar contigo. Aquí tienes tu primer resumen.",
        "Primer día juntos. Te dejo un resumen de lo que ya veo en tus cuentas.",
        "Empezamos. Esto es lo que he podido ver hasta ahora.",
        "Un placer arrancar contigo. Te pongo al día de lo que veo.",
        "Aquí estoy, listo para contarte cada día cómo van tus cuentas.",
        "Primer resumen, el de estreno. Vamos allá.",
        "Hola. Soy tu resumen diario y hoy me toca presentarme.",
    ],
    .backAfterDays: [
        "Cuánto tiempo. Te cuento lo que ha pasado mientras no estabas.",
        "Bienvenido de vuelta. Ha pasado un tiempo, así que hay bastante que repasar.",
        "Qué bien verte otra vez. Repasamos lo que ha ocurrido estos días.",
        "Ya estás de vuelta. Esto es lo que se ha movido desde la última vez.",
        "Hacía días que no pasabas por aquí. Te pongo al día.",
        "Te echaba de menos por aquí. Vamos con lo que ha pasado en este tiempo.",
        "Después de unos días fuera, aquí tienes lo que ha ido llegando.",
        "Cuánto sin verte. Te resumo los últimos días con calma.",
        "Regresas tras una pausa. Te cuento cómo han ido las cosas.",
    ],
    .bankUnreadable: [
        "Hay un banco que no he podido leer hoy, así que el resumen puede estar incompleto.",
        "Algún banco no me ha dejado mirar esta vez. Te cuento lo que sí he visto.",
        "Un banco no ha respondido, así que lo de hoy es solo una parte.",
        "No he conseguido leer todos los bancos. Esto es lo que he podido ver.",
        "Hoy hay un banco que no se deja ver. El resto, aquí abajo.",
        "Uno de tus bancos no ha contestado. Lo demás sí lo tengo claro.",
        "Me falta ver algún banco, así que el resumen puede quedarse corto.",
        "Un banco se ha quedado sin leer. Te dejo lo que sí he podido mirar.",
        "No todos los bancos han querido hablar hoy. Aquí va lo que tengo.",
    ],
    .needsAttention: [
        "Hoy hay algo que pide tu atención. Te lo cuento más abajo.",
        "Ha saltado algún aviso, lo dejo apuntado en el resumen.",
        "Algo ha llamado mi atención, lo verás enseguida.",
        "Hoy hay un aviso en tus cuentas. Lo tienes justo debajo.",
        "Ha surgido algo en tus cuentas. Te lo cuento enseguida.",
        "Un aviso ha entrado por aquí. Va marcado más abajo.",
        "Tengo una cosa que contarte antes del resto.",
        "Hay una nota en el resumen de hoy, la verás enseguida.",
        "Hoy el resumen trae un aviso. Está en su sitio, más abajo.",
    ],
    .incomeArrived: [
        "Hoy ha entrado dinero en tus cuentas. Te lo cuento enseguida.",
        "Ha llegado un ingreso. Vamos con los detalles.",
        "Buenas noticias: algo ha entrado en tus cuentas.",
        "Ha caído un ingreso esta vez. Repaso rápido de lo demás.",
        "Hoy hay ingresos por aquí. Te cuento cómo queda el día.",
        "Se nota movimiento a favor: ha entrado dinero.",
        "Algo ha llegado a tus cuentas. Aquí va el detalle.",
        "Ha entrado un ingreso nuevo. Repasamos cómo ha ido el día.",
        "Te ha llegado dinero. Te cuento lo que hay en el resumen.",
    ],
    .busyDay: [
        "Día movido por aquí. Hay bastante que contar.",
        "Ha habido mucho trasiego en tus cuentas. Vamos por partes.",
        "Hoy hay más movimiento de lo normal. Te lo ordeno.",
        "Muchos movimientos desde la última vez. Te los cuento sin prisa.",
        "Un día con bastante actividad. Aquí va el repaso.",
        "Han pasado varias cosas en tus cuentas. Las repasamos juntos.",
        "Menudo ritmo llevan tus cuentas. Te resumo lo importante.",
        "Hay mucho que ver hoy, pero lo tienes ordenado más abajo.",
        "Tus cuentas no han parado. Te cuento lo que ha pasado.",
    ],
    .weekend: [
        "Buen fin de semana. Esto es lo que ha pasado por aquí.",
        "Fin de semana tranquilo por aquí. Te cuento cómo va todo.",
        "Es fin de semana y las cuentas van a su ritmo. Te lo cuento.",
        "Hoy es fin de semana. Un repaso breve y a disfrutar.",
        "Fin de semana por delante. Aquí tienes el resumen de siempre.",
        "Cuentas en calma para ser fin de semana. Esto es lo que veo.",
        "Un fin de semana más. Te pongo al día sin prisas.",
        "Hoy no hay prisa, es fin de semana. Te cuento lo justo.",
        "Buenas, que sea un buen fin de semana. Te dejo el resumen.",
    ],
    .monthStart: [
        "Mes recién estrenado. Te cuento cómo arranca.",
        "Empieza el mes y las cuentas arrancan con calma. Esto es lo que veo.",
        "Estamos a principios de mes. Te cuento cómo va todo.",
        "Nuevo mes, hoja en blanco. Te cuento qué hay de nuevo.",
        "Primeros días del mes, ritmo suave. Te cuento cómo va.",
        "Arranca el mes. Te pongo al día de lo que ha pasado.",
        "Un mes nuevo acaba de empezar. Aquí va el resumen de hoy.",
        "Mes nuevo, resumen nuevo. Te cuento qué hay.",
        "Comienzo de mes por aquí. Vamos con lo de hoy.",
    ],
    .monthEnd: [
        "Se acerca el final del mes. Te cuento cómo va todo.",
        "Últimos días del mes por aquí. Esto es lo que veo.",
        "El mes va llegando a su fin. Te pongo al día.",
        "Final de mes a la vista. Aquí va el resumen de hoy.",
        "Ya casi cerramos el mes. Te cuento lo que hay.",
        "Recta final del mes. Vamos con lo de hoy.",
        "Estamos en los últimos días del mes. Te lo cuento con calma.",
        "El mes se despide. Te cuento cómo ha ido el día.",
        "Fin de mes asomando. Repasamos lo de hoy.",
    ],
    .quietDay: [
        "Día tranquilo por aquí. Te cuento cómo va todo.",
        "Todo en calma esta vez. Un repaso rápido y listo.",
        "Poco movimiento desde la última vez. Te lo cuento enseguida.",
        "Sin sobresaltos por ahora. Aquí tienes el resumen.",
        "Un día de los tranquilos. Esto es lo que veo.",
        "Va todo a su ritmo. Te dejo el resumen de hoy.",
        "Nada que te quite el sueño. Te cuento lo que hay.",
        "Día sin sorpresas. Vamos con el resumen.",
        "Todo sigue su curso. Te pongo al día en un momento.",
    ],
]

/// Las frases candidatas de una situación.
func openingCandidates(for situation: OpeningSituation) -> [String] { openingCatalogue[situation] ?? [] }

/// El número de días de Madrid desde una fecha de referencia: estable durante todo el día, +1 al día siguiente.
private func dayNumber(_ day: Date) -> Int {
    let reference = madridCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date(timeIntervalSince1970: 1_767_222_000)
    return madridCalendar.dateComponents([.day], from: reference, to: madridCalendar.startOfDay(for: day)).day ?? 0
}

/// La frase de apertura: SIEMPRE una del catálogo, escrita a mano. `choice` es el número (de 1 a N, como en la lista que se le
/// dio al modelo) que propone el modelo del dispositivo; solo vale si está en rango. Sin elección válida, la frase rota por días:
/// la misma durante todo el día y nunca la misma que la del día anterior en la misma situación. Con el modo privado se usa el
/// mismo catálogo (ninguna frase lleva cifras).
public func openingLine(briefing: Briefing, choice: Int?, day: Date, privateMode: Bool) -> String {
    let lines = openingCandidates(for: briefing.situation)
    guard !lines.isEmpty else { return "" }
    if let choice, (1...lines.count).contains(choice) { return lines[choice - 1] }
    let index = ((dayNumber(day) + (OpeningSituation.allCases.firstIndex(of: briefing.situation) ?? 0)) % lines.count + lines.count) % lines.count
    return lines[index]
}

/// El número que contesta el modelo, si es un entero dentro de 1...`count` (con espacios o un punto final); si no, nil.
public func openingChoice(from answer: String, count: Int) -> Int? {
    var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasSuffix(".") { text.removeLast() }
    guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (1...max(count, 1)).contains(value),
          count >= 1 else { return nil }
    return value
}

public let briefingModelInstructions =
    "Eres el asistente de Mi Banco. Te doy varias frases de saludo numeradas. Elige la que mejor encaje con el día y responde solo con su número. No escribas nada más."

/// El mensaje al modelo: la situación en palabras y las frases candidatas numeradas. Nada más: ni importes, ni comercios, ni
/// inversiones; el único dígito que lleva es el de cada número de la lista.
public func briefingModelPrompt(_ briefing: Briefing) -> String {
    let lines = openingCandidates(for: briefing.situation)
    var text = "Situación: \(briefing.situation.promptLabel).\n"
    for (i, line) in lines.enumerated() { text += "\(i + 1). \(line)\n" }
    return text + "Responde solo con el número de la frase."
}
