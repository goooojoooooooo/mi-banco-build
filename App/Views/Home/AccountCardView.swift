import SwiftUI
import MiBancoCore

/// Una tarjeta del carrusel con sus dos caras. Tocarla la voltea en 3D con peso (muelle de 0,55 s con rebote; a mitad de
/// giro la tarjeta crece un 5 %, se oscurece y un brillo la cruza); detrás: si el saldo es exacto o estimado, desde
/// cuándo, lo gastado este mes y "Editar saldo". La de delante acompaña un poco a la inclinación del teléfono.
struct AccountCardView: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    var links: [BankID: BankLinkInfo] = [:]
    let total: Int?
    let monthSpent: Int
    var portfolioSummary: PortfolioSummary? = nil
    var portfolioLastImport: Date? = nil
    let flipped: Bool
    /// La cifra protagonista cuenta desde 0 la primera vez que la tarjeta se ve.
    let revealed: Bool
    /// Cada vez que sube, la tarjeta asoma unos grados y vuelve (la pista de que se puede voltear), tras `peekDelay` s.
    var peek = 0
    var peekDelay = 0.0
    /// La tarjeta de delante: la única que acompaña a la inclinación del teléfono.
    var isFront = false
    let onFlip: () -> Void
    let onEdit: () -> Void
    var onOpenBank: (BankID) -> Void = { _ in }
    var onImportInvestments: () -> Void = {}

    @Environment(\.motion) private var motion

    /// El volteo: 0,55 s con rebote 0,2 (como la maqueta), escalado por la intensidad; con Reducir movimiento, un fundido.
    private var flipAnimation: Animation {
        guard !motion.reduce else { return motion.fade }
        let spec = MotionMath.scaled(SpringSpec(response: 0.55, dampingFraction: 0.8),
                                     level: motion.level, timeMultiplier: motion.timeMultiplier)
        return .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }

    var body: some View {
        // La cara delantera es un botón (se hunde al tocar); la trasera lleva su propio botón de acción,
        // así que se voltea de vuelta con un toque en cualquier otro sitio.
        ZStack {
            Button(action: onFlip) {
                CardFront(
                    card: card,
                    balances: balances,
                    total: total,
                    portfolioSummary: portfolioSummary,
                    revealed: revealed
                )
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985))
            .accessibilityIdentifier("card-front-\(card.rawValue)")
            .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: false))

            CardBack(
                card: card,
                balances: balances,
                links: links,
                monthSpent: monthSpent,
                portfolioSummary: portfolioSummary,
                portfolioLastImport: portfolioLastImport,
                flipped: flipped,
                onEdit: onEdit,
                onOpenBank: onOpenBank,
                onImportInvestments: onImportInvestments
            )
                .contentShape(.rect(cornerRadius: Theme.Radius.card))
                .onTapGesture(perform: onFlip)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: true))
        }
        .animation(flipAnimation, value: flipped)
        .unlessProbe(5) { $0.modifier(FlipPeek(trigger: peek, delay: peekDelay)).modifier(TiltedCard(active: isFront && !flipped)) }
    }
}

/// Una cara del volteo: gira alrededor del eje Y con perspectiva y solo se ve (y se toca) mientras mira hacia delante.
/// Con peso: de canto (90°) la tarjeta está un 5 % más grande (× el recorrido del nivel), lleva encima una sombra negra
/// del 50 % y un brillo que la cruza de lado a lado durante el giro. Solo cambian escala, giro y opacidades.
/// Con Reducir movimiento no gira ni crece: las dos caras se funden.
private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool
    @Environment(\.motion) private var motion

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let a = isBack ? angle - 180 : angle
        let facing = abs(a) < 90
        let reduce = motion.reduce
        // 0 con la tarjeta de cara, 1 de canto.
        let edgeOn = reduce ? 0 : abs(sin(angle * .pi / 180))
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        content
            .overlay {
                ZStack {
                    if motion.richEffects {
                        SheenOverlay(phase: CGFloat(min(max(angle / 180, 0), 1)), tilt: 0)
                            .opacity(edgeOn)
                    }
                    shape.fill(.black.opacity(0.5 * edgeOn))
                }
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .scaleEffect(1 + 0.05 * motion.level.distanceScale * edgeOn)
            .rotation3DEffect(.degrees(reduce ? 0 : a), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(reduce ? 1 - abs(a) / 180 : (facing ? 1 : 0))
            .allowsHitTesting(facing)
            .accessibilityHidden(!facing)
    }
}

