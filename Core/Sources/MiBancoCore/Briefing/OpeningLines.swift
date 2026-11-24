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
        "Te doy la bienvenida. Desde hoy te cuento cada día lo que pasa con tus cuentas.",
        "Un gusto empezar contigo. Aquí tienes tu primer resumen.",
        "Primer día juntos. Te dejo un resumen de lo que ya veo en tus cuentas.",
        "Empezamos. Esto es lo que he podido ver hasta ahora.",
        "Un placer arrancar contigo. Te pongo al día de lo que veo.",
        "Aquí estoy para contarte cada día cómo van tus cuentas.",
        "Primer resumen, el de estreno. Vamos allá.",
        "Hola, soy \(appDisplayName). Cada día te contaré cómo van tus cuentas.",
    ],
    .backAfterDays: [
        "Cuánto tiempo. Te cuento lo que ha pasado mientras no estabas.",
        "Qué bien que hayas vuelto. Ha pasado un tiempo, así que hay bastante que repasar.",
        "Otra vez por aquí. Repasamos lo ocurrido estos días.",
        "Ya estás de vuelta. Esto es lo que se ha movido desde la última vez.",
        "Hacía días que no pasabas por aquí. Te pongo al día.",
        "Ha pasado un tiempo. Vamos con lo que ha ocurrido desde entonces.",
        "Tras unos días sin pasar por aquí, esto es lo que ha ido llegando.",
        "Han pasado unos días. Te resumo lo ocurrido.",
        "Unos días sin pasar por aquí. Te cuento cómo han ido las cosas.",
    ],
    .bankUnreadable: [
        "Hay algún banco que no he podido leer, así que el resumen puede estar incompleto.",
        "Algún banco no me ha dejado mirar esta vez. Te cuento lo que sí he visto.",
        "Algún banco no está al día, así que esto es solo una parte.",
        "No he conseguido leer todos los bancos. Esto es lo que he podido ver.",
        "Algún banco no se deja ver. Lo que sí veo, aquí abajo.",
        "De algún banco no tengo datos nuevos. Te cuento lo que sí tengo.",
        "Me falta ver algún banco, así que el resumen puede quedarse corto.",
        "Algún banco se ha quedado sin leer. Te dejo lo que sí he podido mirar.",
        "Con algún banco hay un problema. Aquí va lo que sí tengo.",
    ],
    .needsAttention: [
        "Hoy hay algo que pide tu atención. Te lo cuento más abajo.",
        "Ha saltado algún aviso, lo dejo apuntado en el resumen.",
        "Algo ha llamado mi atención, lo verás enseguida.",
        "Hay algún aviso en tus cuentas. Lo verás más abajo.",
        "Ha surgido algo en tus cuentas. Te lo cuento enseguida.",
        "Ha saltado algún aviso. Está marcado más abajo.",
        "Hay algo en el resumen que merece tu atención.",
        "Hay una nota en el resumen de hoy, la verás enseguida.",
        "El resumen trae algún aviso. Está en su sitio, más abajo.",
    ],
    .incomeArrived: [
        "Ha entrado dinero en tus cuentas. Te lo cuento enseguida.",
        "Ha llegado algún ingreso. Vamos con los detalles.",
        "Algo ha entrado en tus cuentas. Vamos con los detalles.",
        "Ha caído algún ingreso. Repaso rápido de lo demás.",
        "Hay algún ingreso por aquí. Te cuento cómo queda todo.",
        "Ha entrado dinero por aquí. Vamos con el detalle.",
        "Algo ha llegado a tus cuentas. Aquí va el detalle.",
        "Ha entrado algún ingreso nuevo. Repasamos lo ocurrido desde la última vez.",
        "Te ha llegado dinero. Te cuento lo que hay en el resumen.",
    ],
    .busyDay: [
        "Ha habido movimiento por aquí. Hay bastante que contar.",
        "Ha habido bastante movimiento en tus cuentas. Vamos por partes.",
        "Hay bastante movimiento desde la última vez. Te lo ordeno.",
        "Bastantes movimientos desde la última vez. Te los cuento sin prisa.",
        "Bastante actividad desde la última vez. Aquí va el repaso.",
        "Han pasado varias cosas en tus cuentas. Las repasamos juntos.",
        "Se han juntado varios pagos. Te resumo lo importante.",
        "Hay bastante que ver, pero lo tienes ordenado más abajo.",
        "Han salido varios pagos. Te cuento lo que ha pasado.",
    ],
    .weekend: [
        "Buen fin de semana. Esto es lo que ha pasado por aquí.",
        "Fin de semana por aquí. Te cuento cómo va todo.",
        "Es fin de semana y hay poco movimiento por aquí. Te lo cuento.",
        "Hoy es fin de semana. Un repaso breve y a disfrutar.",
        "Es fin de semana. Aquí tienes el resumen de siempre.",
        "Es fin de semana. Esto es lo que veo en tus cuentas.",
        "Un fin de semana más. Te pongo al día sin prisas.",
        "Hoy no hay prisa, es fin de semana. Te cuento lo justo.",
        "Buenas, que sea un buen fin de semana. Te dejo el resumen.",
    ],
    .monthStart: [
        "Mes recién estrenado. Te cuento cómo arranca.",
        "Empieza el mes. Esto es lo que veo.",
        "Estamos a principios de mes. Te cuento cómo va todo.",
        "Nuevo mes. Te cuento qué hay de nuevo.",
        "Primeros días del mes. Te cuento cómo va.",
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
        "Ya casi termina el mes. Te cuento lo que hay.",
        "Recta final del mes. Vamos con lo de hoy.",
        "Estamos en los últimos días del mes. Te cuento cómo va.",
        "El mes se despide. Te cuento lo que ha pasado.",
        "Fin de mes asomando. Repasamos lo de hoy.",
    ],
    .quietDay: [
        "Un día más por aquí. Te cuento cómo va todo.",
        "Pocos movimientos esta vez. Un repaso rápido y listo.",
        "Poco movimiento desde la última vez. Te lo cuento enseguida.",
        "No hay avisos nuevos por ahora. Aquí tienes el resumen.",
        "Un día corriente por aquí. Esto es lo que veo.",
        "Aquí tienes el resumen de hoy. Vamos allá.",
        "Poca cosa que contar esta vez. Te cuento lo que hay.",
        "Un día corriente. Vamos con el resumen.",
        "Seguimos con lo de siempre. Te pongo al día en un momento.",
    ],
]

