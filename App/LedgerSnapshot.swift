import Foundation
import MiBancoCore

/// Un movimiento o un aviso sin leer, tal como los lista Inicio.
enum LedgerItem: Identifiable, Equatable, Sendable {
    case movement(Movement), unread(UnreadNotice)

    var id: UUID {
        switch self {
        case .movement(let m): return m.id
        case .unread(let n): return n.id
        }
    }
    var bank: BankID {
        switch self {
        case .movement(let m): return m.bank
        case .unread(let n): return n.bank
        }
    }
    var date: Date {
        switch self {
        case .movement(let m): return m.date
        case .unread(let n): return n.date
        }
    }
}

/// Una fila de la lista con sus textos ya redactados (el cuerpo de la vista no formatea nada).
struct ListRow: Identifiable, Equatable, Sendable {
    let item: LedgerItem
    /// Posición en su lista (0 = la más reciente): ordena la entrada escalonada.
    let order: Int
    let title: String
    let subtitle: String
    var id: UUID { item.id }
}

/// "Hoy", "Ayer", "Martes, 17 nov" y sus filas.
struct DaySection: Identifiable, Equatable, Sendable {
    /// Inicio del día.
    let id: Date
    let title: String
    var rows: [ListRow]
}

/// Una pieza de la lista plana que pinta Inicio: cabecera de día o fila. Una vista por elemento,
/// para que la pila perezosa saque la identidad de los ids sin evaluar cada fila.
struct ListEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case header(title: String, isFirst: Bool)
        /// `isLast`: última fila de su día (sin separador debajo).
        case row(ListRow, isLast: Bool)
    }
    /// Lleva el prefijo de su lista ("all-", "rev-"…): al cambiar de tarjeta, las filas son vistas nuevas y entran escalonadas.
    let id: String
    let kind: Kind
    /// Orden de su fila (la cabecera, el de la primera fila de su día): ordena la entrada escalonada.
    let order: Int

    static func flatten(_ sections: [DaySection], prefix: String) -> [ListEntry] {
        var out: [ListEntry] = []
        for (i, section) in sections.enumerated() {
            out.append(ListEntry(id: "\(prefix)-d\(Int(section.id.timeIntervalSince1970))",
                                 kind: .header(title: section.title, isFirst: i == 0),
                                 order: section.rows.first?.order ?? 0))
            for (j, row) in section.rows.enumerated() {
                out.append(ListEntry(id: "\(prefix)-\(row.id.uuidString)", kind: .row(row, isLast: j == section.rows.count - 1),
                                     order: row.order))
            }
        }
        return out
    }
}

/// Lo que se sabe del saldo de un banco.
struct BalanceInfo: Equatable, Sendable {
    let cents: Int
    /// false = lo dijo el banco en su último aviso y no ha habido movimientos después.
    let estimated: Bool
    /// Cuándo se fijó la base (aviso del banco o corrección a mano).
    let setAt: Date
    let fromBank: Bool
}

/// Un comercio silenciado: su clave normalizada (lo que guarda Core) y cómo se llama.
struct MutedMerchant: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    /// Lo que se le pasa a Core para dejar de silenciarlo: el nombre con que llegó (se normaliza a `key`).
    let raw: String
    var id: String { key }
}

/// "Este mes 412,30 €, 85,70 € menos que en octubre". Sin datos del mes anterior, solo la primera parte.
struct PaceLine: Equatable, Sendable {
    let thisMonthCents: Int
    /// Este mes menos el anterior a estas alturas (negativo = gastas menos). nil sin mes anterior.
    let differenceCents: Int?
    let previousMonthName: String
}

/// Valores derivados de `state`, calculados una sola vez por cambio de estado (o de día):
/// las vistas solo leen; nada se ordena, filtra ni formatea en un `body`.
struct LedgerSnapshot: Sendable {
    static let maxRows = 60

