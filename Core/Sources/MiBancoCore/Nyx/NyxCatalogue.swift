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
    nyxActionTitle(action, hidden: false)
}

/// Texto visible de cada acción respetando el ojo cerrado: nunca filtra dígitos de un comercio numérico.
public func nyxActionTitle(_ action: NyxAction, hidden: Bool) -> String {
    switch action {
    case .openBankApp(let bank): return "Abrir \(bank.displayName)"
    case .prepareTransfer: return "Preparar traspaso"
    case .setBudget: return "Poner un presupuesto"
    case .openBudgets: return "Ver presupuestos"
    case .muteMerchant(let name):
        let clipped = clippedName(name)
        if hidden, clipped.contains(where: \.isNumber) {
            return "Silenciar este comercio"
        }
        return "Silenciar \(clipped)"
    case .markNotMine: return "No es mío"
    case .openMovement: return "Ver el pago"
    case .renewBank: return "Renovar"
    case .refreshBank: return "Actualizar"
    case .openGuide: return "Abrir la guía"
    case .openNotificationSettings: return "Abrir Ajustes"
    case .openSideStore: return "Abrir SideStore"
    case .turnOffAlert: return "Dejar de avisar"
    }
}

/// Títulos de las acciones de `m` respetando el ojo cerrado (conserva variantes como «Ver el ingreso»).
public func nyxActionTitles(_ m: NyxMessage, hidden: Bool) -> [String] {
    guard hidden else { return m.actionTitles }
    return zip(m.actions, m.actionTitles).map { action, openTitle in
        openTitle.contains(where: \.isNumber) ? nyxActionTitle(action, hidden: true) : openTitle
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

private func nyxWeekdayName(_ day: Date, calendar: Calendar) -> String {
    nyxWeekdays[((calendar.component(.weekday, from: day) - 1) % 7 + 7) % 7]
}

/// `{día}` al comienzo de frase con el ojo abierto: «Hoy», «Mañana», «El viernes 28» o «El 21 nov» (nunca «Hoy» si ya pasó).
private func nyxDayPhrase(_ day: Date, now: Date, calendar: Calendar) -> String {
    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
    switch diff {
    case 0: return "Hoy"
    case 1: return "Mañana"
    case 2...7, (-6)...(-1):
        return "El \(nyxWeekdayName(day, calendar: calendar)) \(calendar.component(.day, from: day))"
    default:
        return "El " + shortSpanishDate(day, calendar: calendar, withYear: false)
    }
}

/// `{día}` al comienzo de frase con el ojo cerrado y en textos neutros: SIN ningún dígito y nunca «Hoy» si ya pasó.
private func nyxClosedDayPhrase(_ day: Date, now: Date, calendar: Calendar) -> String {
    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
    switch diff {
    case 0: return "Hoy"
    case 1: return "Mañana"
    case 2: return "Pasado mañana"
    case 3...7:
        return "El \(nyxWeekdayName(day, calendar: calendar))"
    case 8...:
        let sameMonth = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            && calendar.component(.month, from: day) == calendar.component(.month, from: now)
        return sameMonth ? "Este mes" : "El mes que viene"
    case -1:
        return "Ayer"
    case (-6)...(-2):
        return "Hace unos días"
    case (-13)...(-7):
        return "La semana pasada"
    default:
        let sameMonth = calendar.component(.year, from: day) == calendar.component(.year, from: now)
            && calendar.component(.month, from: day) == calendar.component(.month, from: now)
        return sameMonth ? "Este mes" : "El mes pasado"
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
/// Si faltan datos obligatorios en una entrada antigua o dañada, devuelve la frase neutra en lugar de inventar datos.
public func nyxMessage(for o: NyxObservation, now: Date, calendar: Calendar) -> NyxMessage {
    let f = o.facts
    let rawMerchant = nyxCleanMerchant(f.merchant)

    func build(title: String, closedTitle: String? = nil, open: [BriefingPart], closed: String, neutral: String,
               actions: [NyxAction], actionTitles: [String]? = nil) -> NyxMessage {
        NyxMessage(id: o.id, situation: o.situation, priority: o.priority, title: title,
                   closedTitle: closedTitle ?? title, open: open, closed: closed, neutral: neutral,
                   actions: actions, actionTitles: actionTitles ?? actions.map { nyxActionTitle($0) })
    }

    switch o.situation {
    case .unusualPayment:
        let neutral = "Un pago más alto de lo habitual."
        var actions: [NyxAction] = []
        if let id = f.movementID { actions.append(.markNotMine(id)) }
        if let rawMerchant { actions.append(.muteMerchant(rawMerchant)) }
        if actions.isEmpty, let bankID = f.bank { actions.append(.openBankApp(bankID)) }
        let open: [BriefingPart] = if let rawMerchant, let cents = f.cents, let usual = f.usualCents {
            [.text("\(clippedName(rawMerchant)): "), .amount(cents), .text(". Ahí sueles gastar unos "), .amount(usual), .text(".")]
        } else {
            [.text(neutral)]
        }
        let closed = rawMerchant.map { "Un pago en \(clippedName($0)) más alto de lo habitual." } ?? neutral
        return build(
            title: "Pago poco habitual",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .largePayment:
        let neutral = f.bank.map { "Pago grande con \($0.displayName)." } ?? "Ha habido un pago grande."
        let open: [BriefingPart]
        if let cents = f.cents, let bank = f.bank?.displayName {
            if let rawMerchant {
                open = [.text("Pago de "), .amount(cents), .text(" en \(clippedName(rawMerchant)), con \(bank).")]
            } else {
                open = [.text("Pago de "), .amount(cents), .text(" con \(bank).")]
            }
        } else {
            open = [.text(neutral)]
        }
        let closed: String
        if let bank = f.bank?.displayName {
            if let rawMerchant {
                closed = "Pago grande en \(clippedName(rawMerchant)), con \(bank)."
            } else {
                closed = "Pago grande con \(bank)."
            }
        } else {
            closed = neutral
        }
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0), .markNotMine($0)] }
            ?? f.bank.map { [.openBankApp($0)] } ?? []
        return build(
            title: "Pago grande",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .duplicateCharge:
        let neutral = "Un comercio te ha cobrado dos veces lo mismo en pocos minutos."
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0), .markNotMine($0)] }
            ?? f.bank.map { [.openBankApp($0)] } ?? []
        let open: [BriefingPart] = if let rawMerchant, let cents = f.cents {
            [.text("\(clippedName(rawMerchant)) te ha cobrado "), .amount(cents), .text(" dos veces en pocos minutos.")]
        } else {
            [.text(neutral)]
        }
        let closed = rawMerchant.map { "\(clippedName($0)) te ha cobrado dos veces lo mismo en pocos minutos." } ?? neutral
        return build(
            title: "Posible cobro duplicado",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .subscriptionUp:
        let neutral = "Una suscripción te cobra más que antes."
        var actions: [NyxAction] = []
        if let bankID = f.bank { actions.append(.openBankApp(bankID)) }
        if let rawMerchant { actions.append(.muteMerchant(rawMerchant)) }
        let open: [BriefingPart] = if let rawMerchant, let diff = f.differenceCents, let cents = f.cents {
            [.text("\(clippedName(rawMerchant)) ha subido "), .amount(diff), .text(": ahora te cobra "), .amount(cents), .text(" al mes.")]
        } else {
            [.text(neutral)]
        }
        let closed = rawMerchant.map { "\(clippedName($0)) te cobra más que antes." } ?? neutral
        return build(
            title: "Una suscripción sube",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .subscriptionDown:
        let neutral = "Una suscripción te cobra menos que antes."
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? f.bank.map { [.openBankApp($0)] } ?? []
        let open: [BriefingPart] = if let rawMerchant, let diff = f.differenceCents, let cents = f.cents {
            [.text("\(clippedName(rawMerchant)) ha bajado "), .amount(diff), .text(": ahora te cobra "), .amount(cents), .text(" al mes.")]
        } else {
            [.text(neutral)]
        }
        let closed = rawMerchant.map { "\(clippedName($0)) te cobra menos que antes." } ?? neutral
        return build(
            title: "Una suscripción baja",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .shortfall:
        let closedDay = f.day.map { nyxClosedDayPhrase($0, now: now, calendar: calendar) }
        let neutral: String
        if let closedDay, let bank = f.bank?.displayName {
            neutral = "\(closedDay) te cobran algo en \(bank) y la cuenta se queda corta."
        } else if let closedDay {
            neutral = "\(closedDay) tienes un cobro que no cabe en la cuenta."
        } else {
            neutral = "Tienes un cobro próximo que no cabe en la cuenta."
        }
        let open: [BriefingPart]
        if let dayDate = f.day, let rawMerchant, let bank = f.bank?.displayName,
           let cents = f.cents, let balance = f.balanceCents, let suggested = f.suggestedCents {
            let openDay = nyxDayPhrase(dayDate, now: now, calendar: calendar)
            var parts: [BriefingPart] = [
                .text("\(openDay) te cobran \(clippedName(rawMerchant)) ("), .amount(cents),
                .text(") en \(bank) y tienes "), .amount(balance),
            ]
            if let other = f.otherBank {
                parts += [.text(". Puedo dejarte preparado un traspaso de "), .amount(suggested), .text(" desde \(other.displayName).")]
            } else {
                parts += [.text(". Para cubrirlo, pásale "), .amount(suggested), .text(" antes.")]
            }
            open = parts
        } else {
            open = [.text(neutral)]
        }
        let closed: String
        if let closedDay, let rawMerchant, let bank = f.bank?.displayName {
            closed = "\(closedDay) te cobran \(clippedName(rawMerchant)) en \(bank) y la cuenta se queda corta."
        } else {
            closed = neutral
        }
        let actions: [NyxAction] = f.bank.map { [.prepareTransfer(from: f.otherBank, to: $0, cents: f.suggestedCents)] } ?? []
        return build(
            title: "Un cobro que no cabe",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .budgetNear:
        let neutral = "Estás cerca del límite de un presupuesto."
        let open: [BriefingPart] = if let scope = f.budgetScope, let percent = f.percent, let remaining = f.remainingCents {
            [.text("Llevas el \(percent)\u{00A0}% de tu presupuesto \(scope): te quedan "), .amount(remaining), .text(".")]
        } else {
            [.text(neutral)]
        }
        let closed = f.budgetScope.map { "Estás cerca del límite de tu presupuesto \($0)." } ?? neutral
        return build(
            title: "Presupuesto casi al límite",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: [.openBudgets])

    case .budgetExceeded:
        let neutral = "Te has pasado de un presupuesto."
        let open: [BriefingPart] = if let scope = f.budgetScope, let spent = f.spentCents, let limit = f.limitCents {
            [.text("Te has pasado del presupuesto \(scope): llevas "), .amount(spent), .text(" de "), .amount(limit), .text(".")]
        } else {
            [.text(neutral)]
        }
        let closed = f.budgetScope.map { "Te has pasado del presupuesto \($0)." } ?? neutral
        return build(
            title: "Presupuesto superado",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: [.openBudgets])

    case .budgetOffPace:
        let neutral = "A este ritmo, un presupuesto se acaba antes de fin de mes."
        let open: [BriefingPart] = if let scope = f.budgetScope, let spent = f.spentCents, let limit = f.limitCents {
            [.text("A este ritmo, el presupuesto \(scope) se acaba antes de fin de mes: llevas "),
             .amount(spent), .text(" de "), .amount(limit), .text(".")]
        } else {
            [.text(neutral)]
        }
        let closed = f.budgetScope.map { "A este ritmo, el presupuesto \($0) se acaba antes de fin de mes." } ?? neutral
        return build(
            title: "El presupuesto va rápido",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: [.openBudgets])

    case .categoryAboveNormal:
        let neutral = "Este mes llevas en una categoría más de lo habitual."
        let open: [BriefingPart] = if let category = f.category, let spent = f.spentCents, let usual = f.usualCents {
            [.text("Este mes llevas "), .amount(spent), .text(" en \(category.displayName); tu media es de unos "),
             .amount(usual), .text(" al mes.")]
        } else {
            [.text(neutral)]
        }
        let closed = f.category.map { "Este mes llevas en \($0.displayName) más de lo habitual." } ?? neutral
        let actions: [NyxAction] = f.category.map {
            [.setBudget(category: $0, suggestedCents: nyxSuggestedBudget(from: f.usualCents))]
        } ?? [.openBudgets]
        return build(
            title: "Más de lo habitual",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .salary:
        let neutral = "Ha llegado la nómina."
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? f.bank.map { [.openBankApp($0)] } ?? []
        let titles = actions.map { action -> String in
            if case .openMovement = action { return "Ver el ingreso" }
            return nyxActionTitle(action)
        }
        let open: [BriefingPart] = if let cents = f.cents, let bank = f.bank?.displayName {
            [.text("Ha llegado la nómina: "), .amount(cents), .text(" en \(bank).")]
        } else {
            [.text(neutral)]
        }
        let closed = f.bank.map { "Ha llegado la nómina a \($0.displayName)." } ?? neutral
        return build(
            title: "Ha llegado la nómina",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions,
            actionTitles: titles)

    case .largeIncome:
        let neutral = "Ha entrado un ingreso grande."
        let open: [BriefingPart]
        if let cents = f.cents, let bank = f.bank?.displayName {
            if let rawMerchant {
                open = [.text("Han entrado "), .amount(cents), .text(" de \(clippedName(rawMerchant)) en \(bank).")]
            } else {
                open = [.text("Han entrado "), .amount(cents), .text(" en \(bank).")]
            }
        } else {
            open = [.text(neutral)]
        }
        let closed = f.bank.map { "Ha entrado un ingreso grande en \($0.displayName)." } ?? neutral
        let actions: [NyxAction] = f.movementID.map { [.openMovement($0)] } ?? f.bank.map { [.openBankApp($0)] } ?? []
        let titles = actions.map { action -> String in
            if case .openMovement = action { return "Ver el ingreso" }
            return nyxActionTitle(action)
        }
        return build(
            title: "Ingreso grande",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions,
            actionTitles: titles)

    case .lowBalance:
        let neutral = "Saldo bajo en una cuenta."
        let open: [BriefingPart] = if let bank = f.bank?.displayName, let balance = f.balanceCents {
            [.text("En \(bank) te quedan "), .amount(balance), .text(".")]
        } else {
            [.text(neutral)]
        }
        let closed = f.bank.map { "Saldo bajo en \($0.displayName)." } ?? neutral
        let actions: [NyxAction] = f.bank.map { [.prepareTransfer(from: nil, to: $0, cents: nil)] } ?? []
        return build(
            title: "Saldo bajo",
            open: open,
            closed: closed,
            neutral: neutral,
            actions: actions)

    case .bankExpired:
        if let bankID = f.bank {
            let bank = bankID.displayName
            let text = "La conexión con \(bank) ha caducado. Renuévala para volver a ver su saldo al día."
            return build(title: "\(bank) necesita renovarse", open: [.text(text)], closed: text, neutral: text,
                         actions: [.renewBank(bankID)])
        }
        let text = "Una conexión bancaria ha caducado. Renuévala para volver a ver su saldo al día."
        return build(title: "Un banco necesita renovarse", open: [.text(text)], closed: text, neutral: text, actions: [])

    case .bankExpiring:
        if let bankID = f.bank {
            let bank = bankID.displayName
            let closed = "La conexión con \(bank) caduca pronto. Si la renuevas antes, su saldo sigue al día."
            let open: [BriefingPart] = if let day = f.day {
                [.text("La conexión con \(bank) caduca \(nyxWhenPhrase(day, now: now, calendar: calendar)). Si la renuevas antes, su saldo sigue al día.")]
            } else {
                [.text(closed)]
            }
            return build(title: "\(bank) caduca pronto", open: open, closed: closed, neutral: closed,
                         actions: [.renewBank(bankID)])
        }
        let text = "Una conexión bancaria caduca pronto. Si la renuevas antes, su saldo sigue al día."
        return build(title: "Un banco caduca pronto", open: [.text(text)], closed: text, neutral: text, actions: [])

    case .bankStale:
        if let bankID = f.bank {
            let bank = bankID.displayName
            let closed = "Hace un tiempo que no consigo actualizar \(bank). Puedes probar ahora."
            let open: [BriefingPart] = if let day = f.day {
                [.text("No he podido actualizar \(bank) desde \(nyxWhenPhrase(day, now: now, calendar: calendar)). Puedes probar ahora.")]
            } else {
                [.text(closed)]
            }
            return build(title: "No consigo actualizar \(bank)", open: open, closed: closed, neutral: closed,
                         actions: [.refreshBank(bankID)])
        }
        let text = "Hace un tiempo que no consigo actualizar un banco. Puedes probar ahora."
        return build(title: "No consigo actualizar un banco", open: [.text(text)], closed: text, neutral: text, actions: [])

    case .alertsSilent:
        if f.track == GuideTrack.walletImagin.rawValue {
            let closed = "Hace días que no me llega ningún pago con Apple Pay de imagin. Si has pagado así desde entonces, repasa la guía."
            let open: [BriefingPart] = if let days = f.days {
                [.text("Hace \(days) días que no me llega ningún pago con Apple Pay de imagin. Si has pagado así desde entonces, repasa la guía.")]
            } else {
                [.text(closed)]
            }
            return build(title: "No llegan pagos de imagin", open: open, closed: closed, neutral: closed,
                         actions: [.openGuide(GuideTrack.walletImagin.rawValue)])
        } else if let bankID = f.bank {
            let bank = bankID.displayName
            let closed = "Hace días que no me llega ningún aviso de \(bank). Si has pagado con \(bank) desde entonces, repasa la guía."
            let open: [BriefingPart] = if let days = f.days {
                [.text("Hace \(days) días que no me llega ningún aviso de \(bank). Si has pagado con \(bank) desde entonces, repasa la guía.")]
            } else {
                [.text(closed)]
            }
            return build(title: "No llegan avisos de \(bank)", open: open, closed: closed, neutral: closed,
                         actions: f.track.map { [.openGuide($0)] } ?? [])
        }
        let text = "Hace días que no me llegan avisos de un banco. Si has pagado desde entonces, repasa la guía."
        return build(title: "No llegan avisos", open: [.text(text)], closed: text, neutral: text,
                     actions: f.track.map { [.openGuide($0)] } ?? [])

    case .alertsNeverArrived:
        if let bankID = f.bank {
            let bank = bankID.displayName
            let text = "Aún no me ha llegado ningún aviso de \(bank): sin ellos, me entero tarde de sus pagos. La guía te lleva paso a paso."
            return build(title: "Faltan los avisos de \(bank)", open: [.text(text)], closed: text, neutral: text,
                         actions: f.track.map { [.openGuide($0)] } ?? [])
        }
        let text = "Aún no me ha llegado ningún aviso de un banco: sin ellos, me entero tarde de sus pagos. La guía te lleva paso a paso."
        return build(title: "Faltan avisos de un banco", open: [.text(text)], closed: text, neutral: text,
                     actions: f.track.map { [.openGuide($0)] } ?? [])

    case .notificationsOff:
        let text = "Tienes apagados los avisos de \(appDisplayName), así que no puedo contarte nada al momento. Puedes encenderlos en Ajustes."
        return build(
            title: "Avisos apagados",
            open: [.text(text)],
            closed: text,
            neutral: text,
            actions: [.openNotificationSettings])

    case .appExpiring:
        let closed = "\(appDisplayName) caduca pronto. Renuévala en SideStore antes, o dejará de abrirse."
        if let day = f.day {
            let when = nyxWhenPhrase(day, now: now, calendar: calendar)
            return build(
                title: "\(appDisplayName) caduca \(when)",
                closedTitle: "\(appDisplayName) caduca pronto",
                open: [.text("\(appDisplayName) caduca \(when). Renuévala en SideStore antes, o dejará de abrirse.")],
                closed: closed,
                neutral: closed,
                actions: [.openSideStore])
        }
        return build(
            title: "\(appDisplayName) caduca pronto",
            closedTitle: "\(appDisplayName) caduca pronto",
            open: [.text(closed)],
            closed: closed,
            neutral: closed,
            actions: [.openSideStore])

    case .suggestMute:
        let neutral = "Te he avisado varias veces de pagos en un comercio y los has descartado."
        if let rawMerchant {
            let m = clippedName(rawMerchant)
            let text = "Te he avisado varias veces de pagos en \(m) y los has descartado. Si quieres, dejo de avisarte de ese comercio."
            return build(title: "¿Silencio \(m)?", open: [.text(text)], closed: text, neutral: neutral,
                         actions: [.muteMerchant(rawMerchant)])
        }
        return build(title: "¿Silencio este comercio?", open: [.text(neutral)], closed: neutral, neutral: neutral, actions: [])

    case .suggestAlertOff:
        if let sw = f.alertSwitch {
            let text = "Has descartado varios avisos de \(sw.spanishName) seguidos. Si quieres, dejo de mandártelos; puedes volver a encenderlos en Avisos."
            return build(title: "¿Dejo estos avisos?", open: [.text(text)], closed: text, neutral: text,
                         actions: [.turnOffAlert(sw)])
        }
        let text = "Has descartado varios avisos seguidos. Si quieres, puedes apagarlos en Avisos."
        return build(title: "¿Dejo estos avisos?", open: [.text(text)], closed: text, neutral: text, actions: [])
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
