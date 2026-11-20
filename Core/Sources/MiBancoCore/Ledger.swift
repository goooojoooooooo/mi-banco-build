import Foundation

public struct Movement: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case notification, wallet, bank, statement }

    public var id: UUID
    public var bank: BankID
    /// Negativo = pago.
    public var amountCents: Int
    public var merchant: String?
    public var kind: MovementKind
    public var source: Source
    public var date: Date
    /// true cuando ya absorbió el mismo pago visto por la otra fuente (Cartera + aviso).
    public var pairedAcrossSources: Bool
    /// Huella estable del texto de origen (ver `ingestFingerprint`); nunca el texto en sí.
    public var fingerprint: String?
    /// Huella del registro de la otra fuente que se emparejó con este, para reconocer su reentrega.
    public var pairedFingerprint: String?
    /// true = pago en una tienda (señal positiva del aviso o Apple Pay con comercio). Solo entonces se puede
    /// buscar su logo en internet; nunca para personas ("de Carlos", "a Laura").
    public var isShop: Bool
    /// Nota libre del usuario sobre este movimiento (nil = sin nota).
    public var note: String?
    /// true = el usuario dice que este movimiento no es suyo: se excluye de sumas, detecciones y avisos.
    public var flaggedNotMine: Bool
    /// La categoría que el dueño puso a este movimiento (nil = la decide la app).
    public var category: SpendingCategory?
    /// nil = lo decide la app (ver `ownTransferPairs`); true = el dueño dice que es un traspaso entre sus cuentas; false = dice que no.
    public var ownTransfer: Bool?

    // MARK: Datos del banco (Plan 2)
    /// Clave del registro de la API del banco una vez enlazado.
    public var bankRef: String?
    /// Clave de la fila del extracto CSV una vez enlazada.
    public var statementRef: String?
    public var bankStatus: BankStatus?
    /// Solo en los movimientos CREADOS desde un registro del banco o de un extracto.
    public var importedAt: Date?
    /// true = la fecha es un día sin hora (se guarda al mediodía de Madrid).
    public var dayOnly: Bool
    /// Nombre que da el banco cuando se enlazó a un capturado. NUNCA sustituye a `merchant` (de él salen las
    /// categorías, los silenciados y las suscripciones); solo se muestra si el capturado no trae nombre útil.
    public var bankMerchant: String?
    /// true = no es gasto aunque mueva el saldo (compras y ventas de valores de Trade Republic): las sumas de gasto
    /// deben saltárselo.
    public var excludedFromSpending: Bool
    /// Cuándo enlazó el canal del banco a este capturado con su registro (nil = no se sabe o no se enlazó por ahí). El
    /// criterio de saldo lo compara con la consulta de la lectura; `importedAt` no sirve: también decide `isHistorical`.
    public var linkedAt: Date?

    /// Nombre para mostrar: el capturado, salvo que esté vacío o sea genérico.
    public var displayMerchant: String? { richerMerchant(captured: merchant, bank: bankMerchant) }

    /// Movimiento que ya existía de antes de importarse: no debe avisar ni contar como novedad.
    public var isHistorical: Bool { importedAt.map { date < $0.addingTimeInterval(-48 * 3600) } ?? false }

    public init(id: UUID = UUID(), bank: BankID, amountCents: Int, merchant: String?, kind: MovementKind, source: Source, date: Date,
                pairedAcrossSources: Bool = false, fingerprint: String? = nil, pairedFingerprint: String? = nil,
                isShop: Bool = false, note: String? = nil, flaggedNotMine: Bool = false,
                category: SpendingCategory? = nil, ownTransfer: Bool? = nil,
                bankRef: String? = nil, statementRef: String? = nil, bankStatus: BankStatus? = nil,
                importedAt: Date? = nil, dayOnly: Bool = false, bankMerchant: String? = nil,
                excludedFromSpending: Bool = false, linkedAt: Date? = nil) {
        self.id = id
        self.bank = bank
        self.amountCents = amountCents
        self.merchant = merchant
        self.kind = kind
        self.source = source
        self.date = date
        self.pairedAcrossSources = pairedAcrossSources
        self.fingerprint = fingerprint
        self.pairedFingerprint = pairedFingerprint
        self.isShop = isShop
        self.note = note
        self.flaggedNotMine = flaggedNotMine
        self.category = category
        self.ownTransfer = ownTransfer
        self.bankRef = bankRef
        self.statementRef = statementRef
        self.bankStatus = bankStatus
        self.importedAt = importedAt
        self.dayOnly = dayOnly
        self.bankMerchant = bankMerchant
        self.excludedFromSpending = excludedFromSpending
        self.linkedAt = linkedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, bank, amountCents, merchant, kind, source, date, pairedAcrossSources, fingerprint, pairedFingerprint, isShop
        case note, flaggedNotMine, category, ownTransfer
        case bankRef, statementRef, bankStatus, importedAt, dayOnly, bankMerchant, excludedFromSpending, linkedAt
    }

    /// Los libros guardados antes de estos campos no los traen: se leen con sus valores por defecto.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bank = try c.decode(BankID.self, forKey: .bank)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant)
        kind = try c.decode(MovementKind.self, forKey: .kind)
        source = try c.decode(Source.self, forKey: .source)
        date = try c.decode(Date.self, forKey: .date)
        pairedAcrossSources = try c.decodeIfPresent(Bool.self, forKey: .pairedAcrossSources) ?? false
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint)
        pairedFingerprint = try c.decodeIfPresent(String.self, forKey: .pairedFingerprint)
        isShop = try c.decodeIfPresent(Bool.self, forKey: .isShop) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
        flaggedNotMine = try c.decodeIfPresent(Bool.self, forKey: .flaggedNotMine) ?? false
        category = try c.decodeIfPresent(SpendingCategory.self, forKey: .category)
        ownTransfer = try c.decodeIfPresent(Bool.self, forKey: .ownTransfer)
        bankRef = try c.decodeIfPresent(String.self, forKey: .bankRef)
        statementRef = try c.decodeIfPresent(String.self, forKey: .statementRef)
        bankStatus = try c.decodeIfPresent(BankStatus.self, forKey: .bankStatus)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
        dayOnly = try c.decodeIfPresent(Bool.self, forKey: .dayOnly) ?? false
        bankMerchant = try c.decodeIfPresent(String.self, forKey: .bankMerchant)
        excludedFromSpending = try c.decodeIfPresent(Bool.self, forKey: .excludedFromSpending) ?? false
        linkedAt = try c.decodeIfPresent(Date.self, forKey: .linkedAt)
    }
}

