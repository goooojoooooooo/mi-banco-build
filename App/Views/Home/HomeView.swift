import SwiftUI
import MiBancoCore

/// Inicio: barra fija (título, ojo, lupa), el carrusel de cuentas, el segmentado (se queda pegado arriba),
/// el gasto de 7 días y la lista por días que sigue a la tarjeta elegida. Todo sale de `model.snapshot`.
struct HomeView: View {
    let model: LedgerModel
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
    let openSettings: (BankID?) -> Void

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var motion = HomeMotion()
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
    @State private var detentTick = 0
    /// Durante el deslizamiento de una llegada, el tope no suena (ya suena la llegada).
    @State private var quietSelection = false
    /// Número del último cambio de lista pedido.
    @State private var listSwap = 0

    var body: some View {
        let snapshot = model.snapshot
        let entries = snapshot.list(for: snapshot.total == nil ? .all : listCard)
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if searching {
                    SearchResults(index: snapshot.searchIndex, logoDomains: snapshot.logoDomains,
                                  ownTransfers: snapshot.ownTransfers, query: query, zoom: zoom, onOpen: open)
                } else if snapshot.total != nil {
                    CardCarousel(snapshot: snapshot, selection: $selection, flipped: $flipped, motion: motion,
                                 onEdit: openSettings)
                        .modifier(CarouselParallax(motion: motion, enabled: !reduceMotion))
                        .staggeredEntrance(1, rise: 36, scale: 0.97)
                        .padding(.top, 2)
                    Section {
                        WeekBlock(card: listCard, week: snapshot.weeks[listCard] ?? WeekSpend(), pace: snapshot.pace,
                                  balance: listCard.bank.flatMap { snapshot.balances[$0] })
                            .opacity(listHidden ? 0 : 1)
                            .staggeredEntrance(3, listIndex: 0)
                        ForEach(entries) { entry in
                            row(entry, snapshot: snapshot)
                                .opacity(listHidden ? 0 : 1)
                                .staggeredEntrance(4 + entry.order, listIndex: 1 + entry.order)
                        }
                        if entries.isEmpty {
                            Text("Aún no hay movimientos en esta cuenta.")
                                .titan(.callout)
                                .foregroundStyle(Theme.label2)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    } header: {
                        CardSegments(selection: $selection, motion: motion)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .background(Theme.canvas)
                            .staggeredEntrance(2)
                    }
                } else {
                    HomeEmptyState(openSettings: { openSettings(nil) })
                    ForEach(entries) { entry in
                        row(entry, snapshot: snapshot)
                    }
                }
            }
            .animation(reduceMotion ? nil : Theme.Motion.rowSettle, value: entries.first?.id)
            .padding(.bottom, Theme.Space.section)
        }
        .scrollPosition($scroll)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            motion.listOffset = offset
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HomeTopBar(searching: $searching, query: $query, motion: motion)
                .staggeredEntrance(0, rise: 0)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .environment(\.entrance, entrance)
        .sensoryFeedback(Haptics.detent, trigger: detentTick)
        // Solo un movimiento que llega de verdad, con Inicio delante: un toque suave por un pago, éxito por un ingreso.
        .sensoryFeedback(trigger: model.arrival) { _, new in
            guard let new, isVisible, scenePhase == .active else { return nil }
            return Haptics.arrival(isIncome: new.isIncome)
        }
        .onChange(of: selection) { old, new in
            // `nil` nunca cambia la lista (el carrusel ya no lo escribe, pero así es imposible un vaivén).
            guard let new, new != old else { return }
            if !quietSelection { detentTick += 1 }
            showList(for: new)
        }
        .onChange(of: model.arrival) { _, new in
            if let new { choreograph(new) }
        }
        .onChange(of: revealToken) { _, _ in assemble() }
        // Otra pestaña, bloqueo o app fuera de primer plano: la búsqueda se cierra y el teclado se va
        // (nunca se queda encima del bloqueo ni en la captura del selector de apps).
        .onChange(of: isVisible) { _, visible in
            if !visible { closeSearch() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { closeSearch() }
        }
        .onChange(of: searching) { _, on in
            if !on { query = "" }
        }
        .task(id: snapshot.logoDomains.count) {
            await logos.prewarm(domains: Array(Set(snapshot.logoDomains.values)))
        }
        #if DEBUG
        .onAppear(perform: applyDemoLaunchState)
        #endif
    }

    private func row(_ entry: ListEntry, snapshot: LedgerSnapshot) -> ListEntryView {
        var domain: String?
        var fresh = false
        if case let .row(row, _) = entry.kind {
            domain = snapshot.logoDomains[row.id]
            fresh = row.id == freshID
        }
        return ListEntryView(entry: entry, logoDomain: domain, isFresh: fresh, zoom: zoom,
                             onOpen: open, onDeleteUnread: deleteUnread)
    }

    // MARK: - Lista que sigue a la tarjeta

