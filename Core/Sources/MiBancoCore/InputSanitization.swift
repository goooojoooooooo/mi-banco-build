import Foundation

/// Topes defensivos para textos recibidos desde Atajos/App Intents y comercios guardados en el libro (SEC-11).
public enum InputLimits {
    public static let noticeFieldMaxLength = 2_000
    public static let walletAmountMaxLength = 64
    public static let merchantMaxLength = 120
}

/// Limpia un campo multilínea de aviso: elimina caracteres de control y formato Unicode (p. ej. anulaciones bidi)
/// conservando saltos de línea, tabuladores y espacios duros (`\u{00A0}`, `\u{202F}`), y recorta a `maxLength`.
public func sanitizeNoticeField(_ raw: String?, maxLength: Int = InputLimits.noticeFieldMaxLength) -> String? {
    guard let raw else { return nil }
    return sanitizeScalars(raw, allowNewlines: true, maxLength: maxLength)
}

/// Limpia el texto de importe recibido en «Registrar pago con Cartera»: sin controles ni formato, recortado a `maxLength`.
public func sanitizeWalletAmount(_ raw: String, maxLength: Int = InputLimits.walletAmountMaxLength) -> String {
    sanitizeSingleLine(raw, maxLength: maxLength)
}

/// Limpia y acota el nombre de comercio antes de guardarlo en el libro: una sola línea, sin caracteres de control
/// ni de formato Unicode, espacios colapsados y como mucho `maxLength` caracteres (`nil` si queda vacío).
public func sanitizeMerchant(_ raw: String?, maxLength: Int = InputLimits.merchantMaxLength) -> String? {
    guard let raw else { return nil }
    let cleaned = sanitizeSingleLine(raw, maxLength: maxLength)
    return cleaned.isEmpty ? nil : cleaned
}

/// Sanea todos los campos de un `IngestInput` antes de analizarlos o guardarlos.
public func sanitizeIngestInput(_ input: IngestInput) -> IngestInput {
    switch input {
    case let .notification(bank, title, subtitle, body):
        return .notification(
            bank: bank,
            title: sanitizeNoticeField(title),
            subtitle: sanitizeNoticeField(subtitle),
            body: sanitizeNoticeField(body)
        )
    case let .wallet(bank, amount, merchant):
        return .wallet(
            bank: bank,
            amount: sanitizeWalletAmount(amount),
            merchant: sanitizeMerchant(merchant)
        )
    }
}

private func sanitizeSingleLine(_ raw: String, maxLength: Int) -> String {
    let cleaned = sanitizeScalars(raw, allowNewlines: false, maxLength: maxLength * 2)
    let collapsed = cleaned.split(whereSeparator: { $0 == " " }).joined(separator: " ")
    let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= maxLength { return trimmed }
    return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func sanitizeScalars(_ raw: String, allowNewlines: Bool, maxLength: Int) -> String {
    guard maxLength > 0 else { return "" }
    var out = String.UnicodeScalarView()
    var count = 0
    var previousWasCR = false
    for scalar in raw.unicodeScalars {
        if count >= maxLength { break }
        if scalar == "\r" {
            previousWasCR = true
            out.append(allowNewlines ? "\n" : " ")
            count += 1
            continue
        }
        if scalar == "\n" {
            if previousWasCR {
                previousWasCR = false
                continue
            }
            out.append(allowNewlines ? "\n" : " ")
            count += 1
            continue
        }
        previousWasCR = false
        if scalar == "\t" {
            out.append(allowNewlines ? "\t" : " ")
            count += 1
            continue
        }
        let category = scalar.properties.generalCategory
        if category == .control || category == .format {
            continue
        }
        out.append(scalar)
        count += 1
    }
    return String(out)
}
