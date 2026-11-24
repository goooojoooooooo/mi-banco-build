import SwiftUI
import MiBancoCore

/// El carrusel de cuentas: paginado horizontal con la física del sistema y encaje en cada tarjeta
/// (`viewAligned`), los vecinos asomando 32 pt, girados en 3D (±22° × el recorrido del nivel, perspectiva 0,6), al 92 %
/// y apagados (0,25 × el recorrido del nivel). La posición continua (para el indicador del segmentado y el brillo) sale de la geometría del scroll,
/// nunca del `body`. Para VoiceOver es un solo elemento ajustable: "Cuenta, Revolut, 340,20 euros, 2 de 4".
/// Movimiento (desde `\.motion`: intensidad, Reducir movimiento y cámara lenta). El viaje de una tarjeta a otra lo hace
/// siempre el scroll del sistema (interrumpible con el dedo); cuando es por programa lo lleva el muelle `snap`, y los
/// fotogramas enseñan que el scroll lo sigue: se pasa y vuelve según la intensidad, y la cámara lenta lo alarga.
/// - Un deslizamiento programado (segmentado, llegada) llega con el rebote de su muelle `snap`: se pasa y vuelve.
/// - Cuando es el dedo quien lo deja en otra tarjeta, esa tarjeta da un rebote de encaje pequeño (4 pt en el sentido en
///   que venía, escala 1,012).
/// - Mantener pulsada la tarjeta de delante 0,42 s la levanta (`.lift`); al soltar vuelve, y soltar no la voltea.
/// - La primera vez que se ve Inicio, la tarjeta asoma unos grados (la pista de que se puede voltear).
/// - Con Reducir movimiento: tarjetas planas, sin rebote ni levantar, y el cambio programado es un fundido.
struct CardCarousel: View {
    let snapshot: LedgerSnapshot
    var links: [BankID: BankLinkInfo] = [:]
    let cards: [AccountCard]
    var portfolioSummary: PortfolioSummary? = nil
    var portfolioLastImport: Date? = nil
    @Binding var selection: AccountCard?
    @Binding var flipped: AccountCard?
    let motion: HomeMotion
    let onEdit: (BankID?) -> Void
    var onOpenBank: (BankID) -> Void = { _ in }
    var onImportInvestments: () -> Void = {}

    /// Tarjetas que ya se han visto: su cifra contó desde 0 la primera vez.
    @State private var seen: Set<AccountCard> = []
    /// Lo que enseña el scroll. Va aparte de `selection` a propósito: antes de que el carrusel tenga ancho
    /// (primer pase de maquetación) no se le pide ir a ninguna tarjeta y lo que escriba el scroll se ignora;
    /// después, cada lado solo copia al otro un valor distinto y nunca `nil`, así que no puede haber eco.
    @State private var scrolledID: AccountCard?
    @State private var measured = false
    /// Destino de un desplazamiento programado en curso (segmentado, VoiceOver, llegada). Mientras dura, las tarjetas
    /// intermedias que informe el scroll ("Todo" → Trade Republic pasa por Revolut e imagin) no cambian la elegida.
    @State private var scrollTarget: AccountCard?
    @State private var scrollTargetToken = 0
    /// Rebote de encaje: cuántas veces se ha parado el carrusel en cada tarjeta y en qué sentido venía la última vez.
    @State private var settles: [AccountCard: Int] = [:]
    @State private var settleDirection: CGFloat = 0
    /// La tarjeta levantada con una pulsación larga. Vuelve a `nil` al subir el dedo o si el sistema suelta el botón
    /// (por ejemplo, porque el carrusel empieza a deslizarse).
    @State private var pressLifted: AccountCard?
    /// La espera de 0,42 s con el dedo encima; se cancela en cuanto el dedo sube.
    @State private var liftTimer: Task<Void, Never>?
    /// Cuándo se soltó la última tarjeta levantada: ese soltar no cuenta como toque.
    @State private var liftReleasedAt = Date.distantPast
    /// Reducir movimiento: mientras el carrusel cambia de tarjeta por programa, se funde (no viaja).
    @State private var crossFaded = false
    /// La pista del volteo: cuántas veces ha asomado cada tarjeta y cuánto espera antes de asomar.
    @State private var peeks: [AccountCard: Int] = [:]
    @State private var peekDelay = 0.0
    #if DEBUG
    /// Solo demo (`-MiBancoDemoCardMoment lift`): la tarjeta levantada sin dedo, para los fotogramas.
    @State private var demoLifted: AccountCard?
    /// Solo para las pruebas de toques: cuántas veces ha levantado una tarjeta la pulsación larga.
    @State private var liftCount = 0
    /// Solo para las pruebas de toques: cuántas veces ha hecho falta la red de seguridad de `landed()`.
    @State private var restFixes = 0
    /// Solo para las pruebas de toques: cuántas veces ha movido el DEDO el carrusel, en qué tarjeta (1…n) lo dejó la
    /// última vez, y si ese último movimiento del dedo aún está frenando.
    @State private var fingerLandings = 0
    @State private var fingerLandedOn = 0
    @State private var fingerSettling = false
    @Environment(\.cardTilt) private var tilt
    #endif
    @Environment(\.motion) private var kit
    @Environment(\.entrance) private var entrance
    @Environment(AppPreferences.self) private var preferences

