import SwiftUI
import MiBancoCore

/// De dónde sale el abanico: el marco en pantalla de la tarjeta levantada (o `nil` si no se conoce).
struct WalletFanRequest: Equatable {
    var origin: CGRect?
}

/// El abanico de tarjetas (maqueta aprobada, «Cartera en abanico»): mantener pulsada la tarjeta de delante la levanta
/// y, si se sigue pulsando (o al soltarla), las tarjetas salen de debajo de ella y se abren una bajo otra, 78 pt entre
/// ellas, con 60 ms de escalón y el muelle `snap`. Cada tarjeta enseña en su franja visible el banco y su saldo.
/// - Tocar la tarjeta de un banco: las demás caen y se apagan al 20 %, se apunta el vuelo (`CardFlight.request`, con el
///   marco de esa tarjeta como origen) y se abre la pantalla de ese banco por el camino de siempre (`onOpenBank`).
/// - Tocar «Todo» o «Inversiones» (no tienen pantalla de banco) cierra el abanico y deja esa tarjeta delante.
/// - Es una capa de Inicio, nunca una hoja: se cierra con «Cerrar», tocando fuera, y en el acto si Inicio deja de estar
///   a la vista (otra pestaña, bloqueo, app fuera de primer plano, una hoja).
/// - Con el ojo cerrado los saldos son su máscara. Con Reducir movimiento no hay viaje: las tarjetas se funden en su sitio.
/// Solo cambian desplazamiento, escala, giro y opacidad; los tiempos salen de `\.motion`.
struct WalletFan: View {
    let cards: [AccountCard]
    let snapshot: LedgerSnapshot
    let portfolioSummary: PortfolioSummary?
    let request: WalletFanRequest
    /// La tarjeta tocada (ya con el vuelo apuntado, si es de un banco).
    let onPick: (AccountCard) -> Void
    let onClose: () -> Void

    @Environment(\.motion) private var motion
    @Environment(\.cardFlight) private var flight
    /// Inicio ya está tapado por el negro (primer tiempo de la apertura).
    @State private var dark = false
    @State private var fanned = false
    /// «Tus tarjetas» a la vista (entra cuando Inicio ya no se ve: nunca dos cabeceras a la vez).
    @State private var headerIn = false
    @State private var picked: AccountCard?
    @State private var closing = false
    @State private var pickTick = 0

