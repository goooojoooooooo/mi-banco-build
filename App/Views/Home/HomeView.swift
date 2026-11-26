import SwiftUI
import MiBancoCore

/// Inicio: barra fija (marca, ojo, lupa), el título, el carrusel de cuentas, el segmentado (se queda pegado arriba),
/// el gasto de 7 días y la lista por días que sigue a la tarjeta elegida. Todo sale de `model.snapshot`.
/// El movimiento (montaje por capas, cambio de lista, llegada de un movimiento, tirar para actualizar, abanico de
/// tarjetas) lee `\.motion`: intensidad, Reducir movimiento y la cámara lenta de las grabaciones.
struct HomeView: View {
    let model: LedgerModel
    let portfolio: PortfolioModel
    let accountBook: AccountBookModel
    /// false mientras se ve otra pestaña o con el bloqueo delante: la llegada no suena ni habla ni mueve nada.
    var isVisible = true
    /// Sube al arrancar (tras la marca) y al desbloquear: Inicio se monta por capas.
    var revealToken = 0
    /// Origen de la transición de zoom fila → hoja. La hoja la presenta `RootView` (una sola hoja en toda la app,
    /// que se cierra al bloquear o al salir de la app).
    let zoom: Namespace.ID
    /// Hay una hoja de movimiento abierta: la llegada no mueve nada debajo.
    var detailOpen = false
    let openDetail: (UUID) -> Void
    let openPosition: (String) -> Void
    let openMoveMoney: (MoveRequest) -> Void
    let openBriefing: () -> Void
    let shareText: (String) -> Void
    let openSettings: (BankID?) -> Void
    var openBankSettings: (BankID) -> Void = { _ in }
    let openInvestmentsSettings: () -> Void
    let openAccounts: () -> Void
    @Binding var selectCardRequest: AccountCard?

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    /// Intensidad, Reducir movimiento y cámara lenta: todo el movimiento de Inicio sale de aquí.
    @Environment(\.motion) private var kit

    @State private var motion = HomeMotion()
    /// La inclinación del teléfono que mueve la tarjeta de delante y su brillo. Solo lee los sensores mientras
    /// `tiltRuns` (Inicio a la vista, la tarjeta en pantalla, app activa, efectos ricos); si no, se para.
    @State private var tilt = MotionTilt()
    /// Tirar para actualizar (indicador de titanio).
    @State private var refresh = TitaniumRefreshState()
    /// La tarjeta del carrusel (y del segmentado).
    @State private var selection: AccountCard? = .all
    /// La lista que se ve: cambia tras el fundido de salida, para que la nueva entre escalonada.
    @State private var listCard: AccountCard = .all
    @State private var listHidden = false
    @State private var flipped: AccountCard?
    @State private var entrance = Entrance()
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var searching = false
    @State private var query = ""
    @State private var freshID: UUID?
    /// La llegada anunciada cuyo movimiento aún no ha publicado el modelo (lo hace un instante después).
    @State private var awaitedArrival: Arrival?
    /// Cuándo se anunció: pasado `ArrivalWindow.lifetime` sin que el movimiento aparezca, la llegada caduca.
    @State private var awaitedAt = Date.distantPast
    /// Lo que la última llegada enseña sobre la cifra de la tarjeta.
    @State private var pulse = ArrivalPulse()
    @State private var detentTick = 0
    /// Durante el deslizamiento de una llegada, el tope no suena (ya suena la llegada).
    @State private var quietSelection = false
    /// Número del último cambio de lista pedido.
    @State private var listSwap = 0
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    /// La fila abierta por deslizamiento (solo una a la vez).
    @State private var openRow: UUID?
    /// El abanico de tarjetas, abierto (con el marco de la tarjeta de la que sale).
    @State private var fan: WalletFanRequest?
    /// La lista ha subido tanto que tapa el carrusel: la inclinación deja de leerse.
    @State private var carouselCovered = false
    @State private var flagTick = 0

    // El cuerpo va en piezas (lista, desplazamiento, capas y reacciones): entero, el compilador no llega a comprobar
    // los tipos de una sola expresión tan larga.