    /// La pista del volteo se enseña una sola vez en la vida de la app.
    private static let peekKey = "didPeekFlip"

    private var current: AccountCard {
        if let selection, cards.contains(selection) { return selection }
        return cards.first ?? .all
    }

    private var lifted: AccountCard? {
        #if DEBUG
        if let demoLifted { return demoLifted }
        #endif
        return pressLifted
    }

    // El cuerpo va en piezas (tarjeta, paginado, seguimiento, sincronía, sonda de pruebas): entero, el compilador no
    // llega a comprobar los tipos de una sola expresión tan larga.

    /// Una tarjeta con su rebote de encaje y su «levantar» (la levanta mantener el dedo sobre su botón: ver `pressing`).
    private func cardView(_ card: AccountCard) -> some View {
        AccountCardView(
            card: card, balances: snapshot.balances,
            links: links,
            total: snapshot.total,
            monthSpent: snapshot.monthSpent[card] ?? 0,
            portfolioSummary: portfolioSummary,
            portfolioLastImport: portfolioLastImport,
            flipped: flipped == card,
            revealed: seen.contains(card),
            peek: peeks[card, default: 0],
            peekDelay: peekDelay,
            isFront: card == current,
            onFlip: { tap(card) }, onEdit: { onEdit(card.bank) },
            onPressing: { down in pressing(card, down) },
            onOpenBank: onOpenBank,
            onImportInvestments: onImportInvestments)
            .modifier(SettleBounce(tick: settles[card, default: 0], direction: settleDirection))
            .lift(lifted == card)
    }

