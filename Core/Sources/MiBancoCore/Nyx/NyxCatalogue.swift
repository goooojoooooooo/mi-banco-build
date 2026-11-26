import Foundation

/// Botón con tipo de un mensaje de Nyx (diseño §6.8). Nunca mueve dinero: «Preparar traspaso» abre «Mover dinero» relleno.
public enum NyxAction: Equatable, Codable, Sendable {
    case openBankApp(BankID)
    case prepareTransfer(from: BankID?, to: BankID, cents: Int?)
    case setBudget(category: SpendingCategory, suggestedCents: Int?)
    case openBudgets
    case muteMerchant(String)
    case markNotMine(UUID)
    case openMovement(UUID)
    case renewBank(BankID)
    case refreshBank(BankID)
    case openGuide(String)
    case openNotificationSettings
    case openSideStore
    case turnOffAlert(NyxAlertSwitch)
}

/// Texto visible de cada acción (para movimientos de ingreso, `nyxMessage` usa «Ver el ingreso» en `actionTitles`).
public func nyxActionTitle(_ action: NyxAction) -> String {
    switch action {
    case .openBankApp(let bank): "Abrir \(bank.displayName)"
    case .prepareTransfer: "Preparar traspaso"
    case .setBudget: "Poner un presupuesto"
    case .openBudgets: "Ver presupuestos"
    case .muteMerchant(let name): "Silenciar \(clippedName(name))"
    case .markNotMine: "No es mío"
    case .openMovement: "Ver el pago"
    case .renewBank: "Renovar"
    case .refreshBank: "Actualizar"
    case .openGuide: "Abrir la guía"
    case .openNotificationSettings: "Abrir Ajustes"
    case .openSideStore: "Abrir SideStore"
    case .turnOffAlert: "Dejar de avisar"
    }
}

/// Mensaje listo para enseñar o avisar: variante con ojo abierto (`open`), con ojo cerrado (`closed`) y neutra sin comercio (`neutral`).
public struct NyxMessage: Equatable, Sendable, Identifiable {
    public let id: String
    public let situation: NyxSituation
    public let priority: NyxPriority
    public let title: String
    public let closedTitle: String
    public let open: [BriefingPart]
    public let closed: String
    public let neutral: String
    public let actions: [NyxAction]
    public let actionTitles: [String]

    public init(id: String, situation: NyxSituation, priority: NyxPriority, title: String, closedTitle: String,
                open: [BriefingPart], closed: String, neutral: String, actions: [NyxAction], actionTitles: [String]) {
        self.id = id
        self.situation = situation
        self.priority = priority
        self.title = title
        self.closedTitle = closedTitle
        self.open = open
        self.closed = closed
        self.neutral = neutral
        self.actions = actions
        self.actionTitles = actionTitles
    }
}

private let nyxWeekdays = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]

private func nyxDayPhrase(_ day: Date, now: Date, calendar: Calendar) -> String {
    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
    switch diff {
    case ...0: return "Hoy"
    case 1: return "Mañana"
    default:
        let weekday = nyxWeekdays[((calendar.component(.weekday, from: day) - 1) % 7 + 7) % 7]
        return "El \(weekday) \(calendar.component(.day, from: day))"
    }
}

private func nyxWhenPhrase(_ day: Date, now: Date, calendar: Calendar) -> String {
    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
    switch diff {
    case 0: return "hoy"
    case 1: return "mañana"
    default: return "el " + shortSpanishDate(day, calendar: calendar, withYear: false)
    }
}

private func nyxCleanMerchant(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}

private func nyxSuggestedBudget(from usualCents: Int?) -> Int? {
    guard let usualCents, usualCents > 0 else { return nil }
    return ((usualCents + 999) / 1_000) * 1_000
}