/// La pista de que la tarjeta se voltea: asoma 8° (× el recorrido del nivel) y vuelve con un rebote suave. Una sola
/// secuencia de fotogramas clave (espera, asoma, vuelve): nada encadenado con temporizadores, y los tiempos salen de
/// `\.motion`. Quien la dispara decide cuándo (una sola vez, la primera vez que se ve Inicio).
private struct FlipPeek: ViewModifier {
    let trigger: Int
    let delay: Double
    @Environment(\.motion) private var motion

    private struct Values {
        var angle = 0.0
    }

    func body(content: Content) -> some View {
        let angle = 8 * min(1.5, motion.level.distanceScale)
        let wait = max(0.01, delay)
        let out = motion.seconds(0.26)
        let spec = MotionMath.scaled(SpringToken.liftOut.base, level: motion.level, timeMultiplier: motion.timeMultiplier)
        let spring = Spring(response: spec.response, dampingRatio: spec.dampingFraction)
        let back = spec.response * 2.2
        content.keyframeAnimator(initialValue: Values(), trigger: trigger) { view, value in
            view.rotation3DEffect(.degrees(value.angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        } keyframes: { _ in
            KeyframeTrack(\.angle) {
                LinearKeyframe(0.0, duration: wait)
                CubicKeyframe(angle, duration: out)
                SpringKeyframe(0.0, duration: back, spring: spring)
            }
        }
    }
}

/// Cara delantera: «Todo» (total y los tres bancos), un banco (logo, saldo, estado, total al pie) o «Inversiones».
private struct CardFront: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    let total: Int?
    let portfolioSummary: PortfolioSummary?
    let revealed: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private var secondary: Color { contrast == .increased ? Theme.card2High : Theme.card2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Group {
                if let cents = heroCents {
                    HeroBalance(cents: cents, revealed: revealed, centsColor: secondary)
                        .accessibilityIdentifier("card-hero-\(card.rawValue)")
                } else {
                    // Sin saldo o sin precios: una raya, nunca "0,00 €".
                    Text("—")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(secondary)
                        .accessibilityLabel(card == .investments ? "Sin precio" : "Sin saldo")
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 18)
            if card == .all {
                banks
            } else if card == .investments {
                investmentsFooter
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Total en los tres bancos")
                        .titan(.meta)
                        .foregroundStyle(secondary)
                    if let total {
                        // Rueda como la cifra grande; con el ojo cerrado dibuja «•••,•• €» (nunca la cifra).
                        RollingAmount(cents: total, revealed: revealed)
                            .titan(.cardTitle)
                            .accessibilityIdentifier("card-total-\(card.rawValue)")
                    } else {
                        Text("—").titan(.cardTitle)
                    }
                }
            }
        }
        .foregroundStyle(Theme.label)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: CarouselMetrics.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(CardSurface(material: card.material))
    }

    private var heroCents: Int? {
        if card == .investments { return portfolioSummary?.valueCents }
        if let bank = card.bank { return balances[bank]?.cents }
        return total
    }

