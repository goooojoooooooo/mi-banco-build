import Foundation

public struct Movement: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable { case notification, wallet }

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

    public init(id: UUID = UUID(), bank: BankID, amountCents: Int, merchant: String?, kind: MovementKind, source: Source, date: Date,
                pairedAcrossSources: Bool = false, fingerprint: String? = nil, pairedFingerprint: String? = nil,
                isShop: Bool = false, note: String? = nil, flaggedNotMine: Bool = false,
                category: SpendingCategory? = nil) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, bank, amountCents, merchant, kind, source, date, pairedAcrossSources, fingerprint, pairedFingerprint, isShop
        case note, flaggedNotMine, category
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
    }
}

public struct ManualBalance: Codable, Equatable, Sendable {
    public var cents: Int
    public var setAt: Date
    /// true = el saldo lo comunicó el banco en un aviso; false = puesto a mano.
    public var fromBank: Bool

    public init(cents: Int, setAt: Date, fromBank: Bool) {
        self.cents = cents
        self.setAt = setAt
        self.fromBank = fromBank
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

    public init(balances: [BankID: ManualBalance] = [:], movements: [Movement] = [], unread: [UnreadNotice] = [],
                alertSettings: AlertSettings = AlertSettings(), mutedMerchants: Set<String> = [],
                categoryOverrides: [String: SpendingCategory] = [:]) {
        self.balances = balances
        self.movements = movements
        self.unread = unread
        self.alertSettings = alertSettings
        self.mutedMerchants = mutedMerchants
        self.categoryOverrides = categoryOverrides
    }

    private enum CodingKeys: String, CodingKey { case balances, movements, unread, alertSettings, mutedMerchants, categoryOverrides }

    /// Los libros guardados antes de los avisos no traen ajustes ni silenciados: valores por defecto.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balances = try c.decode([BankID: ManualBalance].self, forKey: .balances)
        movements = try c.decode([Movement].self, forKey: .movements)
        unread = try c.decode([UnreadNotice].self, forKey: .unread)
        alertSettings = try c.decodeIfPresent(AlertSettings.self, forKey: .alertSettings) ?? AlertSettings()
        mutedMerchants = try c.decodeIfPresent(Set<String>.self, forKey: .mutedMerchants) ?? []
        categoryOverrides = try c.decodeIfPresent([String: SpendingCategory].self, forKey: .categoryOverrides) ?? [:]
    }
}

public enum IngestInput: Sendable {
    case notification(bank: BankID, title: String?, subtitle: String?, body: String?)
    case wallet(bank: BankID, amount: String, merchant: String?)
}

public enum IngestOutcome: Equatable, Sendable {
    case stored(Movement)
    case duplicate
    case ignored
    case unread
}

public struct Ledger: Sendable {
    public private(set) var state: LedgerState

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
        state.balances[bank] = ManualBalance(cents: cents, setAt: now, fromBank: false)
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
            state.balances[bank] = ManualBalance(cents: reported, setAt: now, fromBank: true)
        }

        // 1. Reentrega: la misma fuente con el mismo texto normalizado en 60 s.
        let redelivered = state.movements.contains {
            $0.source == source && $0.fingerprint == fingerprint
                && abs($0.date.timeIntervalSince(now)) <= Self.redeliveryWindow
        }
        if redelivered { return .duplicate }

        // 2. El mismo pago visto por la otra fuente: cada movimiento se empareja una sola vez.
        let partner = state.movements.firstIndex {
            $0.bank == bank && $0.source != source && !$0.pairedAcrossSources && $0.amountCents == signed
                && abs($0.date.timeIntervalSince(now)) <= Self.duplicateWindow
        }
        if let partner {
            state.movements[partner].pairedAcrossSources = true
            state.movements[partner].pairedFingerprint = fingerprint
            return .duplicate
        }

        // 3. Reentrega de un registro ya emparejado (llegó hasta 180 s después del original; su reentrega, 60 s más).
        let redeliveredPartner = state.movements.contains {
            $0.source != source && $0.pairedFingerprint == fingerprint
                && abs($0.date.timeIntervalSince(now)) <= Self.duplicateWindow + Self.redeliveryWindow
        }
        if redeliveredPartner { return .duplicate }

        // date == now y balance solo suma date > setAt: no se cuenta dos veces.
        let movement = Movement(bank: bank, amountCents: signed, merchant: parsed.merchant, kind: parsed.kind, source: source,
                                date: now, fingerprint: fingerprint, isShop: parsed.merchantIsShop)
        state.movements.append(movement)
        return .stored(movement)
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
        let later = state.movements.filter { $0.bank == bank && $0.date > base.setAt }
        return (base.cents + later.reduce(0) { $0 + $1.amountCents }, !(base.fromBank && later.isEmpty))
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