    private static let cardHeight: CGFloat = 168
    /// Lo que mide de verdad la cabecera («Tus tarjetas», la ayuda y la X), medida con el tamaño de texto de ahora.
    @State private var headerContent: CGFloat = 0
    /// Alto reservado para la cabecera: 92 pt, o lo que mida si es más (texto muy grande): la primera tarjeta nunca la tapa.
    private var headerHeight: CGFloat { max(92, headerContent + 12) }

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let count = max(cards.count, 1)
            let room = geo.size.height - headerHeight - Self.cardHeight - 20
            let step: CGFloat = count > 1 ? min(78, max(40, room / CGFloat(count - 1))) : 0
            // Donde está la tarjeta levantada, en las coordenadas de esta capa.
            let startY: CGFloat = (request.origin?.minY ?? frame.minY + 150) - frame.minY
            ZStack(alignment: .top) {
                // Negro del todo: Inicio no se transparenta bajo el título ni entre las tarjetas.
                Color.black
                    .opacity(dark ? 1 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                header
                    .opacity(headerIn && picked == nil ? 1 : 0)
                    .offset(y: headerIn ? 0 : motion.distance(6))
                ForEach(Array(cards.enumerated()), id: \.element) { index, card in
                    FanCard(card: card, cents: cents(for: card), labelDelay: labelDelay(index, step: step),
                            fanned: fanned, action: { pick(card) })
                        .frame(height: Self.cardHeight)
                        .padding(.horizontal, 28)
                        .modifier(FlightSource(card: card))
                        .modifier(FanPlacement(
                            index: index, fanned: fanned,
                            state: picked == nil ? .fanned : (picked == card ? .chosen : .dropped),
                            startY: startY, slotY: headerHeight + CGFloat(index) * step))
                        .zIndex(Double(index))
                        .disabled(picked != nil || closing)
                }
            }
        }
        // Inicio, debajo, queda fuera de la accesibilidad mientras el abanico está abierto (lo hace quien lo monta).
        .accessibilityAction(.escape, close)
        .sensoryFeedback(.impact(weight: .medium), trigger: pickTick)
        .onAppear {
            #if DEBUG
            HomeProbe.shared.fanOpen = true
            HomeProbe.shared.fanOpenings += 1
            #endif
            open()
        }
        .onDisappear {
            #if DEBUG
            HomeProbe.shared.fanOpen = false
            #endif
        }
    }

    /// En dos tiempos, sin doble exposición: primero el negro tapa Inicio (cabecera, título, ojo y la tarjeta grande con
    /// su total) en 0,10 s; solo entonces las tarjetas salen de debajo y «Tus tarjetas» entra (0,15 s, subiendo 6 pt).
    private func open() {
        let first: Animation = motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(0.10))
        withAnimation(first) {
            dark = true
        } completion: {
            guard !closing, picked == nil else { return }
            withAnimation(motion.calmAnimation(.snap)) { fanned = true }
            withAnimation(motion.reduce ? motion.fade : .easeOut(duration: motion.seconds(0.15))) { headerIn = true }
        }
    }

    /// Cuándo aparecen el nombre y el saldo de la tarjeta `index`: cuando su franja ya se ha separado unos 30 pt de la
    /// de detrás (su escalón de 60 ms más lo que tarda el muelle en abrir ese tramo). Antes, solo la tarjeta: los textos
    /// de varias tarjetas nunca se ven montados unos sobre otros.
    private func labelDelay(_ index: Int, step: CGFloat) -> Double {
        guard !motion.reduce else { return 0 }
        let share = step > 6 ? min(1, (30 - 6) / (step - 6)) : 1
        return motion.stagger(index, firstGap: 0.06, decay: 1) + motion.seconds(0.30 * share)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tus tarjetas")
                    .titan(.homeTitle)
                    .foregroundStyle(Theme.label)
                    .accessibilityAddTraits(.isHeader)
                Text("Toca una para abrirla.")
                    .titan(.subtitle)
                    .foregroundStyle(Theme.label2)
            }
            Spacer(minLength: 12)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .frame(width: 44, height: 44)
                    .glassSurface(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.glassPress)
            .accessibilityLabel("Cerrar")
            .accessibilityIdentifier("wallet-fan-close")
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerContent = $0 }
        .frame(height: headerHeight, alignment: .top)
    }

    private func cents(for card: AccountCard) -> Int? {
        if card == .investments { return portfolioSummary?.valueCents }
        if let bank = card.bank { return snapshot.balances[bank]?.cents }
        return snapshot.total
    }

    /// Una tarjeta tocada: las demás caen, se apunta el vuelo y, un instante después (lo que tardan en caer), se abre.
    private func pick(_ card: AccountCard) {
        guard picked == nil, !closing else { return }
        withAnimation(motion.animation(.snap)) { picked = card }
        pickTick += 1
        #if DEBUG
        HomeProbe.shared.fanPicked = card.rawValue
        #endif
        if let bank = card.bank, let flight, let flightRequest = flight.makeRequest(bank: bank, card: card) {
            // Mientras no exista la capa que hace volar la tarjeta, la cabecera del banco se ve en el acto (`landed`):
            // abrir el banco funciona como siempre. La capa del vuelo pondrá `landed = false` al despegar.
            flight.landed = true
            flight.request = flightRequest
            #if DEBUG
            HomeProbe.shared.flightRequests += 1
            #endif
        }
        let beat = motion.seconds(motion.reduce ? 0.05 : 0.22)
        Task {
            try? await Task.sleep(for: .seconds(beat))
            onPick(card)
        }
    }

    /// Las tarjetas vuelven bajo la tarjeta de la que salieron y la capa se quita.
    private func close() {
        guard !closing, picked == nil else { return }
        closing = true
        withAnimation(motion.calmAnimation(.snap)) {
            fanned = false
            headerIn = false
            dark = false
        }
        let wait = motion.seconds(motion.reduce ? 0.22 : 0.34)
        Task {
            try? await Task.sleep(for: .seconds(wait))
            onClose()
        }
    }
}

/// Apunta el marco de la tarjeta como origen del vuelo (solo las de un banco tienen pantalla a la que volar).
private struct FlightSource: ViewModifier {
    let card: AccountCard