/// Estado de un registro del banco: pendiente (retenido) o apuntado.
public enum BankStatus: String, Codable, Sendable { case booked, pending }

/// De dónde salió una lectura de saldo.
public enum BalanceOrigin: String, Codable, Sendable { case manual, notice, bank, statement }

public struct ManualBalance: Codable, Equatable, Sendable {
    public var cents: Int
    public var setAt: Date
    /// De dónde salió la lectura (a mano, aviso, API del banco o extracto).
    public var origin: BalanceOrigin
    /// Cuándo se consultó al banco para obtener esta lectura (puede ser posterior a `setAt`, la hora de referencia del
    /// saldo). nil = no se sabe: se usa `setAt`.
    public var fetchedAt: Date?
    /// true = el saldo lo comunicó el banco (aviso, API o extracto); false = puesto a mano.
    public var fromBank: Bool { origin != .manual }

    public init(cents: Int, setAt: Date, fromBank: Bool) {
        self.init(cents: cents, setAt: setAt, origin: fromBank ? .notice : .manual)
    }

    public init(cents: Int, setAt: Date, origin: BalanceOrigin, fetchedAt: Date? = nil) {
        self.cents = cents
        self.setAt = setAt
        self.origin = origin
        self.fetchedAt = fetchedAt
    }

    private enum CodingKeys: String, CodingKey { case cents, setAt, origin, fromBank, fetchedAt }

