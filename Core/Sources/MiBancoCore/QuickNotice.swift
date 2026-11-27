import Foundation

/// Topes defensivos del aviso rápido recibido por Atajos (SEC-11).
/// Nota de unificación: cuando se una `plan-7-seguridad`, podrá delegar el saneado en `InputSanitization.swift`
/// manteniendo estos mismos límites.
public enum QuickNoticeLimits {
    /// Tope del texto entero recibido en «Pasar aviso a Onyx».
    public static let rawMaxLength = 4_000
    /// Tope de cada campo tras repartir título y cuerpo (igual que `noticeFieldMaxLength` en SEC-11).
    public static let fieldMaxLength = 2_000
}

/// Sanea el texto entero de una notificación al estilo SEC-11: normaliza `\r\n`/`\r` a `\n`, conserva `\n`, `\t`,
/// espacios duros (`\u{00A0}`, `\u{202F}`) y `U+200D` (ZWJ, para no partir emojis compuestos), elimina escalares
/// `.control` y `.format` (incluidos anuladores bidi `U+202E`, BOM y ZWSP) y recorta a `maxLength` escalares.
public func sanitizeQuickNoticeText(_ raw: String, maxLength: Int = QuickNoticeLimits.rawMaxLength) -> String {
    guard maxLength > 0 else { return "" }
    var out = String.UnicodeScalarView()
    var count = 0
    var previousWasCR = false
    for scalar in raw.unicodeScalars {
        if count >= maxLength { break }
        if scalar == "\r" {
            previousWasCR = true
            out.append("\n")
            count += 1
            continue
        }
        if scalar == "\n" {
            if previousWasCR {
                previousWasCR = false
                continue
            }
            out.append("\n")
            count += 1
            continue
        }
        previousWasCR = false
        if scalar == "\t" {
            out.append("\t")
            count += 1
            continue
        }
        let category = scalar.properties.generalCategory
        // Conserva U+200D (ZWJ) para no partir emojis compuestos; elimina controles y demás formato (bidi, BOM, ZWSP).
        if category == .control || (category == .format && scalar.value != 0x200D) {
            continue
        }
        out.append(scalar)
        count += 1
    }
    return String(out)
}

/// Deduce el banco de un aviso recibido en bloque:
/// 1. Cabecera explícita de la app en la primera línea (o prefijo `Banco: ...`, `Banco · ...`, `App: Banco`) o pie exacto en la última línea.
/// 2. Mención explícita del banco fuera de una referencia a contraparte («a imagin», «de Revolut», «to ...», «from ...»).
/// 3. Patrones propios de Revolut (`Paid €… at …`, `Spent today`, `RevPoints`; una línea de saldo disponible SOLA no vale)
///    o de Trade Republic (`Saveback`, `Round up`, `Card payment`).
/// Si no puede deducirse de forma fiable o hay señales enfrentadas, devuelve `nil` sin adivinar.
public func detectQuickNoticeBank(_ raw: String) -> BankID? {
    let clean = sanitizeQuickNoticeText(raw)
    let lines = splitQuickLines(clean)
    guard !lines.isEmpty else { return nil }
    let (headerBank, contentLines) = extractBankHeader(from: lines)
    if let headerBank { return headerBank }
    return detectBankFromContent(contentLines)
}

/// Convierte el texto entero de una notificación (variable «Notificación» de Atajos) en un `IngestInput.notification`
/// listo para `IngestRunner.run(...)` y `Ledger.ingest(...)`.
/// Si el banco no se puede deducir devuelve `.unattributedNotice` (se guarda como aviso sin leer, nunca se tira en silencio),
/// salvo que el lector lo ignore (código, aprobación, rechazo o sin importe). `nil` si el texto queda vacío tras sanearlo.
public func parseQuickNotice(_ raw: String) -> IngestInput? {
    let clean = sanitizeQuickNoticeText(raw)
    let lines = splitQuickLines(clean)
    guard !lines.isEmpty else { return nil }

    let (headerBank, contentLines) = extractBankHeader(from: lines)
    guard !contentLines.isEmpty else { return nil }
    guard let bank = headerBank ?? detectBankFromContent(contentLines) else {
        return unattributedQuickNotice(contentLines)
    }

    let rawTitle: String?
    let rawBody: String
    if contentLines.count == 1 || firstAmount(in: contentLines[0]) != nil {
        rawTitle = nil
        rawBody = contentLines.joined(separator: "\n")
    } else {
        rawTitle = contentLines[0]
        rawBody = contentLines.dropFirst().joined(separator: "\n")
    }

    let title = rawTitle.map { capQuickScalars($0, maxLength: QuickNoticeLimits.fieldMaxLength) }
        .flatMap { isBlankQuickText($0) ? nil : $0 }
    let body = capQuickScalars(rawBody, maxLength: QuickNoticeLimits.fieldMaxLength)
    guard !isBlankQuickText(body) else { return nil }
    return .notification(bank: bank, title: title, subtitle: nil, body: body)
}

// MARK: Helpers internos

private func quickFold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

private func isBlankQuickText(_ s: String) -> Bool {
    s.unicodeScalars.allSatisfy { scalar in
        scalar.value == 0x200D || scalar.properties.isWhitespace
    }
}

private func splitQuickLines(_ s: String) -> [String] {
    s.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !isBlankQuickText($0) }
}