    func body(content: Content) -> some View {
        if let bank = card.bank {
            content.cardFlightSource(bank: bank, card: card)
        } else {
            content
        }
    }
}

/// Dónde está cada tarjeta del abanico. Recogida: bajo la tarjeta levantada, algo más pequeña e inclinada hacia atrás.
/// Abierta: en su escalón. Elegida: en su escalón, un 4 % más grande. Las demás, al elegir: caen 300 pt, al 88 %,
/// inclinadas y al 20 %. Cada tarjeta se abre con su retraso (60 ms × su puesto).
private struct FanPlacement: ViewModifier {
    enum Phase { case fanned, chosen, dropped }

    let index: Int
    let fanned: Bool
    let state: Phase
    let startY: CGFloat
    let slotY: CGFloat

    @Environment(\.motion) private var motion
    @State private var placed = false
    /// Opaca desde el primer momento (cada tarjeta tapa a la de detrás: nunca se transparentan los textos de varias).
    @State private var visible = false

    /// El muelle de apertura: el `snap` del nivel con poco rebote (≈ 0,12): el abanico llega a su sitio sin abrirse de
    /// más y volver.
    private var openSpring: Animation {
        guard !motion.reduce else { return motion.fade }
        let spec = MotionMath.scaled(SpringToken.snap.base, level: motion.level, timeMultiplier: motion.timeMultiplier)
        return .spring(response: spec.response, dampingFraction: max(spec.dampingFraction, 0.88))
    }

    func body(content: Content) -> some View {
        let reduce = motion.reduce
        let open = placed || reduce
        let dropped = state == .dropped
        let y: CGFloat = open ? slotY + (dropped && !reduce ? 300 : 0) : startY + CGFloat(index) * 6
        let scale: CGFloat = !open ? 0.94 : (state == .chosen && !reduce ? 1.04 : (dropped && !reduce ? 0.88 : 1))
        let lean: Double = reduce ? 0 : (!open ? 14 : (dropped ? 12 : 0))
        content
            .rotation3DEffect(.degrees(lean), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.5)
            .scaleEffect(scale, anchor: .top)
            .offset(y: y)
            .opacity(visible ? (dropped ? 0.2 : 1) : 0)
            .onAppear { place(fanned) }
            .onChange(of: fanned) { _, now in place(now) }
    }

    private func place(_ now: Bool) {
        guard now != placed else { return }
        if now {
            // Aparece en un instante (opaca) y se abre con su escalón.
            withAnimation(motion.reduce ? motion.fade : .linear(duration: motion.seconds(0.05))) { visible = true }
            withAnimation(openSpring.delay(motion.stagger(index, firstGap: 0.06, decay: 1))) { placed = true }
        } else {
            // Al recoger, todas a la vez, apagándose mientras vuelven.
            withAnimation(motion.calmAnimation(.snap)) {
                placed = false
                visible = false
            }
        }
    }
}

/// Una tarjeta del abanico: el material del banco, su nombre y, a la derecha, su saldo (con el ojo cerrado, la máscara).
private struct FanCard: View {
    let card: AccountCard
    let cents: Int?
    /// Cuándo aparecen su nombre y su saldo tras empezar a abrirse (ver `WalletFan.labelDelay`).
    let labelDelay: Double
    let fanned: Bool
    let action: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @State private var labelShown = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if let bank = card.bank {
                        BankLogo(bank: bank, size: 26)
                    }
                    Text(card.spokenName)
                        .titan(.cardTitle)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let cents {
                        MaskedAmountText(formatEUR(cents), masked: maskedEUR(cents, sign: false))
                            .titan(.cardTitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Text("—").titan(.cardTitle)
                    }
                }
                .frame(minHeight: 34)
                .opacity(labelShown ? 1 : 0)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CardSurface(material: card.material, moves: false))
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.pressable)
        .onChange(of: fanned, initial: true) { _, now in
            guard now, !labelShown else { return }
            withAnimation(.easeOut(duration: motion.seconds(0.12)).delay(labelDelay)) { labelShown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.spokenName), \(cents.map { spokenAmount($0, hidden: preferences.privateMode) } ?? "sin saldo")")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("wallet-card-\(card.rawValue)")
    }
}