    /// Los libros anteriores solo traen `fromBank`: true era un aviso.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cents = try c.decode(Int.self, forKey: .cents)
        setAt = try c.decode(Date.self, forKey: .setAt)
        if let origin = try c.decodeIfPresent(BalanceOrigin.self, forKey: .origin) {
            self.origin = origin
        } else {
            origin = (try c.decodeIfPresent(Bool.self, forKey: .fromBank) ?? false) ? .notice : .manual
        }
        fetchedAt = try c.decodeIfPresent(Date.self, forKey: .fetchedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cents, forKey: .cents)
        try c.encode(setAt, forKey: .setAt)
        try c.encode(origin, forKey: .origin)
        try c.encode(fromBank, forKey: .fromBank)
        try c.encodeIfPresent(fetchedAt, forKey: .fetchedAt)
    }
}

public struct UnreadNotice: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var bank: BankID
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), bank: BankID, text: String, date: Date) {
        self.id = id
        self.bank = bank
        self.text = text
        self.date = date
    }
}

public struct LedgerState: Codable, Equatable, Sendable {
    public var balances: [BankID: ManualBalance]
    public var movements: [Movement]
    public var unread: [UnreadNotice]
    public var alertSettings: AlertSettings
    /// Comercios silenciados, con la clave de `normalizeMerchant`.
    public var mutedMerchants: Set<String>
    /// Categoría recordada por comercio (clave de `normalizeMerchant`).
    public var categoryOverrides: [String: SpendingCategory]
    public var budgets: Budgets
    /// Suscripciones que el dueño ocultó, con id `"<banco>|<clave del comercio>"`.
    public var dismissedSubscriptions: Set<String>
    // MARK: Datos del banco (Plan 2)
    /// Estado (sin secretos) de la conexión de cada banco.
    public var links: [BankID: BankLinkInfo]
    /// Periodos que cubren los extractos importados, por banco (R38): de la primera fila al último día completo antes de
    /// importarlo. Un día solo está cubierto dentro de uno de ellos; entre dos extractos no hay cobertura.
    public var statementCoverage: [BankID: [DateInterval]]

    public init(balances: [BankID: ManualBalance] = [:], movements: [Movement] = [], unread: [UnreadNotice] = [],
                alertSettings: AlertSettings = AlertSettings(), mutedMerchants: Set<String> = [],
                categoryOverrides: [String: SpendingCategory] = [:], budgets: Budgets = Budgets(),
                dismissedSubscriptions: Set<String> = [],
                links: [BankID: BankLinkInfo] = [:], statementCoverage: [BankID: [DateInterval]] = [:]) {
        self.balances = balances
        self.movements = movements
        self.unread = unread
        self.alertSettings = alertSettings
        self.mutedMerchants = mutedMerchants
        self.categoryOverrides = categoryOverrides
        self.budgets = budgets
        self.dismissedSubscriptions = dismissedSubscriptions
        self.links = links
        self.statementCoverage = statementCoverage
    }

    private enum CodingKeys: String, CodingKey { case balances, movements, unread, alertSettings, mutedMerchants, categoryOverrides, budgets, dismissedSubscriptions
        case links, statementCoverage
    }

    /// Los libros guardados antes de los avisos no traen ajustes ni silenciados: valores por defecto.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balances = try c.decode([BankID: ManualBalance].self, forKey: .balances)
        movements = try c.decode([Movement].self, forKey: .movements)
        unread = try c.decode([UnreadNotice].self, forKey: .unread)
        alertSettings = try c.decodeIfPresent(AlertSettings.self, forKey: .alertSettings) ?? AlertSettings()
        mutedMerchants = try c.decodeIfPresent(Set<String>.self, forKey: .mutedMerchants) ?? []
        categoryOverrides = try c.decodeIfPresent([String: SpendingCategory].self, forKey: .categoryOverrides) ?? [:]
        budgets = try c.decodeIfPresent(Budgets.self, forKey: .budgets) ?? Budgets()
        dismissedSubscriptions = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedSubscriptions) ?? []
        links = try c.decodeIfPresent([BankID: BankLinkInfo].self, forKey: .links) ?? [:]
        statementCoverage = try c.decodeIfPresent([BankID: [DateInterval]].self, forKey: .statementCoverage) ?? [:]
    }
}