/// Compone el mensaje exacto del catálogo (diseño §6.7) a partir de los datos con tipo de una observación.
public func nyxMessage(for o: NyxObservation, now: Date, calendar: Calendar) -> NyxMessage {
    let f = o.facts
    let rawMerchant = nyxCleanMerchant(f.merchant)
    let merchant = rawMerchant.map(clippedName) ?? "ese comercio"
    let bankID = f.bank ?? .rev
    let bank = bankID.displayName
    let cents = f.cents ?? 0

    func build(title: String, closedTitle: String? = nil, open: [BriefingPart], closed: String, neutral: String,
               actions: [NyxAction], actionTitles: [String]? = nil) -> NyxMessage {
        NyxMessage(id: o.id, situation: o.situation, priority: o.priority, title: title,
                   closedTitle: closedTitle ?? title, open: open, closed: closed, neutral: neutral,
                   actions: actions, actionTitles: actionTitles ?? actions.map(nyxActionTitle))
    }

    switch o.situation {
    case .unusualPayment:
        let usual = f.usualCents ?? 0
        var actions: [NyxAction] = []
        if let id = f.movementID { actions.append(.markNotMine(id)) }
        if let rawMerchant { actions.append(.muteMerchant(rawMerchant)) }
        if actions.isEmpty { actions.append(.openBankApp(bankID)) }
        return build(
            title: "Pago poco habitual",
            open: [.text("\(merchant): "), .amount(cents), .text(". Ahí sueles gastar unos "), .amount(usual), .text(".")],
            closed: "Un pago en \(merchant) más alto de lo habitual.",
            neutral: "Un pago más alto de lo habitual.",
            actions: actions)

    case .largePayment:
        let open: [BriefingPart]
        let closed: String
        if let rawMerchant {
            let m = clippedName(rawMerchant)
            open = [.text("Pago de "), .amount(cents), .text(" en \(m), con \(bank).")]
            closed = "Pago grande en \(m), con \(bank)."
        } else {
            open = [.text("Pago de "), .amount(cents), .text(" con \(bank).")]
            closed = "Pago grande con \(bank)."
        }
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0), .markNotMine($0)] } ?? [.openBankApp(bankID)]
        return build(
            title: "Pago grande",
            open: open,
            closed: closed,
            neutral: "Pago grande con \(bank).",
            actions: actions)

    case .duplicateCharge:
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0), .markNotMine($0)] } ?? [.openBankApp(bankID)]
        return build(
            title: "Posible cobro duplicado",
            open: [.text("\(merchant) te ha cobrado "), .amount(cents), .text(" dos veces en pocos minutos.")],
            closed: "\(merchant) te ha cobrado dos veces lo mismo en pocos minutos.",
            neutral: "Un comercio te ha cobrado dos veces lo mismo en pocos minutos.",
            actions: actions)

    case .subscriptionUp:
        let diff = f.differenceCents ?? 0
        var actions: [NyxAction] = [.openBankApp(bankID)]
        if let rawMerchant { actions.append(.muteMerchant(rawMerchant)) }
        return build(
            title: "Una suscripción sube",
            open: [.text("\(merchant) ha subido "), .amount(diff), .text(": ahora te cobra "), .amount(cents), .text(" al mes.")],
            closed: "\(merchant) te cobra más que antes.",
            neutral: "Una suscripción te cobra más que antes.",
            actions: actions)

    case .subscriptionDown:
        let diff = f.differenceCents ?? 0
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? [.openBankApp(bankID)]
        return build(
            title: "Una suscripción baja",
            open: [.text("\(merchant) ha bajado "), .amount(diff), .text(": ahora te cobra "), .amount(cents), .text(" al mes.")],
            closed: "\(merchant) te cobra menos que antes.",
            neutral: "Una suscripción te cobra menos que antes.",
            actions: actions)

    case .shortfall:
        let day = nyxDayPhrase(f.day ?? now, now: now, calendar: calendar)
        let balance = f.balanceCents ?? 0
        let suggested = f.suggestedCents ?? 0
        var open: [BriefingPart] = [
            .text("\(day) te cobran \(merchant) ("), .amount(cents), .text(") en \(bank) y tienes "), .amount(balance),
        ]
        if let other = f.otherBank {
            open += [.text(". Puedo dejarte preparado un traspaso de "), .amount(suggested), .text(" desde \(other.displayName).")]
        } else {
            open += [.text(". Para cubrirlo, pásale "), .amount(suggested), .text(" antes.")]
        }
        return build(
            title: "Un cobro que no cabe",
            open: open,
            closed: "\(day) te cobran \(merchant) en \(bank) y la cuenta se queda corta.",
            neutral: "\(day) te cobran algo en \(bank) y la cuenta se queda corta.",
            actions: [.prepareTransfer(from: f.otherBank, to: bankID, cents: f.suggestedCents)])

    case .budgetNear:
        let scope = f.budgetScope ?? "del mes"
        let percent = f.percent ?? 80
        let remaining = f.remainingCents ?? 0
        return build(
            title: "Presupuesto casi al límite",
            open: [.text("Llevas el \(percent)\u{00A0}% de tu presupuesto \(scope): te quedan "), .amount(remaining), .text(".")],
            closed: "Estás cerca del límite de tu presupuesto \(scope).",
            neutral: "Estás cerca del límite de un presupuesto.",
            actions: [.openBudgets])

    case .budgetExceeded:
        let scope = f.budgetScope ?? "del mes"
        let spent = f.spentCents ?? 0
        let limit = f.limitCents ?? 0
        return build(
            title: "Presupuesto superado",
            open: [.text("Te has pasado del presupuesto \(scope): llevas "), .amount(spent), .text(" de "), .amount(limit), .text(".")],
            closed: "Te has pasado del presupuesto \(scope).",
            neutral: "Te has pasado de un presupuesto.",
            actions: [.openBudgets])

    case .budgetOffPace:
        let scope = f.budgetScope ?? "del mes"
        let spent = f.spentCents ?? 0
        let limit = f.limitCents ?? 0
        return build(
            title: "El presupuesto va rápido",
            open: [.text("A este ritmo, el presupuesto \(scope) se acaba antes de fin de mes: llevas "),
                   .amount(spent), .text(" de "), .amount(limit), .text(".")],
            closed: "A este ritmo, el presupuesto \(scope) se acaba antes de fin de mes.",
            neutral: "A este ritmo, un presupuesto se acaba antes de fin de mes.",
            actions: [.openBudgets])

    case .categoryAboveNormal:
        let category = f.category ?? .sinCategoria
        let spent = f.spentCents ?? 0
        let usual = f.usualCents ?? 0
        return build(
            title: "Más de lo habitual",
            open: [.text("Este mes llevas "), .amount(spent), .text(" en \(category.displayName); tu media es de unos "),
                   .amount(usual), .text(" al mes.")],
            closed: "Este mes llevas en \(category.displayName) más de lo habitual.",
            neutral: "Este mes llevas en una categoría más de lo habitual.",
            actions: [.setBudget(category: category, suggestedCents: nyxSuggestedBudget(from: f.usualCents))])

    case .salary:
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? [.openBankApp(bankID)]
        let titles = actions.map { action -> String in
            if case .openMovement = action { return "Ver el ingreso" }
            return nyxActionTitle(action)
        }
        return build(
            title: "Ha llegado la nómina",
            open: [.text("Ha llegado la nómina: "), .amount(cents), .text(" en \(bank).")],
            closed: "Ha llegado la nómina a \(bank).",
            neutral: "Ha llegado la nómina.",
            actions: actions,
            actionTitles: titles)

    case .largeIncome:
        let open: [BriefingPart]
        if let rawMerchant {
            open = [.text("Han entrado "), .amount(cents), .text(" de \(clippedName(rawMerchant)) en \(bank).")]
        } else {
            open = [.text("Han entrado "), .amount(cents), .text(" en \(bank).")]
        }
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? [.openBankApp(bankID)]
        let titles = actions.map { action -> String in
            if case .openMovement = action { return "Ver el ingreso" }
            return nyxActionTitle(action)
        }
        return build(
            title: "Ingreso grande",
            open: open,
            closed: "Ha entrado un ingreso grande en \(bank).",
            neutral: "Ha entrado un ingreso grande.",
            actions: actions,
            actionTitles: titles)

    case .lowBalance:
        let balance = f.balanceCents ?? 0
        return build(
            title: "Saldo bajo",
            open: [.text("En \(bank) te quedan "), .amount(balance), .text(".")],
            closed: "Saldo bajo en \(bank).",
            neutral: "Saldo bajo en una cuenta.",
            actions: [.prepareTransfer(from: nil, to: bankID, cents: nil)])

    case .bankExpired:
        let text = "La conexión con \(bank) ha caducado. Renuévala para volver a ver su saldo al día."
        return build(
            title: "\(bank) necesita renovarse",
            open: [.text(text)],
            closed: text,
            neutral: text,
            actions: [.renewBank(bankID)])

    case .bankExpiring:
        let when = nyxWhenPhrase(f.day ?? now, now: now, calendar: calendar)
        let closed = "La conexión con \(bank) caduca pronto. Si la renuevas antes, su saldo sigue al día."
        return build(
            title: "\(bank) caduca pronto",
            open: [.text("La conexión con \(bank) caduca \(when). Si la renuevas antes, su saldo sigue al día.")],
            closed: closed,
            neutral: closed,
            actions: [.renewBank(bankID)])

    case .bankStale:
        let when = nyxWhenPhrase(f.day ?? now, now: now, calendar: calendar)
        let closed = "Hace un tiempo que no consigo actualizar \(bank). Puedes probar ahora."
        return build(
            title: "No consigo actualizar \(bank)",
            open: [.text("No he podido actualizar \(bank) desde \(when). Puedes probar ahora.")],
            closed: closed,
            neutral: closed,
            actions: [.refreshBank(bankID)])

    case .alertsSilent:
        let days = f.days ?? guideSilentAfterDays
        let isWalletImagin = f.track == GuideTrack.walletImagin.rawValue
        let track = f.track ?? (isWalletImagin ? GuideTrack.walletImagin.rawValue : GuideTrack.revolut.rawValue)
        if isWalletImagin {
            let closed = "Hace días que no me llega ningún pago con Apple Pay de imagin. Si has pagado así desde entonces, repasa la guía."
            return build(
                title: "No llegan pagos de imagin",
                open: [.text("Hace \(days) días que no me llega ningún pago con Apple Pay de imagin. Si has pagado así desde entonces, repasa la guía.")],
                closed: closed,
                neutral: closed,
                actions: [.openGuide(track)])
        } else {
            let closed = "Hace días que no me llega ningún aviso de \(bank). Si has pagado con \(bank) desde entonces, repasa la guía."
            return build(
                title: "No llegan avisos de \(bank)",
                open: [.text("Hace \(days) días que no me llega ningún aviso de \(bank). Si has pagado con \(bank) desde entonces, repasa la guía.")],
                closed: closed,
                neutral: closed,
                actions: [.openGuide(track)])
        }

    case .alertsNeverArrived:
        let track = f.track ?? GuideTrack.walletImagin.rawValue
        let text = "Aún no me ha llegado ningún aviso de \(bank): sin ellos, me entero tarde de sus pagos. La guía te lleva paso a paso."
        return build(
            title: "Faltan los avisos de \(bank)",
            open: [.text(text)],
            closed: text,
            neutral: text,
            actions: [.openGuide(track)])

    case .notificationsOff:
        let text = "Tienes apagados los avisos de \(appDisplayName), así que no puedo contarte nada al momento. Puedes encenderlos en Ajustes."
        return build(
            title: "Avisos apagados",
            open: [.text(text)],
            closed: text,
            neutral: text,
            actions: [.openNotificationSettings])

    case .appExpiring:
        let when = nyxWhenPhrase(f.day ?? now, now: now, calendar: calendar)
        let closed = "\(appDisplayName) caduca pronto. Renuévala en SideStore antes, o dejará de abrirse."
        return build(
            title: "\(appDisplayName) caduca \(when)",
            closedTitle: "\(appDisplayName) caduca pronto",
            open: [.text("\(appDisplayName) caduca \(when). Renuévala en SideStore antes, o dejará de abrirse.")],
            closed: closed,
            neutral: closed,
            actions: [.openSideStore])

    case .suggestMute:
        let text = "Te he avisado varias veces de pagos en \(merchant) y los has descartado. Si quieres, dejo de avisarte de ese comercio."
        let actions: [NyxAction] = rawMerchant.map { [.muteMerchant($0)] } ?? []
        return build(
            title: "¿Silencio \(merchant)?",
            open: [.text(text)],
            closed: text,
            neutral: "Te he avisado varias veces de pagos en un comercio y los has descartado.",
            actions: actions)

    case .suggestAlertOff:
        let sw = f.alertSwitch ?? .largePayment
        let text = "Has descartado varios avisos de \(sw.spanishName) seguidos. Si quieres, dejo de mandártelos; puedes volver a encenderlos en Avisos."
        return build(
            title: "¿Dejo estos avisos?",
            open: [.text(text)],
            closed: text,
            neutral: text,
            actions: [.turnOffAlert(sw)])
    }
}

