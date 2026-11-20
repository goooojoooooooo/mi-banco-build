#if DEBUG
import Foundation
import MiBancoCore

/// Modo demo solo para compilaciones DEBUG: datos ficticios en memoria para las capturas del simulador.
/// Se activa con `-MiBancoDemo`. Argumentos para abrir estados concretos:
/// `-MiBancoDemoScreen inicio|avisos|ajustes`, `-MiBancoDemoCard todo|rev|ima|tr`, `-MiBancoDemoDetail`
/// (hoja del movimiento más reciente), `-MiBancoDemoPrivate` (modo privado), `-MiBancoDemoSearch <texto>`,
/// `-MiBancoDemoArrival` (llega un pago a los ~4 s), `-MiBancoDemoLock` (bloqueo y desbloqueo a los ~4 s),
/// `-MiBancoDemoOnlineLogo` (una tienda fuera del directorio, para la descarga del logo),
/// `-MiBancoDemoSwitch` (a los 2 s pasa a la tarjeta siguiente), `-MiBancoDemoRules` (Avisos, en los interruptores),
/// `-MiBancoDemoAlertsGuide <rev|tr|wallet|wallet-rev|wallet-tr> <paso>` (wallet = Apple Pay de imagin) (con `-MiBancoDemoScreen ajustes`: abre la guía de avisos en ese paso,
/// contando desde 1; con paso 0 solo abre la lista de guías).
/// En la demo nada se escribe en el almacén ni en UserDefaults: los cambios viven en memoria.
enum DemoMode {
    enum Screen { case home, alerts, settings }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after flag: String) -> String? {
        let args = arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var isActive: Bool { arguments.contains("-MiBancoDemo") }

    static var screen: Screen {
        switch value(after: "-MiBancoDemoScreen") ?? "" {
        case "avisos": .alerts
        case "ajustes": .settings
        default: .home
        }
    }

    static var initialCard: AccountCard? {
        switch value(after: "-MiBancoDemoCard") ?? "" {
        case "todo": .all
        case "rev": .rev
        case "ima": .ima
        case "tr": .tr
        default: nil
        }
    }

    /// `-MiBancoDemoSwitch`: a los 2 s pasa a la tarjeta siguiente como lo haría un toque en el segmentado.
    static var switchesCard: Bool { arguments.contains("-MiBancoDemoSwitch") }

    /// `-MiBancoDemoAlertsGuide <rev|tr|wallet|wallet-rev|wallet-tr> <paso>` (wallet = Apple Pay de imagin): paso desde 1 (0 = solo la lista); el paso en `step` cuenta desde 0.
    static var guideStart: (track: GuideTrack?, step: Int)? {
        guard let flag = arguments.firstIndex(of: "-MiBancoDemoAlertsGuide"), flag + 1 < arguments.count else { return nil }
        let track: GuideTrack?
        let number = flag + 2 < arguments.count ? Int(arguments[flag + 2]) ?? 1 : 1
        // Paso 0: solo la lista de guías (sin entrar en ninguna).
        if number <= 0 { return (nil, 0) }
        switch arguments[flag + 1] {
        case "rev": track = .revolut
        case "tr": track = .tradeRepublic
        case "wallet", "wallet-ima": track = .walletImagin
        case "wallet-rev": track = .walletRevolut
        case "wallet-tr": track = .walletTradeRepublic
        default: track = nil
        }
        return (track, number - 1)
    }

    /// `-MiBancoDemoGuideHalfway`: la guía de Apple Pay de imagin queda a medias (paso 9), para ver la lista con una guía empezada.
    static var guideProgressSeed: [String: String] {
        arguments.contains("-MiBancoDemoGuideHalfway")
            ? [GuideTrack.walletImagin.rawValue: GuideSavedStep(step: 8, of: guideSteps(for: .walletImagin).count).stored] : [:]
    }

    /// `-MiBancoDemoPersistGuide`: la demo guarda el último paso de cada guía en UserDefaults (prueba de reinicio);
    /// `-MiBancoDemoGuideReset` lo borra al arrancar.
    static var persistsGuideProgress: Bool { arguments.contains("-MiBancoDemoPersistGuide") }
    static var resetsGuideProgress: Bool { arguments.contains("-MiBancoDemoGuideReset") }

    static var opensDetail: Bool { arguments.contains("-MiBancoDemoDetail") }
    /// `-MiBancoDemoRules`: en Avisos, se desplaza hasta "Qué quieres que te avise".
    static var showsAlertRules: Bool { arguments.contains("-MiBancoDemoRules") }
    static var startsPrivate: Bool { arguments.contains("-MiBancoDemoPrivate") }
    static var searchQuery: String? { value(after: "-MiBancoDemoSearch") }

    /// `-MiBancoDemoArrival`: ~4 s tras arrancar entra un pago nuevo por el mismo camino que un intent real.
    static var simulatesArrival: Bool { arguments.contains("-MiBancoDemoArrival") }

    /// `-MiBancoDemoLock`: arranca con el bloqueo puesto (sin Face ID) y ~4 s después ejecuta el desbloqueo real.
    static var holdsLock: Bool { isActive && arguments.contains("-MiBancoDemoLock") }

    /// `-MiBancoDemoOnlineLogo`: la demo añade un pago en tienda de una marca que el directorio no conoce.
    static var includesUnknownShop: Bool { arguments.contains("-MiBancoDemoOnlineLogo") }

    /// Saldos fijados "ahora" (Revolut lo dijo el banco: al día; imagin y Trade Republic, estimados), así que los
    /// movimientos, todos anteriores, no los alteran (el pago de Mercadona de hoy ya está dentro de los 340,20 €).
    /// Hay historia para que salgan los avisos: Spotify sube de 9,99 a 10,99, Netflix se cobra en 3 días, una nómina,
    /// gasto repartido por el mes pasado (frase del ritmo) y compras previas en Mercadona (historial del comercio).
    static func state(now: Date = Date()) -> LedgerState {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        func day(_ daysAgo: Int, hour: Int = 12, minute: Int = 0) -> Date {
            if daysAgo == 0 { return now.addingTimeInterval(-60) }
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) ?? startOfToday
            return day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        func movement(_ bank: BankID, _ cents: Int, _ merchant: String, _ date: Date, note: String? = nil) -> Movement {
            Movement(
                bank: bank, amountCents: cents, merchant: merchant,
                kind: cents < 0 ? .payment : .income, source: .notification, date: date,
                // Los pagos de la demo son compras con tarjeta en tienda; Nómina, Bizum e Intereses no.
                isShop: cents < 0, note: note)
        }
        func monthsAgo(_ months: Int, from date: Date) -> Date {
            calendar.date(byAdding: .month, value: -months, to: date) ?? date
        }

        let balances: [BankID: ManualBalance] = [
            // Revolut dio el saldo en el propio aviso de Mercadona (mismo instante): su "Te quedaban" se conoce.
            .rev: ManualBalance(cents: 34_020, setAt: day(0), fromBank: true),
            .ima: ManualBalance(cents: 128_455, setAt: now, fromBank: false),
            .tr: ManualBalance(cents: 215_000, setAt: now, fromBank: false),
        ]

        // Lo reciente (lo que se ve en Inicio).
        let spotifyDate = day(1, hour: 9, minute: 2)
        var movements = [
            movement(.rev, -1_250, "Mercadona", day(0)),
            movement(.rev, -1_099, "Spotify", spotifyDate),
            movement(.ima, 145_000, "Nómina", day(2, hour: 8, minute: 30)),
            movement(.ima, 2_000, "Bizum de Laura", day(2, hour: 19, minute: 12)),
            movement(.rev, -1_480, "Renfe", day(3, hour: 7, minute: 45), note: "Billete a Valencia"),
            movement(.tr, 612, "Intereses", day(4, hour: 6)),
            movement(.tr, -4_995, "Zara", day(5, hour: 18, minute: 20)),
            movement(.ima, -2_340, "Lidl", day(5, hour: 11, minute: 5)),
            movement(.rev, -1_830, "Glovo", day(6, hour: 21, minute: 40)),
            // Dos cargos iguales en Amazon con tres minutos de diferencia: "Posible cobro duplicado" (ámbar) en Avisos.
            movement(.ima, -2_499, "Amazon", day(1, hour: 16, minute: 2)),
            movement(.ima, -2_499, "Amazon", day(1, hour: 16, minute: 5)),
        ]

        // Spotify: 9,99 los tres meses anteriores y 10,99 ayer (una subida de 1 €).
        for months in 1...3 {
            movements.append(movement(.rev, -999, "Spotify", monthsAgo(months, from: spotifyDate)))
        }

        // Netflix: dos cobros mensuales; el siguiente cae dentro de 3 días.
        let nextNetflix = calendar.date(byAdding: .day, value: 3, to: startOfToday)?.addingTimeInterval(10 * 3600) ?? now
        for months in 1...2 {
            movements.append(movement(.rev, -1_399, "Netflix", monthsAgo(months, from: nextNetflix)))
        }

        // Compras anteriores en Mercadona este mes (3, 7 y 12 de noviembre en la maqueta).
        for (daysAgo, cents) in [(7, -1_890), (12, -1_435), (16, -1_545)] {
            movements.append(movement(.rev, cents, "Mercadona", day(daysAgo, hour: 19, minute: 10)))
        }

        // El mes pasado, repartido: la frase del ritmo compara con él.
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        let lastMonth = monthsAgo(1, from: monthStart)
        let spread: [(Int, BankID, Int, String)] = [
            (2, .rev, -3_480, "Mercadona"), (4, .ima, -2_215, "Lidl"), (5, .rev, -1_260, "Glovo"),
            (8, .tr, -8_990, "Zara"), (9, .rev, -1_480, "Renfe"), (11, .ima, -4_620, "Carrefour"),
            (13, .rev, -2_975, "Mercadona"), (15, .ima, -6_040, "Repsol"), (17, .rev, -950, "Starbucks"),
            (18, .ima, -3_310, "Lidl"), (20, .rev, -2_145, "Glovo"), (23, .tr, -5_499, "Decathlon"),
            (25, .rev, -3_760, "Mercadona"), (27, .ima, -1_985, "Carrefour"),
        ]
        for (dayOfMonth, bank, cents, merchant) in spread {
            guard let date = calendar.date(byAdding: .day, value: dayOfMonth - 1, to: lastMonth)?.addingTimeInterval(13 * 3600),
                  date < monthStart else { continue }
            movements.append(movement(bank, cents, merchant, date))
        }

        if includesUnknownShop {
            // Marca fuera del directorio (tesla.es / tesla.com): obliga a la descarga online de verdad.
            movements.append(movement(.ima, -3_900, "Tesla", day(0).addingTimeInterval(-120)))
        }
        return LedgerState(balances: balances, movements: movements, unread: [])
    }
}
#endif