public enum IngestInput: Sendable {
    case notification(bank: BankID, title: String?, subtitle: String?, body: String?)
    case wallet(bank: BankID, amount: String, merchant: String?)
}

public enum IngestOutcome: Equatable, Sendable {
    case stored(Movement)
    /// Un registro del banco que ya estaba en el libro se completó con este aviso o pago de Cartera.
    case merged(Movement)
    case duplicate
    case ignored
    case unread
}

/// Calendario de los días en la lógica de `ingest` (que no recibe calendario): gregoriano, Madrid.
let madridCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .gmt
    return c
}()

extension Movement.Source {
    /// Vino de la API del banco o de un extracto, no de un aviso ni de Cartera.
    var isBankSourced: Bool { self == .bank || self == .statement }
}

public struct Ledger: Sendable {
    public internal(set) var state: LedgerState

    /// Cartera y aviso del mismo banco con el mismo importe firmado dentro de esta ventana = el mismo pago.
    static let duplicateWindow: TimeInterval = 180
    /// El mismo texto de la misma fuente dentro de esta ventana = una reentrega, no otro pago.
    static let redeliveryWindow: TimeInterval = 60
    /// Lo que se guarda, como mucho, del texto de un aviso sin leer.
    static let unreadTextLimit = 500

    public init(state: LedgerState = LedgerState()) {
        self.state = state
    }

    public mutating func setBalance(_ bank: BankID, cents: Int, now: Date) {
        state.balances[bank] = ManualBalance(cents: cents, setAt: now, origin: .manual)
    }

    /// Adopta una lectura de saldo si no hay otra, si la actual es a mano (el banco siempre manda) o si no es más antigua.
    /// `fetchedAt`: cuándo se consultó al banco (la API); los avisos y extractos no lo pasan.
    @discardableResult
    public mutating func adoptBalance(_ bank: BankID, cents: Int, at: Date, origin: BalanceOrigin,
                                      fetchedAt: Date? = nil) -> Bool {
        if let current = state.balances[bank], current.origin != .manual, at < current.setAt { return false }
        state.balances[bank] = ManualBalance(cents: cents, setAt: at, origin: origin, fetchedAt: fetchedAt)
        return true
    }

    public mutating func setLink(_ bank: BankID, _ info: BankLinkInfo?) {
        state.links[bank] = info
    }

    public mutating func removeUnread(id: UUID) {
        state.unread.removeAll { $0.id == id }
    }

    public mutating func deleteMovement(id: UUID) {
        state.movements.removeAll { $0.id == id }
    }

    public mutating func setNote(_ note: String?, for id: UUID) {
        guard let i = state.movements.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        state.movements[i].note = trimmed.isEmpty ? nil : trimmed
    }

    public mutating func setFlaggedNotMine(_ flagged: Bool, for id: UUID) {
        guard let i = state.movements.firstIndex(where: { $0.id == id }) else { return }
        state.movements[i].flaggedNotMine = flagged
    }

    /// Pone (o quita, con nil) la categoría de un movimiento. Con `applyToMerchant` se recuerda para todo el
    /// comercio y se limpian las categorías sueltas de sus movimientos.
    public mutating func setCategory(_ category: SpendingCategory?, for id: UUID, applyToMerchant: Bool) {
        guard let i = state.movements.firstIndex(where: { $0.id == id }) else { return }
        let key = normalizeMerchant(state.movements[i].merchant ?? "")
        if applyToMerchant, !key.isEmpty {
            state.categoryOverrides[key] = category
            for j in state.movements.indices where normalizeMerchant(state.movements[j].merchant ?? "") == key {
                state.movements[j].category = nil
            }
        } else {
            state.movements[i].category = category
        }
    }

    public mutating func setOwnTransfer(_ value: Bool?, for id: UUID) {
        guard let i = state.movements.firstIndex(where: { $0.id == id }) else { return }
        state.movements[i].ownTransfer = value
    }