    /// El paginado: las tarjetas en fila, cada una girada, encogida y apagada según lo lejos que esté del centro.
    private var pager: some View {
        let reduce = kit.reduce
        // Cuánto giran y cuánto se apagan las vecinas sigue a la intensidad: ±22° × el recorrido del nivel (13° en
        // Sutil, 22° en Equilibrado, 32° en Expresivo; tope de 34° de la maqueta) y un apagado de 0,25 × el recorrido
        // (0,15 / 0,25 / 0,33, con tope ×1,3). El viaje en sí lo hace el scroll del sistema (su física, interrumpible
        // con el dedo), llevado por el muelle `snap` cuando es por programa (ver `glide(to:)`).
        let turn: Double = 22 * kit.level.distanceScale
        let dim: Double = 0.25 * min(1.3, kit.level.distanceScale)
        return ScrollView(.horizontal) {
            HStack(spacing: CarouselMetrics.spacing) {
                ForEach(cards, id: \.self) { card in
                    cardView(card)
                        .containerRelativeFrame(.horizontal)
                        .frame(maxHeight: .infinity)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            let away: Double = abs(phase.value)
                            let angle: Double = reduce ? 0 : min(34, max(-34, -turn * phase.value))
                            let shrink: Double = reduce ? 1 : 1 - 0.08 * away
                            return content
                                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                .scaleEffect(shrink)
                                .brightness(-dim * away)
                        }
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if visible { seen.insert(card) }
                        }
                        // La tarjeta levantada pasa por encima de sus vecinas.
                        .zIndex(lifted == card ? 1 : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .safeAreaPadding(.horizontal, CarouselMetrics.inset)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $scrolledID)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .opacity(crossFaded ? 0 : 1)
    }

    /// El paginado y lo que se mide de él: posición continua, sentido, paradas y primera colocación.
    private var tracked: some View {
        pager
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Paso entre tarjetas medido en el contenido (n tarjetas + n−1 huecos), no en el contenedor: el ancho del
                // contenedor ya viene sin el margen lateral y restarlo otra vez desplazaba el indicador (1,2 en vez de 1).
                let count = CGFloat(max(cards.count, 1))
                let step = (geometry.contentSize.width + CarouselMetrics.spacing) / count
                return step > 0 ? (geometry.contentOffset.x + geometry.contentInsets.leading) / step : 0
            } action: { old, position in
                guard position.isFinite else { return }
                // Sentido en que se mueven las tarjetas (la posición sube = van hacia la izquierda), para el rebote de encaje.
                if abs(position - old) > 0.0005 { motion.carouselDirection = position > old ? -1 : 1 }
                motion.carouselPosition = position
                let last = CGFloat(max(cards.count - 1, 0))
                let over = position < -0.04 || position > last + 0.04
                if over != motion.carouselOverscrolled { motion.carouselOverscrolled = over }
            }
            // Quién mueve el carrusel (el dedo o un deslizamiento programado) y cuándo se para.
            .onScrollPhaseChange { old, new in
                #if DEBUG
                probeFinger(old, new)
                #endif
                if new == .interacting { motion.carouselByFinger = true }
                if new == .animating { motion.carouselByFinger = false }
                if new == .idle, old != .idle { landed() }
            }
            .sensoryFeedback(Haptics.edge, trigger: motion.carouselOverscrolled) { _, new in new }
            .sensoryFeedback(Haptics.flip, trigger: flipped)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.containerSize.width > 0
            } action: { _, hasWidth in
                if hasWidth { settleInitialPosition() }
            }
            // Respaldo: si el cambio de geometría no llega (el primer valor ya era el bueno), tras el primer pase igual.
            .task {
                try? await Task.sleep(for: .milliseconds(60))
                settleInitialPosition()
            }
    }

    /// Lo anterior, de acuerdo con la tarjeta elegida en los dos sentidos.
    private var synced: some View {
        tracked
            .onChange(of: scrolledID) { _, new in
                guard measured, let new else { return }
                // Desplazamiento programado en curso (incluida nuestra propia asignación): nada de lo que informe el
                // scroll cambia la elegida; al terminar `releaseTarget` pone todo de acuerdo.
                if scrollTarget != nil { return }
                // El dedo dejó el carrusel en otra tarjeta: eso pasa a ser la elegida.
                guard new != selection else { return }
                #if DEBUG
                // Solo para probar la prueba (`-MiBancoDemoFingerLoses`): aquí el programa le gana al dedo.
                if DemoMode.fingerLosesToGlide, let chosen = selection {
                    glide(to: chosen)
                    return
                }
                #endif
                selection = new
            }
            .onChange(of: selection) { _, new in
                if flipped != nil { flipped = nil }
                if let new { seen.insert(new) }
                // Segmentado, VoiceOver, toque en un vecino o llegada: el carrusel va hasta allí con su muelle.
                guard measured, let new, new != scrolledID else { return }
                glide(to: new)
            }
            // Montaje de Inicio (arranque o desbloqueo): la primera vez en la vida de la app, la tarjeta asoma.
            .onChange(of: entrance.token) { _, _ in peekIfFirstTime() }
    }

    /// En DEBUG, además: el contador de levantadas para XCUITest y los momentos de demo para las ráfagas.
    @ViewBuilder private var probed: some View {
        #if DEBUG
        synced
            .onChange(of: pressLifted) { old, new in
                if old == nil, new != nil { liftCount += 1 }
            }
            .onChange(of: motion.demoMomentTick) { _, _ in runDemoMoment() }
            .overlay(alignment: .topLeading) {
                // Solo para XCUITest (`-MiBancoDemoCardElements`): sondas invisibles con lo que la prueba necesita saber.
                if DemoMode.exposesCardElements {
                    probe("card-lift-count", "\(liftCount)", at: 0)
                    probe("card-rest-fixes", "\(restFixes)", at: 1)
                    // Cuántas veces ha movido el dedo el carrusel y en qué tarjeta (1…n) lo dejó la última vez.
                    probe("card-finger-landings", "\(fingerLandings)", at: 2)
                    probe("card-finger-landed-on", "\(fingerLandedOn)", at: 3)
                    // «1» mientras hay un deslizamiento programado en curso.
                    probe("card-glide-active", scrollTarget != nil ? "1" : "0", at: 4)
                }
            }
        #else
        synced
        #endif
    }

    var body: some View {
        probed
        .accessibilityElement(children: Self.cardChildrenBehavior)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Desliza hacia arriba o hacia abajo para cambiar de cuenta")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: flipAccessibilityActionTitle) { tap(current) }
        .accessibilityAction(named: primaryAccessibilityActionTitle) {
            if current == .investments {
                onImportInvestments()
            } else if let bank = current.bank, let link = links[bank] {
                let status = bankStatusLines(
                    bank: bank,
                    link: link,
                    estimated: snapshot.balances[bank]?.estimated,
                    canConnect: BankConnector.shared.canConnect(bank),
                    now: AppClock.now,
                    calendar: DateText.madridCalendar
                )
                switch status.action {
                case .refresh:
                    let estimated = snapshot.balances[bank]?.estimated
                    let canConnect = BankConnector.shared.canConnect(bank)
                    Task {
                        let outcome = await BankSync.shared.refresh(trigger: .manual, only: bank)[bank]
                        // U88: la acción con nombre dice cómo acabó, como el botón del reverso.
                        let problem: SyncProblem? = if case .failed(let p)? = outcome { p } else { nil }
                        let text = manualRefreshAnnouncement(bank: bank, link: link, problem: problem, estimated: estimated,
                                                             canConnect: canConnect, now: AppClock.now,
                                                             calendar: DateText.madridCalendar)
                        AccessibilityNotification.Announcement(text).post()
                    }
                case .renew:
                    onOpenBank(bank)
                case .connect, .importStatement, .editBalance, nil:
                    onEdit(bank)
                }
            } else {
                onEdit(current.bank)
            }
        }
    }

    private var flipAccessibilityActionTitle: String {
        if current == .investments {
            return flipped == current ? "Ver el valor" : "Ver detalles"
        }
        return flipped == current ? "Ver el saldo" : "Ver detalles de la cuenta"
    }

    private var primaryAccessibilityActionTitle: String {
        switch current {
        case .all:
            return "Editar saldos"
        case .investments:
            return "Importar de nuevo"
        case .rev, .ima, .tr:
            if let bank = current.bank, let link = links[bank] {
                let status = bankStatusLines(
                    bank: bank,
                    link: link,
                    estimated: snapshot.balances[bank]?.estimated,
                    canConnect: BankConnector.shared.canConnect(bank),
                    now: AppClock.now,
                    calendar: DateText.madridCalendar
                )
                switch status.action {
                case .refresh: return "Actualizar"
                case .renew: return "Renovar"
                case .connect, .importStatement, .editBalance, nil: return "Editar saldo"
                }
            }
            return "Editar saldo"
        }
    }

    // MARK: - Desplazamiento programado

    /// Lleva el carrusel a `card`. Con movimiento, con el muelle de encaje; con Reducir movimiento, sin viaje: el
    /// carrusel se funde, cambia y vuelve. Mientras dura, lo que informe el scroll no cambia la tarjeta elegida.
    private func glide(to card: AccountCard) {
        scrollTarget = card
        scrollTargetToken += 1
        let token = scrollTargetToken
        if kit.reduce {
            withAnimation(.easeOut(duration: 0.11 * kit.timeMultiplier)) {
                crossFaded = true
            } completion: {
                guard scrollTargetToken == token else { return }
                jump(to: card)
                releaseTarget(token)
            }
        } else {
            withAnimation(kit.animation(.snap)) {
                scrolledID = card
            } completion: {
                releaseTarget(token)
            }
        }
        // Por si la animación no informa de su final (el usuario la interrumpe con el dedo): se suelta igual. La espera
        // sigue a la intensidad y a la cámara lenta, para no soltar a mitad de un deslizamiento grabado despacio.
        let patience = kit.seconds(0.9)
        Task {
            try? await Task.sleep(for: .seconds(patience))
            guard scrollTargetToken == token else { return }
            if crossFaded { jump(to: card) }
            releaseTarget(token)
        }
    }

    /// Reducir movimiento: el carrusel (ya invisible) salta a la tarjeta y vuelve a verse con un fundido.
    private func jump(to card: AccountCard) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { scrolledID = card }
        withAnimation(.easeOut(duration: 0.17 * kit.timeMultiplier)) { crossFaded = false }
    }

    /// Fin de un desplazamiento programado. Si el dedo lo interrumpió y dejó el carrusel en otra tarjeta, esa pasa a ser
    /// la elegida (así carrusel, segmentado y lista nunca se quedan en desacuerdo).
    private func releaseTarget(_ token: Int) {
        guard scrollTargetToken == token, scrollTarget != nil else { return }
        scrollTarget = nil
        guard let shown = scrolledID, shown != selection else { return }
        #if DEBUG
        // Solo para probar la prueba (`-MiBancoDemoFingerLoses`): el carrusel vuelve a la tarjeta del programa.
        if DemoMode.fingerLosesToGlide, let chosen = selection {
            glide(to: chosen)
            return
        }
        #endif
        selection = shown
    }

    /// Una sola vez, con el carrusel ya maquetado: se coloca en la tarjeta elegida sin animación (p. ej. la demo con Revolut).
    private func settleInitialPosition() {
        guard !measured else { return }
        measured = true
        // La tarjeta de delante cuenta su cifra aunque el aviso de visibilidad no llegue.
        seen.insert(current)
        if current != .all { scrolledID = current }
        motion.carouselRest = CGFloat(current.index(in: cards))
    }

    // MARK: - Encaje, levantar y pista

    /// El carrusel se ha parado. Si el DEDO lo ha dejado en otra tarjeta que la última vez, esa tarjeta da su rebote de
    /// encaje en el sentido en que venía (el frenado del sistema llega a su sitio sin pasarse). Tras un deslizamiento
    /// programado no: ese ya llega con el rebote de su muelle `snap` (se pasa y vuelve, más o menos según la
    /// intensidad), y un segundo rebote después solo sería un tic a destiempo. Un toque (el dedo baja y sube sin mover
    /// nada) no cuenta.
    private func landed() {
        guard !cards.isEmpty else { return }
        let position = motion.carouselPosition
        let index = min(max(Int(position.rounded()), 0), cards.count - 1)
        // Red de seguridad: quieto y sin deslizamiento programado en curso, la tarjeta elegida es la que se ve. Si el
        // scroll no llegó a informar de ella (su identificador puede llegar vacío en el borde), se pone aquí de acuerdo:
        // carrusel, segmentado y lista nunca se quedan diciendo cosas distintas.
        if measured, scrollTarget == nil, abs(position - CGFloat(index)) < 0.2, cards[index] != current, !fingerLoses {
            #if DEBUG
            restFixes += 1
            #endif
            selection = cards[index]
        }
        guard abs(position - motion.carouselRest) > 0.5 else { return }
        motion.carouselRest = CGFloat(index)
        guard !kit.reduce, motion.carouselByFinger else { return }
        settleDirection = motion.carouselDirection
        settles[cards[index], default: 0] += 1
    }

    /// Solo la tarjeta de delante, por su cara delantera (el reverso tiene sus propios botones), y nunca con Reducir
    /// movimiento.
    private func canLift(_ card: AccountCard) -> Bool {
        !kit.reduce && card == current && flipped != card
    }

    /// El dedo baja o sube sobre la cara delantera de una tarjeta (lo dice el propio botón de la tarjeta). Con el dedo
    /// 0,42 s encima, la tarjeta se levanta y sigue levantada hasta que el dedo sube; si el carrusel (o la lista)
    /// empieza a deslizarse, el sistema suelta el botón y la tarjeta baja.
    /// A propósito NO es un gesto añadido a la tarjeta: una pulsación larga encadenada con un arrastre, aunque
    /// simultánea, le quitaba al carrusel el deslizamiento hacia atrás (lo pilló la prueba de deslizar en los dos
    /// sentidos). El botón ya convive con el scroll.
    private func pressing(_ card: AccountCard, _ down: Bool) {
        liftTimer?.cancel()
        liftTimer = nil
        if down {
            guard canLift(card) else { return }
            liftTimer = Task {
                // El umbral de la pulsación larga: tiempo real del dedo, no el de una animación.
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled, canLift(card) else { return }
                pressLifted = card
            }
        } else if pressLifted != nil {
            pressLifted = nil
            liftReleasedAt = Date()
        }
    }

    /// Montaje de Inicio con movimiento, fuera de la demo y solo la primera vez: la tarjeta de delante asoma cuando el
    /// montaje ha terminado (1,3 s en Equilibrado).
    private func peekIfFirstTime() {
        guard entrance.active, entrance.scope == .assembly, measured, !kit.reduce, flipped == nil else { return }
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        guard !UserDefaults.standard.bool(forKey: Self.peekKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.peekKey)
        peek(current, after: kit.seconds(1.3))
    }

    private func peek(_ card: AccountCard, after delay: Double) {
        peekDelay = delay
        peeks[card, default: 0] += 1
    }

    #if DEBUG
    /// Solo demo: el momento pedido con `-MiBancoDemoCardMoment`, sobre la tarjeta de delante.
    private func runDemoMoment() {
        switch DemoMode.cardMoment {
        case .lift:
            demoLifted = current
            Task {
                try? await Task.sleep(for: .seconds(3))
                demoLifted = nil
            }
        case .tilt:
            tilt?.demoSweep()
        case .peek:
            peek(current, after: 0.05)
        case .glide, .glideFar:
            // Un deslizamiento programado un instante después del toque (la ráfaga ya está en marcha), por el mismo
            // camino que un toque en el segmentado: a la tarjeta siguiente o a la última.
            let far = DemoMode.cardMoment == .glideFar
            let from = current.index(in: cards)
            let target = cards[far ? cards.count - 1 : min(from + 1, cards.count - 1)]
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = target }
            }
        case .settle:
            // El rebote de encaje solo, hacia la derecha, un instante después del toque (la ráfaga ya está en marcha).
            let card = current
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                settleDirection = 1
                settles[card, default: 0] += 1
            }
        case nil:
            break
        }
    }

    /// Solo para las pruebas de toques: apunta cuándo el DEDO suelta el carrusel y en qué tarjeta queda al frenar.
    private func probeFinger(_ old: ScrollPhase, _ new: ScrollPhase) {
        guard DemoMode.exposesCardElements, !cards.isEmpty else { return }
        let front = min(max(Int(motion.carouselPosition.rounded()), 0), cards.count - 1) + 1
        if old == .interacting, new != .interacting {
            fingerLandings += 1
            fingerSettling = new == .decelerating
            if !fingerSettling { fingerLandedOn = front }
        } else if fingerSettling, old == .decelerating {
            fingerSettling = false
            fingerLandedOn = front
        }
    }

    /// Una sonda invisible de 2 pt para XCUITest: su etiqueta es el valor.
    private func probe(_ id: String, _ value: String, at slot: Int) -> some View {
        Color.clear
            .frame(width: 2, height: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value)
            .accessibilityIdentifier(id)
            .offset(x: CGFloat(slot) * 4)
    }
    #endif

    /// Solo en DEBUG puede ser verdad (`-MiBancoDemoFingerLoses`): la variante «el programa le gana al dedo» con la
    /// que se comprueba que la prueba de deslizar a medias se pone roja.
    private var fingerLoses: Bool {
        #if DEBUG
        return DemoMode.fingerLosesToGlide
        #else
        return false
        #endif
    }

    private func tap(_ card: AccountCard) {
        // Soltar una tarjeta levantada no es un toque: no la voltea.
        guard pressLifted == nil, Date().timeIntervalSince(liftReleasedAt) > 0.35 else { return }
        guard card == current else {
            withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = card }
            return
        }
        flipped = flipped == card ? nil : card
    }

    private func move(by step: Int) {
        guard !cards.isEmpty else { return }
        let next = min(max(current.index(in: cards) + step, 0), cards.count - 1)
        withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = cards[next] }
    }

    /// Para VoiceOver el carrusel es UN elemento ajustable con acciones con nombre. Solo en la demo de pruebas
    /// (`-MiBancoDemoCardElements`, DEBUG) deja ver los botones del reverso para que XCUITest los toque de verdad (U80).
    private static var cardChildrenBehavior: AccessibilityChildBehavior {
        #if DEBUG
        if DemoMode.exposesCardElements { return .contain }
        #endif
        return .ignore
    }

    private var spokenLabel: String {
        let hidden = preferences.privateMode
        let position = "\(current.index(in: cards) + 1) de \(cards.count)"
        if current == .investments {
            let missing = portfolioSummary?.missingPrices ?? 0
            let value: String
            if hidden {
                value = "importe oculto"
            } else if let cents = portfolioSummary?.valueCents {
                value = (missing > 0 ? "al menos " : "") + spokenAmount(cents, hidden: false)
            } else {
                value = "sin precio"
            }
            let count = portfolioSummary?.positions.count ?? 0
            let positionsText = count == 1 ? "1 posición" : "\(count) posiciones"
            let missingPart = missing > 0 ? ", falta el precio de \(missing)" : ""
            // U80 (U14): lo mismo que dice la tarjeta, «… desde la compra», también para VoiceOver (con el ojo cerrado, oculto).
            let gainPart: String = {
                guard let gain = portfolioSummary?.gainCents else { return "" }
                if hidden { return ", importe oculto desde la compra" }
                let kind = gain >= 0 ? "ganancia de" : "pérdida de"
                return ", \(kind) \(spokenAmount(abs(gain), hidden: false)) desde la compra"
            }()
            return "Inversiones, \(value), \(positionsText)\(gainPart)\(missingPart), \(position)"
        }
        guard let bank = current.bank else {
            let total = snapshot.total.map { spokenAmount($0, hidden: hidden) } ?? "sin saldo"
            return "Todo, \(total) en tres cuentas, \(position)"
        }
        guard let info = snapshot.balances[bank] else { return "Cuenta, \(bank.displayName), sin saldo, \(position)" }
        let estimate = info.estimated ? ", estimado" : ""
        return "Cuenta, \(bank.displayName), \(spokenAmount(info.cents, hidden: hidden))\(estimate), \(position)"
    }
}

/// El rebote de encaje de una tarjeta: al subir `tick`, se pasa 4 pt (× el recorrido del nivel) en el sentido en que
/// venía y crece a 1,012, y vuelve a su sitio con el muelle `snap`. Una sola secuencia de fotogramas clave por parada;
/// solo desplazamiento y escala.
private struct SettleBounce: ViewModifier {
    let tick: Int
    let direction: CGFloat
    @Environment(\.motion) private var motion

    private struct Values {
        var x: CGFloat = 0
        var scale: CGFloat = 1
    }

    func body(content: Content) -> some View {
        let spec = MotionMath.scaled(SpringToken.snap.base, level: motion.level, timeMultiplier: motion.timeMultiplier)
        let spring = Spring(response: spec.response, dampingRatio: spec.dampingFraction)
        let push = motion.distance(4) * direction
        let kick = motion.seconds(0.08)
        let rest = spec.response * 2
        content.keyframeAnimator(initialValue: Values(), trigger: tick) { view, value in
            view
                .offset(x: value.x)
                .scaleEffect(value.scale)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(push, duration: kick)
                SpringKeyframe(0, duration: rest, spring: spring)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.012, duration: kick)
                SpringKeyframe(1, duration: rest, spring: spring)
            }
        }
    }
}