    var balances: [BankID: BalanceInfo] = [:]
    var total: Int?
    /// Lista de cada tarjeta, agrupada por día, recortada a `maxRows` y ya aplanada.
    var entries: [AccountCard: [ListEntry]] = [:]
    var weeks: [AccountCard: WeekSpend] = [:]
    /// Gasto de este mes (pagos tuyos) por tarjeta: la cara trasera de cada tarjeta.
    var monthSpent: [AccountCard: Int] = [:]
    var pace: PaceLine?
    var insights: [Insight] = []
    /// Ids de los avisos de atención (ámbar) del feed: la insignia de la pestaña Avisos cuenta los no vistos.
    var warningInsightIDs: [String] = []
    /// Nombre a mostrar de cada comercio (clave de `normalizeMerchant` -> el nombre más reciente con que llegó).
    var merchantNames: [String: String] = [:]
    /// Comercios silenciados, por nombre a mostrar, ya ordenados (pantalla "Comercios silenciados").
    var mutedList: [MutedMerchant] = []
    /// Lo que pide la configuración de avisos (interruptores de Avisos).
    var alertSettings = AlertSettings()
    /// Todos los movimientos, del más reciente al más antiguo: lo que recorre la búsqueda.
    var searchIndex: [Movement] = []
    /// Dominio del directorio de comercios por movimiento (su logo va en la app).
    var logoDomains: [UUID: String] = [:]
    /// Saldo del banco justo después de cada movimiento, cuando se puede calcular ("Te quedaban").
    var balanceAfter: [UUID: Int] = [:]
    /// Historial por comercio (clave de `normalizeMerchant`) y sus últimos pagos (más reciente primero, máx. 4).
    var histories: [String: MerchantHistory] = [:]
    var recentPayments: [String: [Movement]] = [:]
    var mutedMerchants: Set<String> = []
    var hasItems = false
    /// Día en que se calculó; al cambiar de día hay que recalcular aunque el estado no cambie.
    var day = Date.distantPast

    init() {}