private func capQuickScalars(_ s: String, maxLength: Int) -> String {
    guard maxLength > 0 else { return "" }
    if s.unicodeScalars.count <= maxLength { return s }
    return String(String.UnicodeScalarView(s.unicodeScalars.prefix(maxLength)))
}

private let bankAliases: [(alias: String, bank: BankID)] = [
    ("trade republic", .tr),
    ("traderepublic", .tr),
    ("imaginbank", .ima),
    ("revolut", .rev),
    ("imagin", .ima),
]

private let headerSeparators: Set<Character> = [":", "-", "—", "–", "·", "|"]

private func exactBankName(_ raw: String) -> BankID? {
    let f = quickFold(raw).trimmingCharacters(in: .whitespaces)
    return bankAliases.first(where: { $0.alias == f })?.bank
}

private func extractBankHeader(from lines: [String]) -> (bank: BankID?, content: [String]) {
    guard let first = lines.first else { return (nil, []) }

    // 1a. Cabecera con etiqueta («App: Revolut», «Aplicación: Trade Republic»).
    for label in ["app:", "aplicacion:", "de:", "from:"] {
        if let range = first.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) {
            let value = String(first[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if let bank = exactBankName(value) {
                return (bank, Array(lines.dropFirst()))
            }
        }
    }

    // 1b. Primera línea con el nombre exacto del banco o prefijo «Banco: ...» / «Banco · ...».
    for (alias, bank) in bankAliases {
        guard let range = first.range(of: alias, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else {
            continue
        }
        let rawAfter = first[range.upperBound...]
        let after = rawAfter.trimmingCharacters(in: .whitespaces)
        if after.isEmpty {
            return (bank, Array(lines.dropFirst()))
        }
        let separated = rawAfter.first == ":" || (rawAfter.first?.isWhitespace == true)
        if separated, let sep = after.first, headerSeparators.contains(sep) {
            let remainder = String(after.dropFirst()).trimmingCharacters(in: .whitespaces)
            var rest = Array(lines.dropFirst())
            if !isBlankQuickText(remainder) {
                rest.insert(remainder, at: 0)
            }
            return (bank, rest)
        }
    }

    // 1c. Pie exacto en la última línea (p. ej. si iOS sitúa el nombre de la app al final).
    if lines.count >= 2, let footerBank = exactBankName(lines[lines.count - 1]) {
        return (footerBank, Array(lines.dropLast()))
    }

    return (nil, lines)
}

/// Preposiciones que introducen al banco CONTRAPARTE en un traspaso («a imagin», «de Revolut»), no al emisor.
private let counterpartyPrepositions: Set<String> = ["a", "de", "para", "desde", "hacia", "to", "from"]

private func detectBankFromContent(_ lines: [String]) -> BankID? {
    let foldedLines = lines.map(quickFold)

    // 2. Mención explícita de la marca fuera de una contraparte.
    var mentioned = Set<BankID>()
    for line in foldedLines {
        let tokens = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var i = 0
        while i < tokens.count {
            let prev = i > 0 ? tokens[i - 1] : nil
            let isCounterparty = prev.map { counterpartyPrepositions.contains($0) } ?? false
            if tokens[i] == "trade", i + 1 < tokens.count, tokens[i + 1] == "republic" {
                if !isCounterparty { mentioned.insert(.tr) }
                i += 2
                continue
            }
            if tokens[i] == "traderepublic" {
                if !isCounterparty { mentioned.insert(.tr) }
            } else if tokens[i] == "revolut" {
                if !isCounterparty { mentioned.insert(.rev) }
            } else if tokens[i] == "imagin" || tokens[i] == "imaginbank" {
                if !isCounterparty { mentioned.insert(.ima) }
            }
            i += 1
        }
    }
    if mentioned.count == 1 { return mentioned.first }
    if mentioned.count > 1 { return nil }

    // 3. Patrones propios de cada banco cuando el nombre de la app no viene en el texto.
    let joined = foldedLines.joined(separator: "\n")
    let hasRevolutStrong = [
        "spent today", "revpoints",
    ].contains { joined.contains($0) }
    let hasRevolutPaid = joined.contains(revolutPaidPattern)
        && joined.contains(" at ")
    let hasTRStrong = [
        "saveback", "round up", "roundup", "card payment",
    ].contains { joined.contains($0) }

    if hasRevolutStrong && hasTRStrong { return nil }
    if hasTRStrong { return .tr }
    if hasRevolutStrong || hasRevolutPaid { return .rev }
    return nil
}

/// Frase propia de Revolut («Paid €5.50 at …» / «Paid 5,50 € at …»), compilada una sola vez. Se busca en texto ya plegado.
private let revolutPaidPattern = #/\bpaid\s+(?:€|eur)\s*\d|\bpaid\s+\d+(?:[.,]\d+)*\s*(?:€|eur)/#

/// Un aviso del que no se puede deducir el banco no se tira: si tiene pinta de movimiento o no se entiende, se guarda
/// para que el dueño lo vea (sin saldo ni guía de ningún banco). Lo que el lector ignora (códigos, aprobaciones,
/// rechazos o textos sin importe) no se guarda: no hay ningún pago que perder.
private func unattributedQuickNotice(_ contentLines: [String]) -> IngestInput? {
    let text = capQuickScalars(contentLines.joined(separator: "\n"), maxLength: QuickNoticeLimits.fieldMaxLength)
    guard !isBlankQuickText(text) else { return nil }
    if case .ignore = parseNotification(bank: .rev, title: nil, subtitle: nil, body: text) { return nil }
    return .unattributedNotice(text: text)
}