    /// La lista sale con un fundido de 150 ms, cambia, y la nueva entra escalonada (60 ms entre filas).
    /// Un cambio rápido de tarjeta deja sin efecto el anterior (`listSwap`), y si la animación de salida no termina
    /// (p. ej. otra transacción la interrumpe), un respaldo a los 0,4 s vuelve a enseñar la lista: nunca se queda oculta.
    private func showList(for card: AccountCard) {
        guard card != listCard || listHidden else { return }
        listSwap += 1
        let swapID = listSwap
        if reduceMotion {
            listCard = card
            return
        }
        withAnimation(Theme.Motion.listFade) {
            listHidden = true
        } completion: {
            swapList(swapID)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            swapList(swapID)
        }
    }

    private func swapList(_ swapID: Int) {
        guard swapID == listSwap, listHidden || listCard != (selection ?? .all) else { return }
        // El cambio de lista va sin animación (la vieja ya es invisible): nada se queda ocupando sitio.
        var swap = Transaction()
        swap.disablesAnimations = true
        withTransaction(swap) { listCard = selection ?? .all }
        beginEntrance(.list)
        withAnimation(Theme.Motion.listFade) { listHidden = false }
    }

    // MARK: - Montaje y llegada

    /// Al arrancar y al desbloquear: barra, carrusel, segmentado, resumen y filas, por capas (≤ 1,2 s).
    private func assemble() {
        guard !reduceMotion, !searching else { return }
        beginEntrance(.assembly)
    }

    private func beginEntrance(_ scope: Entrance.Scope) {
        let token = entrance.token + 1
        entrance = Entrance(token: token, active: true, scope: scope)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if entrance.token == token { entrance.active = false }
        }
    }

    /// Llega un movimiento: si su banco tiene otra tarjeta delante, el carrusel se desliza hasta ella; la lista vuelve
    /// arriba; el saldo y el total ruedan cuando el modelo publica (un instante después); la fila nueva entra
    /// con un fondo que se apaga en 1,6 s y, si es dinero que entra, un ✓ verde.
    private func choreograph(_ arrival: Arrival) {
        freshID = arrival.id
        let id = arrival.id
        Task {
            try? await Task.sleep(for: Theme.Motion.arrivalLead + Theme.Motion.freshHold)
            guard freshID == id else { return }
            withAnimation(Theme.Motion.freshFade) { freshID = nil }
        }
        guard isVisible, scenePhase == .active else { return }
        if UIAccessibility.isVoiceOverRunning {
            let what = arrival.amountCents < 0 ? "pago de" : "ingreso de"
            let amount = spokenAmount(abs(arrival.amountCents), hidden: preferences.privateMode)
            AccessibilityNotification.Announcement("Nuevo movimiento: \(arrival.title), \(what) \(amount)").post()
        }
        guard !searching, !detailOpen else { return }
        if motion.listOffset > 4 {
            withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) { scroll.scrollTo(edge: .top) }
        }
        // «Todo» ya enseña los tres saldos y el total: solo se desliza si delante está la tarjeta de otro banco.
        let target = AccountCard(bank: arrival.bank)
        guard let current = selection, current != .all, current != target else { return }
        quietSelection = true
        flipped = nil
        withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) {
            selection = target
        } completion: {
            quietSelection = false
        }
    }

    // MARK: - Acciones

    private func open(_ id: UUID) {
        openDetail(id)
    }

    private func closeSearch() {
        guard searching || !query.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        searching = false
        query = ""
    }

    /// Si falla, el aviso sigue en la lista y se puede volver a intentar.
    private func deleteUnread(_ id: UUID) {
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
            try? model.deleteUnread(id)
        }
    }

    #if DEBUG
    private func applyDemoLaunchState() {
        guard DemoMode.isActive else { return }
        // `-MiBancoDemoCard`: arranca ya en esa tarjeta (el carrusel se coloca en cuanto tiene ancho).
        if let card = DemoMode.initialCard, card != .all {
            quietSelection = true
            selection = card
            listCard = card
            quietSelection = false
        }
        // `-MiBancoDemoSwitch`: a los 2 s pasa a la tarjeta siguiente por el mismo camino que un toque en el segmentado.
        if DemoMode.switchesCard {
            Task {
                try? await Task.sleep(for: .seconds(2))
                let all = AccountCard.allCases
                let next = all[min((selection ?? .all).index + 1, all.count - 1)]
                withAnimation(Theme.Motion.cardSettle) { selection = next }
            }
        }
        if let text = DemoMode.searchQuery {
            searching = true
            query = text
        }
        if DemoMode.opensDetail, let first = model.snapshot.searchIndex.first {
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

/// La hoja de detalle abierta para un movimiento.
struct DetailRoute: Identifiable, Hashable {
    let id: UUID
    /// Viene de una fila de Inicio: la hoja sale con zoom desde su logo.
    var zooms = false
}