    init(state: LedgerState, now: Date = Date(), calendar: Calendar = .current) {
        day = calendar.startOfDay(for: now)
        let ledger = Ledger(state: state)
        for bank in BankID.allCases {
            if let b = ledger.balance(bank), let base = state.balances[bank] {
                balances[bank] = BalanceInfo(cents: b.cents, estimated: b.estimated, setAt: base.setAt, fromBank: base.fromBank)
            }
        }
        total = ledger.total()
        mutedMerchants = state.mutedMerchants

        let byDate = state.movements.sorted { $0.date > $1.date }
        searchIndex = byDate
        for m in byDate {
            if let domain = m.logoDomain { logoDomains[m.id] = domain }
        }

        // Listas por tarjeta.
        let items = (byDate.map { LedgerItem.movement($0) } + state.unread.map { LedgerItem.unread($0) })
            .sorted { $0.date > $1.date }
        hasItems = !items.isEmpty
        for card in AccountCard.allCases {
            let mine = card.bank.map { bank in items.filter { $0.bank == bank } } ?? items
            let grouped = Self.sections(for: Array(mine.prefix(Self.maxRows)), showsBank: card == .all, now: now, calendar: calendar)
            entries[card] = ListEntry.flatten(grouped, prefix: card.rawValue)
            weeks[card] = WeekSpend(movements: state.movements, bank: card.bank, now: now, calendar: calendar)
        }

        // Gasto del mes por tarjeta.
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        var spent: [AccountCard: Int] = [:]
        for m in state.movements where m.kind == .payment && !m.flaggedNotMine && m.date >= monthStart && m.date <= now {
            spent[.all, default: 0] += abs(m.amountCents)
            spent[AccountCard(bank: m.bank), default: 0] += abs(m.amountCents)
        }
        monthSpent = spent

        let previousMonth = calendar.date(byAdding: .day, value: -1, to: monthStart) ?? monthStart
        let monthName = previousMonth.formatted(Date.FormatStyle(locale: Locale(identifier: "es_ES")).month(.wide))
        if let p = spendingPace(movements: state.movements, now: now, calendar: calendar) {
            pace = PaceLine(thisMonthCents: p.thisMonthCents, differenceCents: p.differenceCents, previousMonthName: monthName)
        } else if let month = spent[.all] {
            pace = PaceLine(thisMonthCents: month, differenceCents: nil, previousMonthName: monthName)
        }

        // "Te quedaban": saldo actual menos lo que pasó después de cada movimiento, banco a banco. Solo para
        // movimientos desde la base del saldo (`setAt`; el del propio aviso que trajo el saldo cae justo en `setAt`
        // y el saldo del banco ya lo incluye), que son los que `Ledger.balance` tiene en cuenta;
        // de los anteriores no se sabe y no se enseña nada.
        for bank in BankID.allCases {
            guard let current = balances[bank]?.cents, let reading = state.balances[bank] else { continue }
            var later = 0
            for m in byDate where m.bank == bank {
                guard m.date >= reading.setAt else { break }
                // Mismo criterio que `Ledger.balance`: lo que el saldo no suma (registros del banco, ya enlazados,
                // extractos sobre un saldo del banco) no cambia la cuenta ni enseña "Te quedaban".
                // El movimiento que cae justo en la base ya está dentro de la lectura.
                let counts = Ledger.countsTowardBalance(m, base: reading)
                guard counts || (m.date == reading.setAt && Ledger.isBalanceEligible(m, origin: reading.origin)) else { continue }
                balanceAfter[m.id] = current - later
                later += m.amountCents
            }
        }

        // Historial por comercio.
        var payments: [String: [Movement]] = [:]
        var names: [String: String] = [:]
        for m in byDate {
            guard let merchant = m.merchant else { continue }
            let key = normalizeMerchant(merchant)
            guard !key.isEmpty else { continue }
            names[key] = names[key] ?? merchant
            if m.kind == .payment && !m.flaggedNotMine && (payments[key]?.count ?? 0) < 4 {
                payments[key, default: []].append(m)
            }
        }
        recentPayments = payments
        merchantNames = names
        // Una sola pasada para todos los comercios (antes: una pasada completa por comercio).
        let all = merchantHistories(in: state.movements, now: now, calendar: calendar)
        let empty = MerchantHistory(countThisMonth: 0, totalThisMonthCents: 0, countAllTime: 0, firstDate: nil)
        for key in names.keys {
            histories[key] = all[key] ?? empty
        }
        alertSettings = state.alertSettings
        mutedList = state.mutedMerchants
            .map { MutedMerchant(key: $0, name: names[$0] ?? $0.capitalized, raw: names[$0] ?? $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        insights = MiBancoCore.insights(for: state, now: now, calendar: calendar)
        warningInsightIDs = insights.filter { $0.severity == .warning }.map(\.id)
    }

    func list(for card: AccountCard) -> [ListEntry] { entries[card] ?? [] }

    func isMuted(_ merchant: String?) -> Bool {
        guard let merchant else { return false }
        let key = normalizeMerchant(merchant)
        return !key.isEmpty && mutedMerchants.contains(key)
    }

    // MARK: - Agrupar por día

    /// `items` ya ordenados del más reciente al más antiguo.
    static func sections(for items: [LedgerItem], showsBank: Bool, now: Date, calendar: Calendar) -> [DaySection] {
        var out: [DaySection] = []
        for (order, item) in items.enumerated() {
            let day = calendar.startOfDay(for: item.date)
            let row = ListRow(item: item, order: order, title: title(of: item), subtitle: subtitle(of: item, showsBank: showsBank))
            if out.last?.id == day {
                out[out.count - 1].rows.append(row)
            } else {
                out.append(DaySection(id: day, title: dayTitle(day, now: now, calendar: calendar), rows: [row]))
            }
        }
        return out
    }

    static func title(of item: LedgerItem) -> String {
        switch item {
        case .movement(let m): m.displayTitle
        case .unread: "No se pudo leer este aviso"
        }
    }

    /// Todo: "Revolut · 18:47". Un banco: "18:47". La nota, si la hay, sustituye a la hora.
    private static func subtitle(of item: LedgerItem, showsBank: Bool) -> String {
        switch item {
        case .movement(let m):
            let detail = m.note ?? m.date.formatted(timeStyle)
            return showsBank ? "\(m.bank.displayName) · \(detail)" : detail
        case .unread(let n):
            return showsBank ? "\(n.bank.displayName) · \(n.text)" : n.text
        }
    }

    /// "Hoy", "Ayer", "Martes, 17 nov" (con año si no es este).
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Hoy" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Ayer"
        }
        let weekday = day.formatted(Date.FormatStyle(locale: spanish).weekday(.wide))
        let month = day.formatted(Date.FormatStyle(locale: spanish).month(.abbreviated)).replacing(".", with: "")
        var text = "\(weekday.prefix(1).uppercased())\(weekday.dropFirst()), \(calendar.component(.day, from: day)) \(month)"
        if calendar.component(.year, from: day) != calendar.component(.year, from: now) {
            text += " \(calendar.component(.year, from: day))"
        }
        return text
    }

    static let spanish = Locale(identifier: "es_ES")
    static let timeStyle = Date.FormatStyle(locale: spanish).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
}

extension Movement {
    /// Comercio, o "Pago"/"Ingreso" si el aviso no lo dice.
    var displayTitle: String { merchant ?? (kind == .payment ? "Pago" : "Ingreso") }
}
