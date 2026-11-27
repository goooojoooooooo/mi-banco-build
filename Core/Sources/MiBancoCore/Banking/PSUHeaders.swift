import Foundation

/// Lista cerrada de cabeceras PSU que acepta Enable Banking (con su nombre canónico).
public let allowedPSUHeaderNames: [String] = [
    "Psu-Ip-Address",
    "Psu-User-Agent",
    "Psu-Referer",
    "Psu-Accept",
    "Psu-Accept-Charset",
    "Psu-Accept-Encoding",
    "Psu-Accept-language",
    "Psu-Geo-Location",
]

private let canonicalPSUHeaderMap: [String: String] = Dictionary(
    uniqueKeysWithValues: allowedPSUHeaderNames.map { ($0.lowercased(), $0) }
)

/// Sanea un valor de cabecera HTTP: rechaza caracteres de control (incluidos CR, LF, NUL, TAB y C1) y valores vacíos.
private func sanitizePSUHeaderValue(_ raw: String) -> String? {
    for scalar in raw.unicodeScalars {
        let v = scalar.value
        if v < 0x20 || (v >= 0x7F && v <= 0x9F) || v == 0x2028 || v == 0x2029 {
            return nil
        }
    }
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

/// Filtra y normaliza un diccionario de cabeceras PSU contra la lista oficial de Enable Banking.
/// Nunca deja pasar cabeceras fuera de la lista (como `Authorization`, `Accept` o `Content-Type`) ni valores con control/CR/LF.
public func sanitizePSUHeaders(_ raw: [String: String]) -> [String: String] {
    let ordered = raw.sorted { lhs, rhs in
        let lhsCanonical = canonicalPSUHeaderMap[lhs.key.lowercased()] == lhs.key
        let rhsCanonical = canonicalPSUHeaderMap[rhs.key.lowercased()] == rhs.key
        if lhsCanonical != rhsCanonical { return lhsCanonical }
        return lhs.key < rhs.key
    }
    var out: [String: String] = [:]
    for (rawName, rawValue) in ordered {
        guard let canonical = canonicalPSUHeaderMap[rawName.lowercased()],
              out[canonical] == nil,
              let clean = sanitizePSUHeaderValue(rawValue) else { continue }
        out[canonical] = clean
    }
    return out
}

/// Regla pura de cabeceras PSU (Enable Banking, «todas las requeridas o ninguna»):
/// - En segundo plano (`.background`) devuelve siempre `nil`.
/// - Solo acepta cabeceras de la lista oficial, sin distinguir mayúsculas/minúsculas, y filtra valores vacíos o con control/CR/LF.
/// - Si `required` pide alguna cabecera que no está disponible (p. ej. `Psu-Ip-Address`) o no está en la lista oficial, devuelve `nil`.
/// - Si el usuario está presente, todas las requeridas están cubiertas y hay al menos una cabecera válida, devuelve los nombres canónicos.
public func psuHeaders(
    for trigger: SyncTrigger,
    required: [String]?,
    available: [String: String]
) -> [String: String]? {
    guard trigger != .background else { return nil }
    let sanitized = sanitizePSUHeaders(available)
    guard !sanitized.isEmpty else { return nil }
    if let required {
        for rawName in required {
            let trimmed = rawName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let canonical = canonicalPSUHeaderMap[trimmed.lowercased()],
                  sanitized[canonical] != nil else {
                return nil
            }
        }
    }
    return sanitized
}

/// Construye las cabeceras PSU rellenables solo con datos locales no identificativos del iPhone
/// (sin modelo de hardware, sin UDID, sin nombre del teléfono y sin consultar ningún servicio externo).
public func buildLocalPSUHeaders(
    appName: String,
    appVersion: String,
    osVersion: String,
    preferredLanguage: String?
) -> [String: String] {
    var headers: [String: String] = [:]
    if let name = sanitizeUserAgentToken(appName),
       let appVer = sanitizeUserAgentToken(appVersion),
       let osVer = sanitizeUserAgentToken(osVersion) {
        headers["Psu-User-Agent"] = "\(name)/\(appVer) (iOS \(osVer))"
    }
    if let rawLang = preferredLanguage, let cleanLang = sanitizeAcceptLanguageTag(rawLang) {
        headers["Psu-Accept-language"] = cleanLang
    }
    return headers
}

private func sanitizeUserAgentToken(_ raw: String) -> String? {
    guard let clean = sanitizePSUHeaderValue(raw) else { return nil }
    let allowed = clean.unicodeScalars.allSatisfy { scalar in
        let v = scalar.value
        return (v >= 0x30 && v <= 0x39) // 0-9
            || (v >= 0x41 && v <= 0x5A) // A-Z
            || (v >= 0x61 && v <= 0x7A) // a-z
            || v == 0x2E || v == 0x2D || v == 0x5F // . - _
    }
    return allowed ? clean : nil
}

private func sanitizeAcceptLanguageTag(_ raw: String) -> String? {
    guard let clean = sanitizePSUHeaderValue(raw) else { return nil }
    let normalized = clean.replacingOccurrences(of: "_", with: "-")
    let allowed = normalized.unicodeScalars.allSatisfy { scalar in
        let v = scalar.value
        return (v >= 0x30 && v <= 0x39) // 0-9
            || (v >= 0x41 && v <= 0x5A) // A-Z
            || (v >= 0x61 && v <= 0x7A) // a-z
            || v == 0x2D // -
    }
    return allowed && !normalized.isEmpty ? normalized : nil
}

/// ¿Rechazó Enable Banking la petición por cabeceras PSU (422 `PSU_HEADER_NOT_PROVIDED` / `PSU_HEADER_INVALID`)?
public func isPSUHeaderRejection(_ error: Error) -> Bool {
    guard case let .api(_, code) = error as? BankingClientError, let code else { return false }
    return code == "PSU_HEADER_NOT_PROVIDED" || code == "PSU_HEADER_INVALID"
}

/// Busca el banco de una sesión guardada dentro de la lista devuelta por `GET /aspsps`.
/// Prefiere coincidencia exacta (sin distinguir mayúsculas) por nombre y país; si no, por nombre o `BankID`.
public func findASPSP(
    name: String,
    country: String,
    bank: BankID,
    in list: [EBASPSP]
) -> EBASPSP? {
    let targetName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let targetCountry = country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if let exact = list.first(where: {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetName
            && $0.country.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == targetCountry
    }) {
        return exact
    }
    if let byName = list.first(where: {
        $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == targetName
    }) {
        return byName
    }
    return matchASPSP(for: bank, in: list)
}

/// Texto seguro de diagnóstico para las cabeceras PSU requeridas de un banco:
/// solo nombres de cabecera HTTP (nunca valores, tokens, claves ni IBAN).
public func psuHeadersDiagnosticValue(_ required: [String]?) -> String {
    guard let required else { return "pendiente de comprobar" }
    var names: [String] = []
    var seen = Set<String>()
    for raw in required {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isSafeHTTPHeaderName(trimmed) else { continue }
        let display = canonicalPSUHeaderMap[trimmed.lowercased()] ?? trimmed
        if seen.insert(display.lowercased()).inserted {
            names.append(display)
        }
    }
    return names.isEmpty ? "ninguna" : names.joined(separator: ", ")
}

/// Línea de diagnóstico de Ajustes para los bancos conectados (solo nombres de cabeceras requeridas).
/// Devuelve `nil` si no hay ningún banco conectado.
public func psuHeadersDiagnosticsLine(
    connectedBanks: [BankID],
    requiredByBank: [BankID: [String]]
) -> String? {
    guard !connectedBanks.isEmpty else { return nil }
    let parts = connectedBanks.map { bank in
        "\(bank.displayName) \(psuHeadersDiagnosticValue(requiredByBank[bank]))"
    }
    return "Cabeceras PSU: \(parts.joined(separator: " · "))"
}

private func isSafeHTTPHeaderName(_ name: String) -> Bool {
    name.unicodeScalars.allSatisfy { scalar in
        let v = scalar.value
        return (v >= 0x30 && v <= 0x39) // 0-9
            || (v >= 0x41 && v <= 0x5A) // A-Z
            || (v >= 0x61 && v <= 0x7A) // a-z
            || v == 0x2D // -
    }
}