    /// La lista que sigue a la tarjeta elegida: acciones, traspasos pendientes, resumen de 7 días y filas.
    @ViewBuilder
    private func listSection(_ snapshot: LedgerSnapshot, cards: [AccountCard], card: AccountCard, entries: [ListEntry]) -> some View {
        Section {
            if card == .investments, let summary = portfolio.summary {
                PositionRows(summary: summary, onOpen: openPosition)
                    .opacity(listAlpha)
            } else {
                QuickActions(
                    card: card,
                    model: model,
                    accountBook: accountBook,
                    onMove: openMoveMoney,
                    onCopyIBAN: showToast,
                    onShareIBAN: shareText,
                    onOpenAccounts: openAccounts
                )
                .homeEntrance(.row(0), listOpacity: listAlpha)

                PendingMoveBanner(
                    moves: visiblePendingMoves(for: card),
                    states: model.pendingMoveStates,
                    accountBook: accountBook,
                    onDismiss: { id in
                        withAnimation(kit.reduce ? nil : kit.calmAnimation(.snap)) {
                            model.removePendingMove(id)
                        }
                    }
                )
                .opacity(listAlpha)

                WeekBlock(card: card, week: snapshot.weeks[card] ?? WeekSpend(), pace: snapshot.pace,
                          balance: card.bank.flatMap { snapshot.balances[$0] })
                    .homeEntrance(.row(1), listOpacity: listAlpha)
                ForEach(entries) { entry in
                    row(entry, snapshot: snapshot, swipes: true)
                        .homeEntrance(.row(2 + entry.order), listOpacity: listAlpha)
                }
                if entries.isEmpty {
                    Text("Aún no hay movimientos en esta cuenta.")
                        .titan(.callout)
                        .foregroundStyle(Theme.label2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
        } header: {
            CardSegments(cards: cards, selection: $selection, motion: motion)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .background(Theme.canvas)
                .homeEntrance(.segments)
        }
    }

    /// Todo lo que se desplaza: título, carrusel (o resultados de la búsqueda) y la lista.
    @ViewBuilder
    private func content(_ snapshot: LedgerSnapshot) -> some View {
        let cards = AccountCard.visible(hasInvestments: portfolio.hasPositions)
        let activeListCard = cards.contains(listCard) ? listCard : .all
        let entries = snapshot.list(for: snapshot.total == nil ? .all : activeListCard)
        // La primera FILA (no la cabecera del día, que no cambia cuando llega otro movimiento hoy).
        let firstRowID = entries.first { entry in
            if case .row = entry.kind { return true }
            return false
        }?.id
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            // El indicador de «tirar para actualizar»: no ocupa alto; se dibuja en el hueco que deja la lista al bajar.
            if !searching {
                TitaniumRefreshIndicator(state: refresh, motion: motion)
            }
            // El título va con el contenido (se desliza bajo la barra); al buscar, deja su sitio a los resultados.
            if !searching {
                HomeTitle()
                    .homeEntrance(.title)
                    // Por encima del carrusel: una tarjeta que se voltea o se levanta pasa por detrás del título,
                    // que se lee siempre entero.
                    .zIndex(1)
            }
            if searching {
                SearchResults(index: snapshot.searchIndex, logoDomains: snapshot.logoDomains,
                              ownTransfers: snapshot.ownTransfers, query: query, zoom: zoom, onOpen: open)
            } else if snapshot.total != nil || portfolio.hasPositions {
                CardCarousel(snapshot: snapshot, links: model.state.links, cards: cards,
                             portfolioSummary: portfolio.summary,
                             portfolioLastImport: portfolio.portfolio.lastImport,
                             selection: $selection, flipped: $flipped, motion: motion,
                             onEdit: openSettings,
                             onOpenBank: openBankSettings,
                             onImportInvestments: openInvestmentsSettings,
                             onFan: openFan)
                    .environment(\.cardTilt, tilt)
                    .environment(\.arrivalPulse, pulse)
                    .modifier(CarouselParallax(motion: motion, enabled: !kit.reduce))
                    .homeEntrance(.carousel)
                    .padding(.top, 2)
                listSection(snapshot, cards: cards, card: activeListCard, entries: entries)
            } else {
                HomeEmptyState(openSettings: { openSettings(nil) })
                ForEach(entries) { entry in
                    row(entry, snapshot: snapshot, swipes: false)
                }
            }
        }
        // Una fila nueva: las demás le hacen sitio con el muelle de fila (con Reducir movimiento, sin animación).
        .animation(kit.reduce ? nil : kit.animation(.row), value: firstRowID)
        // Abrir o cerrar la búsqueda cambia las piezas en el acto (ningún muelle mueve la maquetación) y lo nuevo se
        // funde (`SearchSwapFade`).
        .transaction(value: searching) { $0.animation = nil }
        .modifier(SearchSwapFade(searching: searching))
        .modifier(TitaniumRefreshHold(state: refresh))
        // La última fila puede subir por encima del degradado de la barra de pestañas (`TabBarFade`).
        .padding(.bottom, Theme.Space.section + TabBarFade.height)
    }

    /// La lista con su desplazamiento medido (paralaje, degradado de la barra, tirar para actualizar).
    private func scroller(_ snapshot: LedgerSnapshot) -> some View {
        ScrollView {
            content(snapshot)
        }
        .scrollPosition($scroll)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            motion.listOffset = offset
            // Solo cambia al cruzar el alto de la tarjeta: Inicio no se vuelve a evaluar en cada paso del desplazamiento.
            let covered = offset > CarouselMetrics.minHeight
            if covered != carouselCovered { carouselCovered = covered }
        }
        .onScrollPhaseChange { old, new in
            motion.listIdle = new == .idle
            // Como en Mail: en cuanto el dedo arrastra la lista, la fila que estaba abierta se cierra.
            if new == .interacting, openRow != nil { openRow = nil }
            // El dedo suelta la lista: si había tirado lo bastante, se actualiza.
            if old == .interacting, new != .interacting { pullReleased() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Sus piezas (marca y botones de cristal) entran cada una a su tiempo: ver `HomeEntrance`.
            HomeTopBar(searching: $searching, query: $query, motion: motion, openBriefing: openBriefing)
        }
        .background(Theme.canvas.ignoresSafeArea())
    }

    /// Lo anterior con sus capas: el aviso breve, el abanico de tarjetas y (solo DEBUG) las sondas de las pruebas.
    private func layered(_ snapshot: LedgerSnapshot) -> some View {
        scroller(snapshot)
            // Con el abanico abierto, lo de debajo no se lee ni se recorre con VoiceOver.
            .accessibilityHidden(fan != nil)
            // Bajo la barra de pestañas de cristal, negro: los últimos 90 pt de la lista se funden a negro, así el
            // cristal no tiene filas que deformar (antes salía «sucio» con trozos de la fila de debajo).
            .overlay(alignment: .bottom) { TabBarFade() }
            .overlay(alignment: .top) {
                if let toastText {
                    Text(toastText)
                        .titan(.meta)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.raised, in: Capsule())
                        .padding(.top, 58)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .overlay {
                if let fan {
                    WalletFan(cards: AccountCard.visible(hasInvestments: portfolio.hasPositions),
                              snapshot: snapshot, portfolioSummary: portfolio.summary, request: fan,
                              onPick: pickFromFan, onClose: { self.fan = nil })
                }
            }
            // Línea C (lote final, carcasa): con el abanico abierto la barra de pestañas no queda encima de él.
            .toolbar(fan == nil ? .automatic : .hidden, for: .tabBar)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HomeProbeElement()
                    DrawnTextAuditProbe()
                }
                .allowsHitTesting(false)
            }
            #endif
            .environment(\.entrance, entrance)
    }

    /// Hápticas: cada tope del carrusel, «No es mío» y la llegada de un movimiento.
    private func withFeedback<V: View>(_ view: V) -> some View {
        view
            .sensoryFeedback(Haptics.detent, trigger: detentTick)
            .sensoryFeedback(Haptics.warning, trigger: flagTick)
            // Solo un movimiento que llega de verdad, con Inicio delante: un toque suave por un pago, éxito por un ingreso.
            .sensoryFeedback(trigger: model.arrival) { _, new in
                guard let new, isVisible, scenePhase == .active else { return nil }
                return Haptics.arrival(isIncome: new.isIncome)
            }
    }

    /// La tarjeta elegida manda en la lista.
    private func withSelectionReactions<V: View>(_ view: V) -> some View {
        view
            .onChange(of: selection) { old, new in
                // `nil` nunca cambia la lista (el carrusel ya no lo escribe, pero así es imposible un vaivén).
                guard let new, new != old else { return }
                if !quietSelection { detentTick += 1 }
                openRow = nil
                showList(for: new)
                if new == .investments {
                    Task { await portfolio.refreshPrices(force: false) }
                }
            }
            .onChange(of: portfolio.hasPositions) { _, hasPositions in
                if !hasPositions && (selection == .investments || listCard == .investments) {
                    selection = .all
                    listCard = .all
                }
            }
            .onChange(of: selectCardRequest, initial: true) { _, requested in
                guard let requested else { return }
                selectCardRequest = nil
                let cards = AccountCard.visible(hasInvestments: portfolio.hasPositions)
                guard cards.contains(requested) else { return }
                closeSearch()
                withAnimation(kit.reduce ? nil : kit.animation(.snap)) {
                    selection = requested
                }
            }
    }

    /// Llegadas y montaje por capas.
    private func withArrivalReactions<V: View>(_ view: V) -> some View {
        view
            .onChange(of: model.arrival) { _, new in
                if let new { choreograph(new) }
            }
            // El modelo publica el movimiento un instante después de anunciar la llegada: entonces la cifra rueda, la
            // tarjeta enseña su ✓ y la fila cae.
            .onChange(of: model.state.movements.count) { _, _ in landArrival() }
            .onChange(of: revealToken) { _, _ in assemble() }
    }

    /// Otra pestaña, bloqueo, app fuera de primer plano o una hoja: la búsqueda se cierra, el teclado se va y el
    /// abanico se quita en el acto (nada se queda encima del bloqueo ni en la captura del selector de apps).
    private func withFrontReactions<V: View>(_ view: V) -> some View {
        view
            .onChange(of: isVisible) { _, visible in
                if !visible { leaveFront() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { leaveFront() }
            }
            .onChange(of: detailOpen) { _, open in
                if open { fan = nil }
            }
            .onChange(of: searching) { _, on in
                if !on { query = "" }
                openRow = nil
            }
            .onChange(of: refresh.doneTick) { _, _ in
                // Con Reducir movimiento no hay hueco para el indicador: lo dice el aviso breve.
                if kit.reduce { showToast("Al día") }
            }
    }

    /// La inclinación solo se lee con Inicio a la vista de verdad; en cualquier otro caso los sensores se paran.
    private func withTilt<V: View>(_ view: V) -> some View {
        view
            .onChange(of: tiltRuns, initial: true) { _, runs in
                if runs { tilt.start() } else { tilt.stop() }
                #if DEBUG
                HomeProbe.shared.tiltRunning = runs
                #endif
            }
            .onDisappear { tilt.stop() }
    }

    var body: some View {
        let snapshot = model.snapshot
        let reacting = withFrontReactions(withArrivalReactions(withSelectionReactions(withFeedback(layered(snapshot)))))
        withTilt(reacting)
            .task(id: snapshot.logoDomains.count) {
                await logos.prewarm(domains: Array(Set(snapshot.logoDomains.values)))
            }
            #if DEBUG
            .onAppear(perform: applyDemoLaunchState)
            .onChange(of: motion.demoMomentTick) { _, _ in runDemoMoment() }
            .onChange(of: freshID, initial: true) { _, id in HomeProbe.shared.freshRows = id == nil ? 0 : 1 }
            #endif
    }

    private func row(_ entry: ListEntry, snapshot: LedgerSnapshot, swipes: Bool) -> ListEntryView {
        var domain: String?
        var fresh = false
        if case let .row(row, _) = entry.kind {
            domain = snapshot.logoDomains[row.id]
            fresh = row.id == freshID
        }
        // Solo la lista de Inicio lleva filas deslizables (ni el estado vacío ni la búsqueda).
        let rowBinding: Binding<UUID?>? = swipes ? $openRow : nil
        let onFlag: ((UUID, Bool) -> Void)? = swipes ? { id, flagged in flag(id, flagged) } : nil
        return ListEntryView(entry: entry, logoDomain: domain, isFresh: fresh, zoom: zoom,
                             onOpen: { id in self.open(id) }, onDeleteUnread: { id in deleteUnread(id) },
                             openRow: rowBinding, onFlag: onFlag)
    }

    /// Cuándo se leen los sensores de inclinación: Inicio delante (ni otra pestaña ni el bloqueo), la app activa, la
    /// tarjeta en pantalla (la lista no la ha tapado al subir), sin búsqueda, hoja ni abanico encima, y con efectos
    /// ricos (ni Reducir movimiento ni Bajo consumo).
    private var tiltRuns: Bool {
        isVisible && scenePhase == .active && !searching && !detailOpen && fan == nil && !carouselCovered && kit.richEffects
    }

    // MARK: - Lista que sigue a la tarjeta

    /// Hasta dónde se atenúa la lista vieja antes del cambio (con movimiento). La nueva sale desde ahí: la pantalla
    /// nunca se queda en negro entre las dos (antes, unos 100 ms vacíos en cada cambio de tarjeta).
    private static let listFloor = 0.3

    /// Opacidad de la lista: atenuada mientras cambia (con Reducir movimiento, invisible: ahí las cifras se funden por
    /// su cuenta y no se pueden leer dos a la vez).
    private var listAlpha: Double {
        listHidden ? (kit.reduce ? 0 : Self.listFloor) : 1
    }

    /// La lista vieja se atenúa hasta `listFloor` en 0,12 s (solo baja, nunca vuelve a subir), cambia en ese punto y la
    /// nueva sube escalonada (34 ms × 0,8ⁿ entre filas) mientras vuelve al 100 %: un fundido cruzado sin hueco negro.
    /// Un cambio rápido de tarjeta deja sin efecto el anterior (`listSwap`), y si la animación de salida no termina
    /// (p. ej. otra transacción la interrumpe), un respaldo vuelve a enseñar la lista: nunca se queda oculta.
    /// Con Reducir movimiento la vieja se funde del todo y la nueva sale en su sitio con un fundido, sin escalonado.
    private func showList(for card: AccountCard) {
        guard card != listCard || listHidden else { return }
        listSwap += 1
        let swapID = listSwap
        let out = kit.seconds(0.12)
        withAnimation(.easeOut(duration: out)) {
            listHidden = true
        } completion: {
            swapList(swapID)
        }
        Task {
            try? await Task.sleep(for: .seconds(out + kit.seconds(0.26)))
            swapList(swapID)
        }
    }

    private func swapList(_ swapID: Int) {
        guard swapID == listSwap, listHidden || listCard != (selection ?? .all) else { return }
        // El cambio de lista va sin animación (la vieja ya es invisible): nada se queda ocupando sitio.
        var swap = Transaction()
        swap.disablesAnimations = true
        #if DEBUG
        // Lo que se DIBUJA en el cambio: cada pieza de la lista nueva anota la opacidad que de verdad recibe mientras
        // espera su turno (`HomeEntrance` → `DrawnOpacity`) y la sonda guarda la menor.
        HomeProbe.shared.listSwapFloor = 100
        #endif
        withTransaction(swap) { listCard = selection ?? .all }
        beginEntrance(.list)
        #if DEBUG
        HomeProbe.shared.listEntrances += 1
        #endif
        // Con Reducir movimiento las cifras que cambian con la tarjeta se funden por su cuenta: la lista vuelve a
        // verse cuando ese fundido ha terminado, así nunca se leen dos cifras superpuestas.
        let wait = kit.reduce ? 0.22 * kit.timeMultiplier : 0
        withAnimation(.easeOut(duration: kit.seconds(0.16)).delay(wait)) { listHidden = false }
    }

    // MARK: - Montaje y llegada

    /// Al arrancar y al desbloquear: marca y botones, título, carrusel, segmentado, resumen y filas, por capas (ver
    /// `HomeEntrance`). Con Reducir movimiento también, pero como un fundido sin recorrido.
    private func assemble() {
        guard !searching else { return }
        #if DEBUG
        HomeProbe.shared.assemblies += 1
        #endif
        beginEntrance(.assembly)
    }

    /// Abre la ventana de una entrada. Mientras está abierta, las piezas esperan su turno; al cerrarse, todo lo que
    /// aparezca después (filas que entran al bajar la lista) ya está en su sitio. La ventana dura lo que la entrada
    /// más larga con la intensidad y la cámara lenta de `\.motion` (1,4 s en Equilibrado), así que una grabación a
    /// cámara lenta no corta la entrada a medias.
    private func beginEntrance(_ scope: Entrance.Scope) {
        let token = entrance.token + 1
        entrance = Entrance(token: token, active: true, scope: scope)
        let window = kit.seconds(1.4)
        Task {
            try? await Task.sleep(for: .seconds(window))
            if entrance.token == token { entrance.active = false }
        }
    }

    /// Se anuncia una llegada (el modelo aún no ha publicado el movimiento): si su banco tiene otra tarjeta delante, el
    /// carrusel se desliza hasta ella, y la lista vuelve arriba. Lo demás pasa cuando el movimiento ya está en el
    /// libro (`landArrival`).
    private func choreograph(_ arrival: Arrival) {
        freshID = arrival.id
        awaitedArrival = arrival
        awaitedAt = AppClock.now
        #if DEBUG
        HomeProbe.shared.arrivalsAnnounced += 1
        #endif
        defer { landArrival() }
        // La caducidad no depende de que el libro vuelva a cambiar: pasado el plazo sin aterrizar, la fila deja de
        // estar marcada como nueva (nunca un fondo y un ✓ fijos horas después).
        let id = arrival.id
        let window = kit.pause(ArrivalWindow.lifetime)
        Task {
            try? await Task.sleep(for: .seconds(window))
            if awaitedArrival?.id == id { expireArrival(id) }
        }
        guard isVisible, scenePhase == .active else { return }
        if UIAccessibility.isVoiceOverRunning {
            let what = arrival.amountCents < 0 ? "pago de" : "ingreso de"
            let amount = spokenAmount(abs(arrival.amountCents), hidden: preferences.privateMode)
            AccessibilityNotification.Announcement("Nuevo movimiento: \(arrival.title), \(what) \(amount)").post()
        }
        guard !searching, !detailOpen, fan == nil else { return }
        openRow = nil
        if motion.listOffset > 4 {
            withAnimation(kit.reduce ? nil : kit.animation(.snap)) { scroll.scrollTo(edge: .top) }
        }
        // «Todo» ya enseña los tres saldos y el total: solo se desliza si delante está la tarjeta de otro banco.
        let target = AccountCard(bank: arrival.bank)
        guard let current = selection, current != .all, current != target else { return }
        quietSelection = true
        flipped = nil
        withAnimation(kit.reduce ? nil : kit.animation(.snap)) {
            selection = target
        } completion: {
            quietSelection = false
        }
    }

    /// El movimiento anunciado ya está en el libro: su fila cae (lo hace la propia fila, con `isFresh`) con un fondo
    /// que se apaga a la vez que el ✓ de la tarjeta (quieto 1,6 s y fundido de 0,3 s: el momento termina junto), y la
    /// tarjeta de delante responde sobre su cifra (✓ con el importe; con el ojo cerrado, solo un latido): ver
    /// `ArrivalHeroEffect`. Una llegada cuyo movimiento no aparece a tiempo caduca (`ArrivalWindow`): nunca aterriza
    /// minutos después con otro cambio del libro.
    private func landArrival() {
        guard let arrival = awaitedArrival else { return }
        guard ArrivalWindow.isOpen(announcedAt: awaitedAt, now: AppClock.now, timeMultiplier: kit.timeMultiplier) else {
            expireArrival(arrival.id)
            return
        }
        guard model.movement(arrival.id) != nil else { return }
        awaitedArrival = nil
        let id = arrival.id
        let hold = kit.seconds(1.6)
        let fade = kit.seconds(0.3)
        Task {
            try? await Task.sleep(for: .seconds(hold))
            guard freshID == id else { return }
            withAnimation(.easeOut(duration: fade)) { freshID = nil }
        }
        guard isVisible, scenePhase == .active, !searching, !detailOpen, fan == nil else { return }
        // La tarjeta del banco si está delante; si no, «Todo» (si es la que está delante).
        let target = AccountCard(bank: arrival.bank)
        let front = selection ?? .all
        guard front == target || front == .all else { return }
        pulse = ArrivalPulse(token: pulse.token + 1, card: front, amountCents: arrival.amountCents)
    }

    /// La llegada caduca sin aterrizar: ni insignia ni fila nueva; si la fila ya estaba marcada, se apaga en 0,3 s.
    private func expireArrival(_ id: UUID) {
        awaitedArrival = nil
        if freshID == id {
            withAnimation(.easeOut(duration: kit.seconds(0.3))) { freshID = nil }
        }
    }

    // MARK: - Tirar para actualizar

    private func pullReleased() {
        guard isVisible, scenePhase == .active, !searching, fan == nil, !detailOpen else { return }
        refresh.released(pull: -motion.listOffset, motion: kit, action: refreshEverything)
    }

    /// Lo mismo que hace la app al abrirse, pedido a mano: consulta a los bancos conectados (lo que deje la política
    /// de consultas), vuelve a leer el libro y refresca los precios si toca. Devuelve si se puede decir «Al día»: lo
    /// decide `RefreshVerdict` (Core) con lo que devolvió cada banco y sus conexiones tal como quedaron.
    private func refreshEverything() async -> Bool {
        let outcomes = refreshOutcomes(await BankSync.shared.refresh(trigger: .manual))
        model.reload()
        if portfolio.hasPositions { await portfolio.refreshPrices(force: false) }
        return RefreshVerdict.isUpToDate(outcomes: outcomes, links: model.state.links, now: AppClock.now)
    }

    private func refreshOutcomes(_ real: [BankID: SyncOutcome]) -> [BankID: BankRefreshOutcome] {
        #if DEBUG
        // En la demo no se consulta a nadie: cada banco conectado «responde» lo que diga `-MiBancoDemoRefresh`
        // (por defecto, que ya estaba reciente) y pasa por el mismo veredicto que la app de verdad.
        if DemoMode.isActive {
            let reason = DemoMode.refreshSkipReason
            return model.state.links.mapValues { _ in .skipped(reason) }
        }
        #endif
        return real.mapValues { outcome -> BankRefreshOutcome in
            switch outcome {
            case let .skipped(reason): .skipped(reason)
            case .updated: .updated
            case let .failed(problem): .failed(problem)
            }
        }
    }

    // MARK: - Abanico de tarjetas

    /// Mantener pulsada la tarjeta levantada (o soltarla) abre el abanico desde donde está esa tarjeta.
    private func openFan() {
        guard fan == nil, isVisible, scenePhase == .active, !searching, !detailOpen else { return }
        openRow = nil
        flipped = nil
        fan = WalletFanRequest(origin: motion.carouselFrame.isEmpty ? nil : motion.carouselFrame)
    }

    /// Una tarjeta del abanico: la de un banco abre su pantalla (el vuelo ya está apuntado); «Todo» e «Inversiones»
    /// se quedan delante en el carrusel.
    private func pickFromFan(_ card: AccountCard) {
        fan = nil
        if let bank = card.bank {
            openBankSettings(bank)
        } else {
            withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = card }
        }
    }

    // MARK: - Acciones

    private func open(_ id: UUID) {
        openRow = nil
        openDetail(id)
    }

    /// «No es mío» / «Sí es mío» desde las acciones de una fila. Si falla, la fila sigue como estaba.
    private func flag(_ id: UUID, _ flagged: Bool) {
        do {
            try model.setFlaggedNotMine(flagged, for: id)
            if flagged { flagTick += 1 }
        } catch {}
    }

    /// Inicio deja de estar delante: fuera la búsqueda, el teclado, el abanico y la fila abierta.
    private func leaveFront() {
        closeSearch()
        fan = nil
        openRow = nil
    }

    private func closeSearch() {
        guard searching || !query.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searching = false
        query = ""
    }

    /// Si falla, el aviso sigue en la lista y se puede volver a intentar.
    private func deleteUnread(_ id: UUID) {
        withAnimation(kit.reduce ? nil : kit.calmAnimation(.snap)) {
            try? model.deleteUnread(id)
        }
    }

    private func visiblePendingMoves(for card: AccountCard) -> [PendingMove] {
        guard let bank = card.bank else { return model.pendingMoves }
        return model.pendingMoves.filter { $0.from == bank || $0.target == .own(bank) }
    }

    private func showToast(_ text: String) {
        withAnimation(kit.calmAnimation(.snap)) { toastText = text }
        AccessibilityNotification.Announcement(text).post()
        toastTask?.cancel()
        toastTask = Task {
            // Tiempo de lectura (real), no de una animación.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(kit.fade) { toastText = nil }
        }
    }

    #if DEBUG
    /// Solo demo (`-MiBancoDemoCardMoment`): los momentos de Inicio que disparan las ráfagas al tocar el segmento ya
    /// elegido (los de la tarjeta los atiende el carrusel).
    private func runDemoMoment() {
        switch DemoMode.cardMoment {
        case .arrival:
            model.demoSimulateArrival(income: false)
        case .arrivalIncome:
            model.demoSimulateArrival(income: true)
        case .fan:
            openFan()
        case .refresh:
            refresh.start(motion: kit, action: refreshEverything)
        case .rowSwipe:
            let first = model.snapshot.list(for: listCard).first { entry in
                if case .row(let row, _) = entry.kind, case .movement = row.item { return true }
                return false
            }
            if case .row(let row, _)? = first?.kind { openRow = openRow == row.id ? nil : row.id }
        case .staleArrival:
            model.demoAnnounceUnpublishedArrival()
        case .search:
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                searching = true
                try? await Task.sleep(for: .seconds(3))
                closeSearch()
            }
        case .lift, .tilt, .peek, .glide, .glideFar, nil:
            break
        }
    }

