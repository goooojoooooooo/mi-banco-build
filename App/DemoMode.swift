#if DEBUG
import Foundation
import MiBancoCore

/// Modo demo solo para compilaciones DEBUG: datos ficticios en memoria para las capturas del simulador.
/// Se activa con `-MiBancoDemo`. Argumentos para abrir estados concretos:
/// `-MiBancoDemoScreen inicio|gasto|avisos|ajustes`, `-MiBancoDemoCard todo|rev|ima|tr`, `-MiBancoDemoDetail`
/// (hoja del movimiento más reciente), `-MiBancoDemoPrivate` (modo privado), `-MiBancoDemoSearch <texto>`,
/// `-MiBancoDemoArrival` (llega un pago a los ~4 s), `-MiBancoDemoLock` (bloqueo y desbloqueo a los ~4 s),
/// `-MiBancoDemoOnlineLogo` (una tienda fuera del directorio, para la descarga del logo),
/// `-MiBancoDemoSwitch` (a los 2 s pasa a la tarjeta siguiente), `-MiBancoDemoRules` (Avisos, en los interruptores).
/// En la demo nada se escribe en el almacén ni en UserDefaults: los cambios viven en memoria.
enum DemoMode {
    enum Screen { case home, spending, alerts, settings }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after flag: String) -> String? {
        let args = arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var isActive: Bool { arguments.contains("-MiBancoDemo") }

    static var screen: Screen {
        switch value(after: "-MiBancoDemoScreen") ?? "" {
        case "gasto": .spending
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
        case "inv": .investments
        default: nil
        }
    }

    enum BriefingMode: String { case busy, quiet }

    static var scrollsToInvestments: Bool { arguments.contains("-MiBancoDemoInvestmentsSettings") }
    static var scrollsToAssistant: Bool { arguments.contains("-MiBancoDemoAssistantSettings") }
    static var asksPrices: Bool { arguments.contains("-MiBancoDemoAskPrices") }
    static var opensPosition: Bool { arguments.contains("-MiBancoDemoPosition") }
    static var demoMoveStep: Int? { value(after: "-MiBancoDemoMove").flatMap(Int.init) }
    static var opensAccounts: Bool { arguments.contains("-MiBancoDemoAccounts") }
    static var opensUpcoming: Bool { arguments.contains("-MiBancoDemoUpcoming") }
    static var briefingMode: BriefingMode? { value(after: "-MiBancoDemoBriefing").flatMap(BriefingMode.init(rawValue:)) }
    static var briefingShortfall: Bool { arguments.contains("-MiBancoDemoShortfall") }
    static var banksConnected: Bool { arguments.contains("-MiBancoDemoBanks") }
    static var opensConnectionGuide: Bool { arguments.contains("-MiBancoDemoGuide") }
    static var opensStatementImport: Bool { arguments.contains("-MiBancoDemoImport") }
    static var startsFlipped: Bool { arguments.contains("-MiBancoDemoFlip") }
    static var onboardingStep: Int? { value(after: "-MiBancoDemoOnboarding").flatMap(Int.init) }
    /// Argumentos DEBUG de la ronda U0–U67 (solo en memoria).
    static var showsImportFeedback: Bool { arguments.contains("-MiBancoDemoImportFeedback") }
    static var forcesPortfolio: Bool { arguments.contains("-MiBancoDemoPortfolio") }
    static var setsDemoFloor: Bool { arguments.contains("-MiBancoDemoFloor") }
    static var demoPendingMode: String? {
        guard arguments.contains("-MiBancoDemoPending") else { return nil }
        return value(after: "-MiBancoDemoPending") == "done" ? "done" : "waiting"
    }
    static var omittedIBANBank: BankID? { value(after: "-MiBancoDemoNoIban").flatMap(BankID.init(rawValue:)) }
    static var keychainFailCount: Int { arguments.contains("-MiBancoDemoKeychainFails") ? 2 : 0 }
    static var demoRoute: String? { value(after: "-MiBancoDemoRoute") }
    static var prefsFail: Bool { arguments.contains("-MiBancoDemoPrefsFail") }
    static var bankSyncAgoMinutes: Int? { value(after: "-MiBancoDemoBankSyncAgo").flatMap(Int.init) }
    /// U74: tras soltar «Ver» en Cuentas y contactos, el IBAN sigue a la vista estos segundos (la pulsación de XCUITest no
    /// deja mirar la pantalla mientras dura). Solo cambia CUÁNTO dura lo que ya ha revelado el toque, nunca lo revela.
    static var revealLingerSeconds: Double? {
        guard isActive else { return nil }
        return value(after: "-MiBancoDemoRevealLinger").flatMap(Double.init)
    }
    /// U76: entrar por el aviso de la mañana (`-MiBancoDemoRoute briefing`) a los N segundos del arranque, para probar que la
    /// ruta del aviso no abre el resumen encima de una confirmación ni de una conexión.
    static var demoRouteDelaySeconds: Double? { value(after: "-MiBancoDemoRouteAfter").flatMap(Double.init) }
    static var demoGuideKey: Bool { arguments.contains("-MiBancoDemoGuideKey") }
    static var demoConnectPhase: (phase: String, bank: BankID)? {
        let args = arguments
        guard let i = args.firstIndex(of: "-MiBancoDemoConnectPhase"),
              i + 2 < args.count,
              let bank = BankID(rawValue: args[i + 2]) else { return nil }
        return (args[i + 1], bank)
    }

    static func initialPendingMoves(now: Date = Date()) -> [PendingMove] {
        guard demoPendingMode != nil else { return [] }
        return [PendingMove(from: .ima, target: .own(.rev), amountCents: 20_000, createdAt: now.addingTimeInterval(-600))]
    }

    /// Extracto sintético de Revolut (muestra de la Tarea 6 con fechas desplazadas ~40 días atrás para que nada enlace
    /// y el resumen sea exactamente «3 movimientos nuevos, 3 filas ignoradas», con saldo 327,70 €).
    static func sampleRevolutStatementData(now: Date = Date()) -> Data {
        let cal = DateText.madridCalendar
        let today = cal.startOfDay(for: now)
        func fmt(_ daysAgo: Int, _ time: String) -> String {
            let d = cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let y = String(format: "%04d", c.year ?? 2026)
            let m = String(format: "%02d", c.month ?? 10)
            let day = String(format: "%02d", c.day ?? 10)
            return "\(y)-\(m)-\(day) \(time)"
        }
        let header = "Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"
        let rows = [
            "Transfer,Current,\(fmt(42, "10:00:00")),\(fmt(42, "10:00:01")),To USD,-20.00,0.50,EUR,COMPLETED,240.20",
            "Topup,Current,\(fmt(41, "08:00:00")),\(fmt(41, "08:00:01")),Apple Pay Top-Up,100.00,0.00,EUR,COMPLETED,340.20",
            "Card Payment,Current,\(fmt(40, "13:05:11")),\(fmt(39, "09:00:00")),Mercadona,-12.50,0.00,EUR,COMPLETED,327.70",
            "Card Payment,Current,\(fmt(40, "20:00:00")),,Bolt,-7.30,0.00,EUR,PENDING,",
            "Card Payment,Savings,\(fmt(48, "10:00:00")),\(fmt(48, "10:00:00")),Vault,-5.00,0.00,EUR,COMPLETED,10.00",
            "Card Payment,Current,\(fmt(43, "10:00:00")),\(fmt(43, "10:00:00")),Shop US,-3.00,0.00,USD,COMPLETED,1.00",
        ]
        return Data((([header] + rows).joined(separator: "\n") + "\n").utf8)
    }

    /// Cuaderno de cuentas de demo: solo IBANs de ejemplo publicados (ES91, DE89, GB82) y un contacto inventado.
    static func accountBook() -> AccountBook {
        var book = AccountBook()
        book.ibans = [
            .rev: "GB82WEST12345698765432",
            .ima: "ES9121000418450200051332",
            .tr: "DE89370400440532013000",
        ]
        if let omitted = omittedIBANBank {
            book.ibans.removeValue(forKey: omitted)
        }
        if setsDemoFloor {
            // Saldo de demo de Revolut (340,20 €) + 1,00 € para provocar un día bajo el mínimo (U24).
            book.floors[.rev] = 34_120
        }
        book.payees = [
            Payee(name: "Ana (demo)", phone: "+34 612 345 678"),
        ]
        return book
    }

    /// Solo carga cartera en demo cuando se pide alguna pantalla de inversiones o el resumen movido: las capturas previas no cambian.
    static var includesPortfolio: Bool {
        forcesPortfolio || showsImportFeedback || scrollsToInvestments || asksPrices || opensPosition
            || initialCard == .investments || briefingMode == .busy
    }

    /// Entradas del resumen de demo (`-MiBancoDemoBriefing busy|quiet`, con `-MiBancoDemoShortfall` opcional):
    /// valores idénticos a `busy` / `quiet` / `consejoPorFalta` de la Tarea 5 (`BriefingTests.swift`).
    static func briefingInput(mode: BriefingMode, shortfall: Bool, state: LedgerState? = nil, now: Date = Date()) -> BriefingInput {
        let cal = DateText.madridCalendar
        func nov(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? now
        }
        let spotify = UpcomingCharge(name: "Spotify", bank: .rev, cents: 1_099, date: nov(22, 12))
        let netflix = UpcomingCharge(name: "Netflix", bank: .rev, cents: 1_399, date: nov(25, 12))
        let month = MonthDigest(spentCents: 41_230, projectedCents: 69_000, paceDifferenceCents: -3_510, previousMonthName: "octubre")

        let demoShortfalls: [Shortfall] = shortfall ? [
            Shortfall(
                bank: .rev,
                charge: UpcomingCharge(name: "Netflix", bank: .rev, cents: 1_399, date: nov(21, 12)),
                balanceCents: 920,
                missingCents: 479,
                suggestedFrom: .ima,
                suggestedCents: 1_000
            ),
        ] : []

        if mode == .quiet {
            let quietNow = nov(21, 9, 10)
            let quietSummary = portfolioSummary(portfolio(now: nov(20, 17, 35)), now: quietNow, calendar: cal)
            return BriefingInput(
                now: quietNow,
                since: nov(20, 8, 30),
                isFirst: false,
                banks: [
                    BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 0),
                    BankLine(bank: .ima, cents: 128_455, estimated: true, changeCents: 0),
                    BankLine(bank: .tr, cents: 215_000, estimated: true, changeCents: 0),
                ],
                totalCents: 377_475,
                totalChangeCents: 0,
                upcoming: [spotify, netflix],
                month: month,
                investments: quietSummary,
                shortfalls: demoShortfalls,
                freeMoney: FreeMoney(cents: 154_977, daysLeft: 10)
            )
        }

        let busyNow = nov(20, 8, 30)
        let busySummary = portfolioSummary(portfolio(now: nov(19, 17, 35)), now: busyNow, calendar: cal)

        func movementID(merchant: String, cents: Int) -> UUID {
            state?.movements.first {
                $0.merchant == merchant && abs($0.amountCents) == cents
            }?.id ?? UUID()
        }

        return BriefingInput(
            now: busyNow,
            since: nov(19, 22, 10),
            isFirst: false,
            banks: [
                BankLine(bank: .rev, cents: 34_020, estimated: false, changeCents: 13_755),
                BankLine(bank: .ima, cents: 128_455, estimated: true, changeCents: 165_000),
                BankLine(bank: .tr, cents: 215_000, estimated: true, changeCents: 0),
            ],
            totalCents: 377_475,
            totalChangeCents: 178_755,
            income: [
                MovementDigest(id: movementID(merchant: "Nómina", cents: 145_000), bank: .ima, name: "Nómina ACME", cents: 185_000, date: nov(20, 6, 5)),
            ],
            payments: [
                MovementDigest(id: movementID(merchant: "Zara", cents: 4_995), bank: .rev, name: "Zara", cents: 4_995, date: nov(20, 7)),
                MovementDigest(id: movementID(merchant: "Mercadona", cents: 1_250), bank: .rev, name: "Mercadona", cents: 1_250, date: nov(20, 7)),
            ],
            transfers: [
                TransferDigest(from: .ima, to: .rev, cents: 20_000),
            ],
            upcoming: [spotify, netflix],
            attention: [
                .bankProblem(.ima, .bankUnavailable),
                .consentExpiring(.rev, nov(30, 10)),
            ],
            month: month,
            investments: busySummary,
            shortfalls: demoShortfalls,
            budgetTip: BudgetTip(name: "Comer fuera", remainingCents: 2_380),
            freeMoney: FreeMoney(cents: 154_977, daysLeft: 11)
        )
    }

    static func demoPositionInstrument(in summary: PortfolioSummary?) -> String? {
        summary?.positions.first(where: { $0.position.name == "Apple" })?.position.instrument
            ?? summary?.positions.first?.position.instrument
    }

    /// Cartera inventada del Plan 4b (tareas 6–7): MSCI World (8 acc.), Apple (3 acc.) y Ethereum (0,01).
    static func portfolio(now: Date = Date()) -> Portfolio {
        let cal = DateText.madridCalendar
        let today = cal.startOfDay(for: now)
        let marketTime = cal.date(bySettingHour: 17, minute: 35, second: 0, of: today) ?? now
        let importDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? now
        let txDate1 = cal.date(byAdding: .day, value: -180, to: today)?.addingTimeInterval(11 * 3600 + 15 * 60) ?? now
        let txDate2 = cal.date(byAdding: .day, value: -90, to: today)?.addingTimeInterval(14 * 3600 + 30 * 60) ?? now
        let txDate3 = cal.date(byAdding: .day, value: -45, to: today)?.addingTimeInterval(9 * 3600 + 45 * 60) ?? now

        var p = Portfolio()
        p.transactions = [
            InvestmentTransaction(
                id: "demo-msci-1", date: txDate1, instrument: "IE00B4L5Y983", name: "MSCI World",
                assetClass: "ETF", shares: 8, cashCents: -77_067, priceEUR: Decimal(string: "96.33")
            ),
            InvestmentTransaction(
                id: "demo-aapl-1", date: txDate1, instrument: "US0378331005", name: "Apple",
                assetClass: "STOCK", shares: 2, cashCents: -36_100, priceEUR: Decimal(string: "180.50")
            ),
            InvestmentTransaction(
                id: "demo-aapl-2", date: txDate2, instrument: "US0378331005", name: "Apple",
                assetClass: "STOCK", shares: 1, cashCents: -18_000, priceEUR: Decimal(string: "180.00")
            ),
            InvestmentTransaction(
                id: "demo-eth-1", date: txDate3, instrument: "ETH", name: "Ethereum",
                assetClass: "CRYPTO", shares: Decimal(string: "0.01")!, cashCents: -2_500, priceEUR: 2_500
            ),
        ]
        p.quotes = [
            "IE00B4L5Y983": Quote(priceEUR: 110, previousCloseEUR: Decimal(string: "108.50"), fetchedAt: marketTime, marketTime: marketTime),
            "US0378331005": Quote(priceEUR: 200, previousCloseEUR: 202, fetchedAt: marketTime, marketTime: marketTime),
        ]
        p.manualPrices = [
            "ETH": ManualPrice(priceEUR: 3_000, setAt: importDate),
        ]
        p.symbols = [
            "IE00B4L5Y983": "EUNL.DE",
            "US0378331005": "APC.DE",
        ]
        p.lastImport = importDate
        return p
    }

    /// `-MiBancoDemoSwitch`: a los 2 s pasa a la tarjeta siguiente como lo haría un toque en el segmentado.
    static var switchesCard: Bool { arguments.contains("-MiBancoDemoSwitch") }

    /// `-MiBancoDemoMonth <n>`: en Gasto, desplazamiento de meses respecto al actual (p. ej. `-1` = el mes anterior).
    static var monthOffset: Int { value(after: "-MiBancoDemoMonth").flatMap(Int.init) ?? 0 }

    /// `-MiBancoDemoCategory <raw>`: en Gasto, abre esa categoría del mes en curso. `-MiBancoDemoBudgets`: abre Presupuestos.
    static var openCategory: SpendingCategory? { value(after: "-MiBancoDemoCategory").flatMap(SpendingCategory.init(rawValue:)) }
    static var opensBudgets: Bool { arguments.contains("-MiBancoDemoBudgets") }
    /// `-MiBancoDemoSubscriptions`: abre Suscripciones.
    static var opensSubscriptions: Bool { arguments.contains("-MiBancoDemoSubscriptions") }

    static var opensDetail: Bool { arguments.contains("-MiBancoDemoDetail") || opensCategory }
    /// `-MiBancoDemoDetailCategory`: la hoja del movimiento más reciente, con la rejilla de categorías desplegada.
    static var opensCategory: Bool { arguments.contains("-MiBancoDemoDetailCategory") }
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
        if onboardingStep != nil {
            return LedgerState()
        }
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

        let balances: [BankID: ManualBalance] = if banksConnected {
            [
                .rev: ManualBalance(cents: 34_020, setAt: now, origin: .bank, fetchedAt: now),
                .ima: ManualBalance(cents: 128_455, setAt: now, origin: .bank, fetchedAt: now),
                .tr: ManualBalance(cents: 215_000, setAt: now, fromBank: false),
            ]
        } else {
            [
                // Revolut dio el saldo en el propio aviso de Mercadona (mismo instante): su "Te quedaban" se conoce.
                .rev: ManualBalance(cents: 34_020, setAt: day(0), fromBank: true),
                .ima: ManualBalance(cents: 128_455, setAt: now, fromBank: false),
                .tr: ManualBalance(cents: 215_000, setAt: now, fromBank: false),
            ]
        }

        // Gasto: lo de este mes se fecha siempre dentro del mes en curso y nunca en el futuro, sea el día que sea.
        // Hora fija (R19): el día sale de la fracción del mes transcurrido y la hora es siempre las 9:00 (hoy, las 0:30),
        // así las cifras de las capturas no cambian con la hora del día.
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        func thisMonth(_ fraction: Double) -> Date {
            let today = calendar.component(.day, from: now)
            let target = max(1, Int((Double(today) * fraction).rounded(.down)))
            let dayStart = calendar.date(byAdding: .day, value: target - 1, to: monthStart) ?? monthStart
            let fixed = dayStart.addingTimeInterval(target < today ? 9 * 3600 : 30 * 60)
            return min(fixed, now.addingTimeInterval(-120))
        }

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
            movement(.rev, -1_830, "Glovo", max(day(6, hour: 21, minute: 40), thisMonth(0.2))),
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
        let spread: [(Int, BankID, Int, String)] = [
            (2, .rev, -3_480, "Mercadona"), (4, .ima, -2_215, "Lidl"), (5, .rev, -1_260, "Glovo"),
            (8, .tr, -8_990, "Zara"), (9, .rev, -2_960, "Renfe"), (11, .ima, -4_620, "Carrefour"),
            (13, .rev, -2_975, "Mercadona"), (15, .ima, -6_040, "Repsol"), (17, .rev, -950, "Starbucks"),
            (18, .ima, -3_310, "Lidl"), (20, .rev, -2_650, "Glovo"), (23, .tr, -5_499, "Decathlon"),
            (25, .rev, -3_760, "Mercadona"), (27, .ima, -1_985, "Carrefour"),
        ]
        // Ojo: el ÚLTIMO cargo del mes pasado de un comercio que también tiene un pago reciente no puede parecerse en importe
        // (±25 %) al reciente, o según el día del mes (26–35 días de distancia) la demo mostraría una suscripción de más
        // (Glovo y Renfe lo hacían). Por eso Glovo del día 20 y Renfe cuestan bastante más que sus pagos recientes.
        // Los dos meses anteriores (el segundo, algo más barato): las comparaciones salen con cifras creíbles.
        for (back, percent) in [(1, 100), (2, 90)] {
            let first = monthsAgo(back, from: monthStart)
            let next = monthsAgo(back - 1, from: monthStart)
            for (dayOfMonth, bank, cents, merchant) in spread {
                // Repsol, Starbucks y Decathlon solo salen una vez por mes: en el mes más antiguo se adelantan 8 días para que no
                // se lean como suscripciones (cobros a 26-35 días); Suscripciones solo debe enseñar Spotify y Netflix.
                let oneOff = back == 2 && ["Repsol", "Starbucks", "Decathlon"].contains(merchant)
                guard let date = calendar.date(byAdding: .day, value: max(0, dayOfMonth - 1 - (oneOff ? 8 : 0)), to: first)?.addingTimeInterval(13 * 3600),
                      date < next else { continue }
                movements.append(movement(bank, cents * percent / 100, merchant, date))
            }
        }

        // Gasto: un traspaso entre tus bancos (no cuenta como gasto) y dos comidas fuera este mes.
        func transfer(_ bank: BankID, _ cents: Int, _ merchant: String) -> Movement {
            Movement(bank: bank, amountCents: cents, merchant: merchant, kind: cents < 0 ? .payment : .income,
                     source: .notification, date: thisMonth(0.35), isShop: false)
        }
        movements.append(transfer(.rev, -20_000, "Transferencia a imagin"))
        movements.append(transfer(.ima, 20_000, "Transferencia de Revolut"))
        movements.append(movement(.rev, -4_650, "Restaurante Lateral", thisMonth(0.5)))
        movements.append(movement(.rev, -1_240, "Bar Pepe", thisMonth(0.65)))

        // Un traspaso de Revolut a imagin ayer por la noche (mismo importe, a un minuto): Inicio lo lista como "Traspaso" y no cuenta como gasto.
        // Los textos hablan de transferencias y no son compras en tienda (`isShop` falso).
        let transferDate = day(1, hour: 22)
        movements.append(Movement(bank: .rev, amountCents: -5_000, merchant: "Transferencia a imagin", kind: .payment,
                                  source: .notification, date: transferDate))
        movements.append(Movement(bank: .ima, amountCents: 5_000, merchant: "Transferencia de Revolut", kind: .income,
                                  source: .notification, date: transferDate.addingTimeInterval(60)))

        if includesUnknownShop {
            // Marca fuera del directorio (tesla.es / tesla.com): obliga a la descarga online de verdad.
            movements.append(movement(.ima, -3_900, "Tesla", day(0).addingTimeInterval(-120)))
        }
        if demoPendingMode == "done" {
            // Salida reciente de 200,00 € desde imagin para que `moveState` marque el traspaso pendiente como `.done` (U24/U25).
            movements.append(Movement(
                bank: .ima, amountCents: -20_000, merchant: "Transferencia a Revolut", kind: .payment,
                source: .notification, date: now.addingTimeInterval(-120), isShop: false
            ))
        }

        var links: [BankID: BankLinkInfo] = [:]
        if banksConnected {
            let madrid = DateText.madridCalendar
            let revValid = madrid.date(from: DateComponents(year: 2027, month: 5, day: 19, hour: 10))
                ?? now.addingTimeInterval(180 * 86_400)
            let imaValid = madrid.date(byAdding: .day, value: 9, to: madrid.startOfDay(for: now))?.addingTimeInterval(12 * 3600)
                ?? now.addingTimeInterval(9 * 86_400)
            let revSyncAgo = Double(bankSyncAgoMinutes ?? 5) * 60
            var revLink = BankLinkInfo(
                connectedAt: now.addingTimeInterval(-30 * 86_400),
                consentValidUntil: revValid
            )
            revLink.lastAttemptAt = now.addingTimeInterval(-revSyncAgo)
            revLink.lastSuccessAt = now.addingTimeInterval(-revSyncAgo)
            revLink.historyLoaded = true
            links[.rev] = revLink

            var imaLink = BankLinkInfo(
                connectedAt: now.addingTimeInterval(-81 * 86_400),
                consentValidUntil: imaValid
            )
            imaLink.lastAttemptAt = now.addingTimeInterval(-15 * 60)
            imaLink.lastSuccessAt = now.addingTimeInterval(-15 * 60)
            imaLink.historyLoaded = true
            links[.ima] = imaLink
            // En modo conectado, el pago más reciente de Revolut aparece como «Pendiente» y todos los antiguos de Revolut e
            // imagin salvo uno (-14,35 € en Mercadona hace 12 días) están confirmados por el banco.
            for i in movements.indices {
                let m = movements[i]
                guard m.bank == .rev || m.bank == .ima else { continue }
                if i == 0 {
                    movements[i].bankRef = "demo-rev-pending-0"
                    movements[i].bankStatus = .pending
                    movements[i].linkedAt = m.date
                } else if m.bank == .rev && m.amountCents == -1_435 && m.merchant == "Mercadona" {
                    // Se deja sin bankRef para que unconfirmedCaptures lo marque «Sin confirmar por el banco».
                    continue
                } else {
                    movements[i].bankRef = "demo-\(m.bank.rawValue)-\(i)"
                    movements[i].bankStatus = .booked
                    movements[i].linkedAt = m.date
                }
            }
        }

        return LedgerState(balances: balances, movements: movements, unread: [],
                           budgets: Budgets(monthlyCents: 70_000, byCategory: [.comerFuera: 9_000]),
                           links: links)
    }
}
#endif
