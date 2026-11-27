import Foundation

/// Un destinatario guardado. Sensible: vive solo en el llavero (nunca en el libro, copias ni registros).
public struct Payee: Codable, Equatable, Sendable, Identifiable, CustomStringConvertible, CustomDebugStringConvertible {
    public var id: UUID
    public var name: String
    public var iban: String?
    public var phone: String?

    /// Nunca el nombre, el IBAN ni el teléfono: si alguien lo imprime por error, no sale nada.
    public var description: String { "Payee(•••)" }
    public var debugDescription: String { "Payee(•••)" }

    public init(id: UUID = UUID(), name: String, iban: String? = nil, phone: String? = nil) {
        self.id = id
        self.name = name
        self.iban = iban
        self.phone = phone
    }
}

/// IBAN propios, saldo mínimo a respetar por banco y destinatarios. Solo para el llavero:
/// no forma parte de `LedgerState` ni de ninguna copia de seguridad.
public struct AccountBook: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public var ibans: [BankID: String]
    /// Céntimos que no se quieren tocar en cada banco.
    public var floors: [BankID: Int]
    public var payees: [Payee]
    /// Bancos cuyo IBAN rellenado borró a propósito el dueño: no se vuelven a rellenar solos.
    /// Guarda únicamente el identificador del banco, nunca ningún IBAN ni fragmento.
    public var autoIBANDismissed: Set<BankID>

    /// Sin IBAN, mínimos ni destinatarios en la salida.
    public var description: String { "AccountBook(•••)" }
    public var debugDescription: String { "AccountBook(•••)" }

    public init() {
        ibans = [:]
        floors = [:]
        payees = []
        autoIBANDismissed = []
    }

    private enum CodingKeys: String, CodingKey { case ibans, floors, payees, autoIBANDismissed }

    /// Tolerante: lo que falte se lee vacío (compatible con libretas antiguas sin `autoIBANDismissed`).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ibans = try c.decodeIfPresent([BankID: String].self, forKey: .ibans) ?? [:]
        floors = try c.decodeIfPresent([BankID: Int].self, forKey: .floors) ?? [:]
        payees = try c.decodeIfPresent([Payee].self, forKey: .payees) ?? []
        autoIBANDismissed = try c.decodeIfPresent(Set<BankID>.self, forKey: .autoIBANDismissed) ?? []
    }

    /// Omite `autoIBANDismissed` cuando está vacío para mantener compatibilidad total en JSON.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ibans, forKey: .ibans)
        try c.encode(floors, forKey: .floors)
        try c.encode(payees, forKey: .payees)
        if !autoIBANDismissed.isEmpty {
            let sorted = autoIBANDismissed.sorted { $0.rawValue < $1.rawValue }
            try c.encode(sorted, forKey: .autoIBANDismissed)
        }
    }

    /// Guarda o borra el IBAN propio de un banco (acción del dueño).
    /// Si el dueño borra un IBAN existente de un banco conectable, recuerda el borrado en `autoIBANDismissed`
    /// sin guardar el IBAN; si escribe un IBAN no vacío, limpia esa marca para ese banco.
    public mutating func setIBAN(_ raw: String?, for bank: BankID) {
        let clean = raw.map(normalizeIBAN) ?? ""
        if clean.isEmpty {
            let hadIBAN = !(ibans[bank]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ibans.removeValue(forKey: bank)
            if hadIBAN && bank != .tr {
                autoIBANDismissed.insert(bank)
            }
        } else {
            ibans[bank] = clean
            autoIBANDismissed.remove(bank)
        }
    }

    /// Rellena el IBAN del banco solo si está vacío, el dueño no lo borró antes, el banco admite conexión
    /// (nunca Trade Republic) y el IBAN recibido supera la validación estricta de país, formato y dígitos de control.
    /// Nunca pisa un IBAN que el dueño ya haya guardado. Devuelve `true` solo si el cuaderno cambia.
    @discardableResult
    public mutating func fillIBANIfEmpty(_ raw: String, for bank: BankID) -> Bool {
        guard bank != .tr else { return false }
        guard !autoIBANDismissed.contains(bank) else { return false }
        let existing = ibans[bank]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return false }
        guard let clean = validatedBankIBAN(raw) else { return false }
        ibans[bank] = clean
        return true
    }
}

/// Iniciales de un contacto tomadas solo de letras (sin signos ni dígitos); nil si no hay letras (U63).
public func contactInitials(for name: String) -> String? {
    let words = name.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
    guard let firstWord = words.first, let a = firstWord.first else { return nil }
    if words.count >= 2, let b = words[1].first {
        return "\(a)\(b)".uppercased()
    }
    return String(a).uppercased()
}