    private func applyDemoLaunchState() {
        guard DemoMode.isActive else { return }
        // `-MiBancoDemoCard`: arranca ya en esa tarjeta (el carrusel se coloca en cuanto tiene ancho).
        if let card = DemoMode.initialCard, card != .all {
            quietSelection = true
            selection = card
            listCard = card
            quietSelection = false
        }
        if DemoMode.startsFlipped {
            // U80: tras el cambio de tarjeta de arriba, porque el carrusel deshace el volteo al cambiar de tarjeta
            // (`CardCarousel.onChange(of: selection)`) y la captura `reverso-revolut` salía con el anverso.
            let target = selection ?? .all
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                flipped = target
            }
        }
        // `-MiBancoDemoSwitch`: a los 2 s pasa a la tarjeta siguiente por el mismo camino que un toque en el segmentado.
        if DemoMode.switchesCard {
            let cards = AccountCard.visible(hasInvestments: portfolio.hasPositions)
            Task {
                try? await Task.sleep(for: .seconds(2))
                let next = cards[min((selection ?? .all).index(in: cards) + 1, cards.count - 1)]
                withAnimation(kit.reduce ? nil : kit.animation(.snap)) { selection = next }
            }
        }
        if let text = DemoMode.searchQuery {
            searching = true
            query = text
        }
        if DemoMode.opensPosition, let instrument = DemoMode.demoPositionInstrument(in: portfolio.summary) {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                for _ in 0..<10 {
                    openPosition(instrument)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        } else if DemoMode.opensDetail, let first = model.snapshot.searchIndex.first {
            Task {
                // Se reintenta unos segundos: `openDetail` no abre con la app aún fuera de primer plano (arranque en el simulador de CI);
                // repetir la misma ruta no hace nada una vez abierta.
                try? await Task.sleep(for: .seconds(1.5))
                for _ in 0..<10 {
                    openDetail(first.id)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
    #endif
}

/// Negro bajo la barra de pestañas y un degradado de `height` pt por encima: el cristal de la barra solo tiene negro
/// detrás. Fijo (no se anima), no se toca y no existe para VoiceOver.
struct TabBarFade: View {
    static let height: CGFloat = 90

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(colors: [Theme.canvas.opacity(0), Theme.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.height)
                Theme.canvas.frame(height: geo.safeAreaInsets.bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Al abrir o cerrar la búsqueda, lo que entra (resultados, o el título y el carrusel de vuelta) se funde en su sitio:
/// una sola secuencia que empieza invisible y acaba a la vista. Nada se desplaza.
private struct SearchSwapFade: ViewModifier {
    let searching: Bool
    @Environment(\.motion) private var motion

    func body(content: Content) -> some View {
        let fade = motion.seconds(0.22)
        content.keyframeAnimator(initialValue: 1.0, trigger: searching) { view, opacity in
            view.opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                CubicKeyframe(1.0, duration: fade)
            }
        }
    }
}