/// Las frases candidatas de una situación.
func openingCandidates(for situation: OpeningSituation) -> [String] { openingCatalogue[situation] ?? [] }

/// Número de frases candidatas de una situación (para validar la respuesta del modelo con `openingChoice(from:count:)`).
public func openingCandidateCount(for situation: OpeningSituation) -> Int { openingCandidates(for: situation).count }

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
    // Sin ceros a la izquierda («03» no es un número de la lista).
    guard !text.isEmpty, !(text.count > 1 && text.hasPrefix("0")), text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (1...max(count, 1)).contains(value),
          count >= 1 else { return nil }
    return value
}

public let briefingModelInstructions =
    "Eres el asistente de \(appDisplayName). Te doy varias frases de saludo numeradas. Elige la que mejor encaje con el día y responde solo con su número. No escribas nada más."

/// El mensaje al modelo: la situación en palabras y las frases candidatas numeradas. Nada más: ni importes, ni comercios, ni
/// inversiones; el único dígito que lleva es el de cada número de la lista.
public func briefingModelPrompt(_ briefing: Briefing) -> String {
    let lines = openingCandidates(for: briefing.situation)
    var text = "Situación: \(briefing.situation.promptLabel).\n"
    for (i, line) in lines.enumerated() { text += "\(i + 1). \(line)\n" }
    return text + "Responde solo con el número de la frase."
}