    @ViewBuilder
    private var investmentsFooter: some View {
        if let summary = portfolioSummary {
            VStack(alignment: .leading, spacing: 3) {
                if let todayCents = summary.todayChangeCents, let changeDay = summary.changeDay {
                    let eur = formatSignedEUR(todayCents).replacingOccurrences(of: "-", with: "\u{2212}")
                    let pct = summary.todayChangeTenths.map {
                        " (\(formatPercentTenths($0, signed: true).replacingOccurrences(of: "-", with: "\u{2212}")))"
                    } ?? ""
                    let session = PositionFormatting.sessionPhrase(changeDay: changeDay)
                    let line = "\(eur)\(pct) \(session)"
                    Text(line)
                        .titan(.subtitle)
                        .fontWeight(.medium)
                        .foregroundStyle(todayCents > 0 ? Theme.income : secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .privateAmount(spoken: line)
                }
                if let gainCents = summary.gainCents {
                    let eur = formatSignedEUR(gainCents).replacingOccurrences(of: "-", with: "\u{2212}")
                    let pct = summary.gainTenths.map {
                        " (\(formatPercentTenths($0, signed: true).replacingOccurrences(of: "-", with: "\u{2212}")))"
                    } ?? ""
                    let hasMissingPrices = summary.missingPrices > 0
                    let hasIncompleteCost = summary.positions.contains { $0.position.costIncomplete }
                    let partial: String = {
                        switch (hasMissingPrices, hasIncompleteCost) {
                        case (true, true): return ", de las que tienen precio y coste"
                        case (true, false): return ", de las que tienen precio"
                        case (false, true): return ", de las que tienen coste"
                        case (false, false): return ""
                        }
                    }()
                    let line = "\(eur)\(pct) desde la compra\(partial)"
                    Text(line)
                        .titan(.meta)
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .privateAmount(spoken: line)
                }
                let hasMixedTimes: Bool = {
                    guard let oldest = summary.oldestPriceAt, let newest = summary.pricedAt else { return false }
                    return Int(oldest.timeIntervalSince1970 / 60) != Int(newest.timeIntervalSince1970 / 60)
                }()
                if summary.missingPrices > 0 {
                    let missingText = summary.missingPrices == 1
                        ? "Falta el precio de 1 posición"
                        : "Falta el precio de \(summary.missingPrices) posiciones"
                    let suffix: String = {
                        if summary.hasStalePrice, let oldest = summary.oldestPriceAt {
                            return " · precio antiguo del \(DateText.madridDay(oldest))"
                        }
                        if hasMixedTimes, let oldest = summary.oldestPriceAt {
                            return " · \(PositionFormatting.oldestPriceTimestamp(oldest))"
                        }
                        if let pricedAt = summary.pricedAt {
                            let pricedCount = max(0, summary.positions.count - summary.missingPrices)
                            return " · \(PositionFormatting.priceTimestamp(pricedAt, plural: pricedCount != 1))"
                        }
                        return ""
                    }()
                    Text(missingText + suffix)
                        .titan(.caption)
                        .foregroundStyle(Theme.warning)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if summary.hasStalePrice, let oldest = summary.oldestPriceAt ?? summary.pricedAt {
                    Text("Precio antiguo (del \(DateText.madridDay(oldest)))")
                        .titan(.caption)
                        .foregroundStyle(Theme.warning)
                        .lineLimit(1)
                } else if hasMixedTimes, let oldest = summary.oldestPriceAt {
                    Text(PositionFormatting.oldestPriceTimestamp(oldest))
                        .titan(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                } else if let pricedAt = summary.pricedAt {
                    let timestamp = PositionFormatting.priceTimestamp(pricedAt, plural: summary.positions.count != 1)
                    Text(timestamp)
                        .titan(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: Theme.Space.small) {
            if card == .investments {
                Text("Inversiones").titan(.cardTitle)
                Spacer(minLength: 0)
                let count = portfolioSummary?.positions.count ?? 0
                Text(count == 1 ? "1 posición" : "\(count) posiciones")
                    .titan(.meta)
                    .foregroundStyle(secondary)
            } else if let bank = card.bank {
                HStack(spacing: 10) {
                    BankLogo(bank: bank, size: 30)
                    Text(bank.displayName).titan(.cardTitle)
                }
                Spacer(minLength: 0)
                if let info = balances[bank] {
                    if info.estimated {
                        Text("estimado")
                            .titan(.captionStrong)
                            .foregroundStyle(Color(hex: "#D6D6DA"))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    } else {
                        Text(DateText.balanceStatus(info)).titan(.meta).foregroundStyle(secondary)
                    }
                } else {
                    Text("sin saldo").titan(.meta).foregroundStyle(secondary)
                }
            } else {
                Text("Todo").titan(.cardTitle)
                Spacer(minLength: 0)
                Text("3 cuentas").titan(.meta).foregroundStyle(secondary)
            }
        }
        .frame(minHeight: 32)
    }

    private var banks: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(BankID.allCases, id: \.self) { bank in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        BankLogo(bank: bank, size: 16)
                        Text(bank.shortName).lineLimit(1)
                    }
                    .titan(.meta)
                    .foregroundStyle(secondary)
                    if let info = balances[bank] {
                        // Si no cabe en su columna se encoge entero (lo hace el propio importe).
                        RollingAmount(cents: info.cents, revealed: revealed)
                            .titan(.cardBalance)
                            .accessibilityIdentifier("card-bank-\(bank.rawValue)")
                            .padding(.top, 5)
                        Text(DateText.balanceStatus(info))
                            .titan(.caption)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    } else {
                        Text("—").titan(.cardBalance).padding(.top, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Cara trasera.
private struct CardBack: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    let links: [BankID: BankLinkInfo]
    let monthSpent: Int
    let portfolioSummary: PortfolioSummary?
    let portfolioLastImport: Date?
    let flipped: Bool
    let onEdit: () -> Void
    let onOpenBank: (BankID) -> Void
    let onImportInvestments: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @State private var refreshing = false
    @State private var refreshedCheck = false

    private var secondary: Color { contrast == .increased ? Theme.card2High : Theme.card2 }

    var body: some View {
        // Hora de verdad al dibujar; `TimelineView` solo marca el redibujo de cada minuto (U80).
        TimelineView(.everyMinute) { _ in
            let liveLines = liveBankStatus(now: AppClock.now)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if card == .investments {
                        Text("Inversiones").titan(.cardTitle)
                    } else if let bank = card.bank {
                        BankLogo(bank: bank, size: 30)
                        Text(bank.displayName).titan(.cardTitle)
                    } else {
                        Text("Tus tres cuentas").titan(.cardTitle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 32)

                if card == .investments {
                    investmentsBackBody
                } else {
                    Text(title)
                        .titan(.cardTitle)
                        .padding(.top, 14)
                    // «Actualizado hace 5 min · exacto»: al cambiar (cada minuto, o al actualizar) las cifras ruedan en su
                    // sitio; con Reducir movimiento, un fundido. Son minutos, no importes.
                    let status = explanation(liveLines: liveLines)
                    Text(status)
                        .titan(.subtitle)
                        .foregroundStyle(secondary)
                        .contentTransition(motion.reduce ? .opacity : .numericText())
                        .animation(motion.calmAnimation(.snap), value: status)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    if let secondaryText = secondaryExplanation(liveLines: liveLines) {
                        Text(secondaryText)
                            .titan(.meta)
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 16)

                    HStack(alignment: .bottom, spacing: Theme.Space.row) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Gastado este mes").titan(.meta).foregroundStyle(secondary)
                            RollingAmount(cents: monthSpent, revealed: flipped)
                                .titan(.cardTitle)
                                .accessibilityIdentifier("card-month-\(card.rawValue)")
                        }
                        Spacer(minLength: 0)
                        trailingActionButton(liveLines: liveLines)
                    }
                }
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: CarouselMetrics.minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(CardSurface(material: card.material, moves: false))
        }
    }

    private func liveBankStatus(now: Date) -> BankStatusLines? {
        guard let bank = card.bank, let link = links[bank] else { return nil }
        return bankStatusLines(
            bank: bank,
            link: link,
            estimated: balances[bank]?.estimated,
            canConnect: BankConnector.shared.canConnect(bank),
            now: now,
            calendar: DateText.madridCalendar
        )
    }

    @ViewBuilder
    private func trailingActionButton(liveLines: BankStatusLines?) -> some View {
        if let bank = card.bank, links[bank] != nil {
            let action = liveLines?.action
            let isSyncing = refreshing || BankSyncStatus.shared.running.contains(bank)
            switch action {
            case .refresh:
                Button {
                    refreshConnectedBank(bank)
                } label: {
                    HStack(spacing: 8) {
                        if isSyncing {
                            ProgressView()
                                .tint(Theme.onTileSelected)
                                .controlSize(.small)
                        } else if refreshedCheck {
                            DrawnCheck(lineWidth: 2, color: Theme.onTileSelected)
                                .frame(width: 14, height: 14)
                                .transition(.opacity)
                                .accessibilityLabel("Actualizado")
                                .accessibilityIdentifier("bank-card-refreshed")
                        }
                        Text(refreshedCheck ? "Actualizado" : "Actualizar")
                            .titan(.option)
                            .foregroundStyle(Theme.onTileSelected)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.tileSelected, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(isSyncing)
                .accessibilityIdentifier("bank-card-refresh")

            case .renew:
                capsuleAction("Renovar") { onOpenBank(bank) }

            case .connect, .importStatement, .editBalance, nil:
                if isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Theme.onTileSelected)
                            .controlSize(.small)
                        Text("Actualizar")
                            .titan(.option)
                            .foregroundStyle(Theme.onTileSelected)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.tileSelected, in: Capsule())
                } else {
                    capsuleAction("Editar saldo", action: onEdit)
                }
            }
        } else {
            capsuleAction(card == .all ? "Editar saldos" : "Editar saldo", action: onEdit)
        }
    }

    private func capsuleAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .titan(.option)
                .foregroundStyle(Theme.onTileSelected)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(Theme.tileSelected, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func refreshConnectedBank(_ bank: BankID) {
        guard !refreshing, !BankSyncStatus.shared.running.contains(bank) else { return }
        refreshing = true
        Task {
            _ = await BankSync.shared.refresh(trigger: .manual, only: bank)
            refreshing = false
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { refreshedCheck = true }
            try? await Task.sleep(for: .seconds(2.0))
            withAnimation(.easeOut(duration: 0.25)) { refreshedCheck = false }
        }
    }

    @ViewBuilder
    private var investmentsBackBody: some View {
        if let summary = portfolioSummary {
            let hasIncomplete = summary.positions.contains { $0.position.costIncomplete }
            if summary.costCents == 0 && hasIncomplete {
                Text("Coste: sin datos")
                    .titan(.cardTitle)
                    .foregroundStyle(secondary)
                    .padding(.top, 14)
            } else {
                HStack(spacing: 6) {
                    Text(hasIncomplete ? "Coste parcial:" : "Coste:")
                        .titan(.cardTitle)
                    Text(formatEUR(summary.costCents))
                        .titan(.cardTitle)
                        .privateAmount()
                }
                .padding(.top, 14)
            }
        }
        if let lastImport = portfolioLastImport {
            Text("Última importación: \(DateText.madridDay(lastImport))")
                .titan(.subtitle)
                .foregroundStyle(secondary)
                .padding(.top, 4)
        }
        Spacer(minLength: 16)
        HStack {
            Spacer(minLength: 0)
            Button(action: onImportInvestments) {
                Text("Importar de nuevo")
                    .titan(.option)
                    .foregroundStyle(Theme.onTileSelected)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.tileSelected, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Abre Ajustes, Inversiones")
        }
    }

    private var title: String {
        guard let bank = card.bank else { return "Este mes" }
        guard let info = balances[bank] else { return "Sin saldo" }
        return info.estimated ? "Saldo estimado" : "Saldo exacto"
    }

    private func explanation(liveLines: BankStatusLines?) -> String {
        guard let bank = card.bank else {
            let known = BankID.allCases.filter { balances[$0] != nil }
            guard !known.isEmpty else {
                return "Aún no tienes saldos guardados. Escríbelos en Ajustes o conecta tus bancos."
            }
            let missing = BankID.allCases.filter { balances[$0] == nil }.map(\.displayName)
            let fromBank = known.filter { balances[$0]?.origin == .bank }.map(\.displayName)
            let fromStatementExact = known.filter { balances[$0]?.origin == .statement && balances[$0]?.estimated == false }.map(\.displayName)
            let fromStatementEstimated = known.filter { balances[$0]?.origin == .statement && balances[$0]?.estimated == true }.map(\.displayName)
            let estimated = known.filter { balances[$0]?.estimated == true && balances[$0]?.origin != .bank && balances[$0]?.origin != .statement }.map(\.displayName)

            if !fromBank.isEmpty || !fromStatementExact.isEmpty || !fromStatementEstimated.isEmpty || !missing.isEmpty {
                var clauses: [String] = []
                if !fromBank.isEmpty {
                    let verb = fromBank.count == 1 ? "viene del banco" : "vienen del banco"
                    clauses.append("\(spanishJoin(fromBank)) \(verb)")
                }
                if !fromStatementExact.isEmpty {
                    let verb = fromStatementExact.count == 1 ? "viene del extracto" : "vienen del extracto"
                    clauses.append("\(spanishJoin(fromStatementExact)) \(verb)")
                }
                if !fromStatementEstimated.isEmpty {
                    let verb = fromStatementEstimated.count == 1 ? "es estimado desde el extracto" : "son estimados desde el extracto"
                    clauses.append("\(spanishJoin(fromStatementEstimated)) \(verb)")
                }
                if !estimated.isEmpty {
                    let verb = estimated.count == 1 ? "es estimado" : "son estimados"
                    clauses.append("\(spanishJoin(estimated)) \(verb)")
                }
                if !missing.isEmpty {
                    let verb = missing.count == 1 ? "no tiene saldo" : "no tienen saldo"
                    clauses.append("\(spanishJoin(missing)) \(verb)")
                }
                if !clauses.isEmpty {
                    return clauses.joined(separator: "; ") + "."
                }
            }
            let allEstimated = known.filter { balances[$0]?.estimated == true }.map(\.displayName)
            switch allEstimated.count {
            case 0: return "Los tres saldos son exactos: vienen del último aviso de cada banco."
            case 1: return "\(allEstimated[0]) es estimado: su aviso no trae el saldo, así que lo calculamos."
            default:
                let list = spanishJoin(allEstimated)
                return "\(list) son estimados: sus avisos no traen el saldo, así que los calculamos."
            }
        }
        if links[bank] != nil {
            if refreshing || BankSyncStatus.shared.running.contains(bank) {
                return "Conectado · actualizando…"
            }
            if let primary = liveLines?.primary {
                return primary
            }
        }
        return DateText.balanceExplanation(balances[bank], bank: bank)
    }

    private func secondaryExplanation(liveLines: BankStatusLines?) -> String? {
        guard let bank = card.bank, links[bank] != nil else { return nil }
        return liveLines?.secondary
    }

    private func spanishJoin(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        let conj = last.lowercased().hasPrefix("i") ? " e " : " y "
        return names.dropLast().joined(separator: ", ") + conj + last
    }
}

/// La cifra grande de la tarjeta: euros a 50 pt y céntimos a 26 pt en gris de tarjeta. Rueda como un cuentakilómetros
/// (`RollingAmount`): cuenta desde 0 la primera vez que se ve, rueda en cada cambio y, con el ojo cerrado, dibuja
/// «•••,•• €» (nunca la cifra). El propio importe crece con Dynamic Type (hasta ×1,35) y, si no cabe, se encoge entero.
struct HeroBalance: View {
    let cents: Int
    var revealed = true
    var centsColor = Theme.card2

    var body: some View {
        RollingAmount(cents: cents, revealed: revealed,
                      style: .hero(euros: 50, cents: 26, centsColor: centsColor))
    }
}

/// Logo de un banco en su ficha (radio ≈ 27 % del lado).
struct BankLogo: View {
    let bank: BankID
    var size: CGFloat = 20
    @Environment(MerchantLogos.self) private var logos

    var body: some View {
        ZStack {
            if let image = logos.bankImage(bank) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.27, style: .continuous))
        .accessibilityHidden(true)
    }
}