    /// Presupuesto mensual total; un importe de 0 o menos lo quita.
    public mutating func setMonthlyBudget(_ cents: Int?) {
        state.budgets.monthlyCents = cents.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Presupuesto mensual de una categoría; un importe de 0 o menos lo quita.
    public mutating func setBudget(_ cents: Int?, for category: SpendingCategory) {
        if let cents, cents > 0 { state.budgets.byCategory[category] = cents } else { state.budgets.byCategory[category] = nil }
    }

    /// Sustituye todo el libro por el de una copia. Los campos que dependen de este dispositivo (p. ej. las conexiones
    /// con bancos, ligadas al Llavero) NO se restauran: para excluir uno, añade una línea `restored.x = state.x` aquí.
    public mutating func restore(_ backup: LedgerState) {
        var restored = backup
        // La conexión con cada banco es de este aparato (su sesión vive en el Llavero): nunca sale de una copia. Se queda,
        // pero con el cursor de sincronización REBOBINADO (sin última consulta con éxito y sin historial cargado): la
        // siguiente sincronización vuelve a pedir todo el historial. Si no, lo ocurrido entre la fecha de la copia y el
        // cursor no se pediría nunca, y los capturados de la última semana de la copia se darían por «sin confirmar».
        // Se conservan el consentimiento, el problema, la espera y el registro de consultas (el límite diario sigue).
        restored.links = state.links.mapValues { link in
            var rewound = link
            rewound.lastSuccessAt = nil
            rewound.historyLoaded = false
            return rewound
        }
        state = restored
    }

    public mutating func setSubscriptionDismissed(_ dismissed: Bool, id: String) {
        if dismissed { state.dismissedSubscriptions.insert(id) } else { state.dismissedSubscriptions.remove(id) }
    }

    public mutating func setMuted(_ muted: Bool, merchant: String) {
        let key = normalizeMerchant(merchant)
        guard !key.isEmpty else { return }
        if muted { state.mutedMerchants.insert(key) } else { state.mutedMerchants.remove(key) }
    }

    public func isMuted(merchant: String?) -> Bool {
        guard let merchant else { return false }
        let key = normalizeMerchant(merchant)
        return !key.isEmpty && state.mutedMerchants.contains(key)
    }

    public mutating func updateAlertSettings(_ body: (inout AlertSettings) -> Void) {
        body(&state.alertSettings)
    }

    public mutating func ingest(_ input: IngestInput, now: Date) -> IngestOutcome {
        let bank: BankID
        let parsed: ParsedMovement
        let source: Movement.Source
        switch input {
        case let .notification(b, title, subtitle, body):
            bank = b
            source = .notification
            switch parseNotification(bank: b, title: title, subtitle: subtitle, body: body) {
            case .ignore:
                return .ignored
            case .unreadable:
                return storeUnread(bank: b, text: [title, subtitle, body].compactMap { $0 }.joined(separator: "\n"), now: now)
            case .movement(let m):
                parsed = m
            }
        case let .wallet(b, amount, merchant):
            bank = b
            source = .wallet
            guard let cents = parseAmountToCents(Substring(amount)) else {
                return storeUnread(bank: b, text: amount, now: now)
            }
            // Apple Pay con comercio: siempre una compra en una tienda.
            parsed = ParsedMovement(kind: .payment, amountCents: cents, merchant: merchant, merchantIsShop: !(merchant ?? "").isEmpty)
        }

        let signed = parsed.kind == .payment ? -parsed.amountCents : parsed.amountCents
        let fingerprint = ingestFingerprint(input)
        // También en un duplicado: el saldo que escribe el banco es más fiable que la estimación.
        if let reported = parsed.reportedBalanceCents {
            adoptBalance(bank, cents: reported, at: now, origin: .notice)
        }

        // 1. Reentrega: la misma fuente con el mismo texto normalizado en 60 s.
        let redelivered = state.movements.contains {
            $0.source == source && $0.fingerprint == fingerprint
                && abs($0.date.timeIntervalSince(now)) <= Self.redeliveryWindow
        }
        if redelivered { return .duplicate }

        // 2. El mismo pago visto por la otra fuente: cada movimiento se empareja una sola vez.
        let partner = state.movements.firstIndex {
            $0.bank == bank && $0.source != source && !$0.source.isBankSourced && !$0.pairedAcrossSources && $0.amountCents == signed
                && abs($0.date.timeIntervalSince(now)) <= Self.duplicateWindow
        }
        if let partner {
            state.movements[partner].pairedAcrossSources = true
            state.movements[partner].pairedFingerprint = fingerprint
            return .duplicate
        }

        // 3. Reentrega de un registro ya emparejado (llegó hasta 180 s después del original; su reentrega, 60 s más).
        let redeliveredPartner = state.movements.contains {
            $0.source != source && !$0.source.isBankSourced && $0.pairedFingerprint == fingerprint
                && abs($0.date.timeIntervalSince(now)) <= Self.duplicateWindow + Self.redeliveryWindow
        }
        if redeliveredPartner { return .duplicate }

        // 4. Un registro del banco (o de un extracto) del mismo pago que aún no se había visto por aviso: se completa
        // en lugar de duplicarlo. Gana el más cercano en el tiempo.
        // Solo filas del MISMO día de Madrid; las del día anterior solo si el aviso llega antes de las 03:00
        // (las fechas del banco suelen venir en UTC o ser el día de autorización).
        let nowDay = madridCalendar.startOfDay(for: now)
        let justAfterMidnight = madridCalendar.component(.hour, from: now) < 3
        let bankMatch = state.movements.indices.filter { i in
            let m = state.movements[i]
            guard m.source.isBankSourced, m.fingerprint == nil, m.bank == bank, m.amountCents == signed else { return false }
            let days = madridCalendar.dateComponents([.day], from: madridCalendar.startOfDay(for: m.date), to: nowDay).day ?? Int.max
            return days == 0 || (days == 1 && justAfterMidnight)
        }.min { abs(state.movements[$0].date.timeIntervalSince(now)) < abs(state.movements[$1].date.timeIntervalSince(now)) }
        if let i = bankMatch {
            state.movements[i].source = source
            state.movements[i].date = now
            state.movements[i].dayOnly = false
            state.movements[i].fingerprint = fingerprint
            // El nombre del banco pasa a su campo propio; `merchant` queda con el del aviso si es útil.
            let bankName = state.movements[i].merchant
            setMerchantKeepingCategory(richerMerchant(captured: parsed.merchant, bank: bankName), at: i)
            state.movements[i].bankMerchant = bankName
            state.movements[i].isShop = state.movements[i].isShop || parsed.merchantIsShop
            return .merged(state.movements[i])
        }

        // date == now y balance solo suma date > setAt: no se cuenta dos veces.
        let movement = Movement(bank: bank, amountCents: signed, merchant: parsed.merchant, kind: parsed.kind, source: source,
                                date: now, fingerprint: fingerprint, isShop: parsed.merchantIsShop)
        state.movements.append(movement)
        return .stored(movement)
    }

    /// Cambia el comercio de un movimiento (un renombrado al conciliar, un aviso tardío fusionado). Si la clave del
    /// comercio antiguo tenía una categoría «para todo el comercio» y la nueva no tiene ninguna, la categoría pasa al propio
    /// movimiento para no perderla con el cambio de clave.
    mutating func setMerchantKeepingCategory(_ merchant: String?, at i: Int) {
        let oldKey = normalizeMerchant(state.movements[i].merchant ?? "")
        let newKey = normalizeMerchant(merchant ?? "")
        if oldKey != newKey, !oldKey.isEmpty, state.movements[i].category == nil,
           let inherited = state.categoryOverrides[oldKey], state.categoryOverrides[newKey] == nil {
            state.movements[i].category = inherited
        }
        state.movements[i].merchant = merchant
    }

    /// Un aviso sin leer idéntico dentro de la ventana de reentrega no se guarda dos veces.
    private mutating func storeUnread(bank: BankID, text raw: String, now: Date) -> IngestOutcome {
        let text = String(raw.prefix(Self.unreadTextLimit))
        let repeated = state.unread.contains {
            $0.bank == bank && $0.text == text && abs($0.date.timeIntervalSince(now)) <= Self.redeliveryWindow
        }
        if repeated { return .duplicate }
        state.unread.append(UnreadNotice(bank: bank, text: text, date: now))
        return .unread
    }

    public func balance(_ bank: BankID) -> (cents: Int, estimated: Bool)? {
        guard let base = state.balances[bank] else { return nil }
        let later = state.movements.filter { $0.bank == bank && Self.countsTowardBalance($0, base: base) }
        return (base.cents + later.reduce(0) { $0 + $1.amountCents }, !(base.origin != .manual && later.isEmpty))
    }

    /// El ÚNICO criterio de qué movimientos se suman sobre una lectura de saldo (lo usan `balance` y "Te quedaban"):
    /// posteriores a la lectura y capturados (no los del banco: su saldo ya los incluye). Un capturado enlazado a un
    /// registro del banco o de un extracto cuenta solo si su hora precisa es posterior a la lectura Y su registro no
    /// se conocía ya cuando se tomó la lectura (`linkedAt ?? importedAt` nil o posterior a la CONSULTA, `fetchedAt ?? setAt`, no a la
    /// hora de referencia del saldo, que puede ser anterior): un aviso tardío fusionado en una fila que el banco ya
    /// había dado está dentro de ese saldo. Los de extracto solo cuentan sobre un saldo puesto a mano.
    public static func countsTowardBalance(_ m: Movement, base: ManualBalance) -> Bool {
        guard m.date > base.setAt, isBalanceEligible(m, origin: base.origin) else { return false }
        // Un capturado enlazado por la misma consulta que la lectura (`linkedAt`) se trata como un aviso tardío fusionado en
        // una fila ya conocida: la lectura ya lo incluye.
        if isLinked(m), let known = m.linkedAt ?? m.importedAt, known <= (base.fetchedAt ?? base.setAt) { return false }
        return true
    }

    /// Capturado (o fusionado) enlazado a un registro del banco o a una fila de extracto. Las filas del propio banco o
    /// extracto llevan su clave por definición: no son "enlazadas".
    private static func isLinked(_ m: Movement) -> Bool {
        !m.source.isBankSourced && (m.bankRef != nil || m.statementRef != nil)
    }

    /// La parte del criterio que no mira la fecha. Un enlazado con hora precisa es elegible: solo cuenta si es
    /// posterior a la lectura (lo exige `countsTowardBalance`). Una fila de solo día nunca tiene hora real, y sobre un
    /// saldo de extracto (con hora de solo día) un capturado enlazado a una fila del extracto ya está en ese saldo.
    public static func isBalanceEligible(_ m: Movement, origin: BalanceOrigin) -> Bool {
        guard m.source != .bank, m.source != .statement || origin == .manual else { return false }
        guard isLinked(m) else { return true }
        if m.dayOnly { return false }
        if m.statementRef != nil && origin == .statement { return false }
        return true
    }

    public func total() -> Int? {
        let known = BankID.allCases.compactMap { balance($0)?.cents }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}

/// Huella estable (FNV-1a de 64 bits, en hexadecimal) del texto de entrada normalizado:
/// sin mayúsculas ni tildes, con espacios y saltos de línea colapsados.
/// No es criptográfica: solo reconoce el mismo aviso repetido sin guardar su texto.
func ingestFingerprint(_ input: IngestInput) -> String {
    let key: String
    switch input {
    case let .notification(bank, title, subtitle, body):
        key = "\(bank.rawValue)|n|" + normalizedForFingerprint([title, subtitle, body].compactMap { $0 }.joined(separator: " "))
    case let .wallet(bank, amount, merchant):
        key = "\(bank.rawValue)|w|" + normalizedForFingerprint(amount) + "|" + normalizedForFingerprint(merchant ?? "")
    }
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in key.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: 16 - hex.count) + hex
}

private func normalizedForFingerprint(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}