/// Texto del aviso del sistema de Nyx. Con el ojo cerrado aplica una red final sin dígitos: cerrado → neutro → genérico.
public func nyxNotificationText(_ m: NyxMessage, hidden: Bool) -> (title: String, body: String) {
    guard hidden else { return (m.title, render(m.open, .plain)) }
    if !m.closedTitle.contains(where: \.isNumber), !m.closed.contains(where: \.isNumber) {
        return (m.closedTitle, m.closed)
    }
    let fallbackTitle: String
    if !m.closedTitle.contains(where: \.isNumber) {
        fallbackTitle = m.closedTitle
    } else if m.situation == .suggestMute {
        fallbackTitle = "¿Silencio este comercio?"
    } else {
        fallbackTitle = assistantName
    }
    if !fallbackTitle.contains(where: \.isNumber), !m.neutral.contains(where: \.isNumber) {
        return (fallbackTitle, m.neutral)
    }
    return (assistantName, "Tengo algo que contarte.")
}

/// Texto dentro de la app y de VoiceOver para un mensaje de Nyx. Con el ojo cerrado usa la misma red sin dígitos.
public func nyxDisplayText(_ m: NyxMessage, hidden: Bool) -> String {
    hidden ? nyxNotificationText(m, hidden: true).body : render(m.open, .plain)
}

/// Acciones disponibles hoy sobre `m` dado el libro actual: oculta acciones sobre movimientos borrados o comercios ya silenciados.
public func nyxAvailableActions(_ m: NyxMessage, state: LedgerState) -> [NyxAction] {
    let movementIDs = Set(state.movements.map(\.id))
    return m.actions.filter { action in
        switch action {
        case .openMovement(let id), .markNotMine(let id):
            return movementIDs.contains(id)
        case .muteMerchant(let name):
            let key = normalizeMerchant(name)
            return !key.isEmpty && !state.mutedMerchants.contains(key)
        default:
            return true
        }
    }
}
