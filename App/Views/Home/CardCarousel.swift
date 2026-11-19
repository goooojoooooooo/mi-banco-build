import SwiftUI
import MiBancoCore

/// El carrusel de cuentas: paginado horizontal con la física del sistema y encaje en cada tarjeta
/// (`viewAligned`), los vecinos asomando 32 pt, girados en 3D (±22°, perspectiva 0,6), al 92 % y apagados.
/// La posición continua (para el indicador del segmentado y el brillo) sale de la geometría del scroll,
/// nunca del `body`. Para VoiceOver es un solo elemento ajustable: "Cuenta, Revolut, 340,20 euros, 2 de 4".
struct CardCarousel: View {
    let snapshot: LedgerSnapshot
    @Binding var selection: AccountCard?
    @Binding var flipped: AccountCard?
    let motion: HomeMotion
    let onEdit: (BankID?) -> Void

    /// Tarjetas que ya se han visto: su cifra contó desde 0 la primera vez.
    @State private var seen: Set<AccountCard> = []
    /// Lo que enseña el scroll. Va aparte de `selection` a propósito: antes de que el carrusel tenga ancho
    /// (primer pase de maquetación) no se le pide ir a ninguna tarjeta y lo que escriba el scroll se ignora;
    /// después, cada lado solo copia al otro un valor distinto y nunca `nil`, así que no puede haber eco.
    @State private var scrolledID: AccountCard?
    @State private var measured = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences

    private var current: AccountCard { selection ?? .all }

    var body: some View {
        let reduce = reduceMotion
        ScrollView(.horizontal) {
            HStack(spacing: CarouselMetrics.spacing) {
                ForEach(AccountCard.allCases, id: \.self) { card in
                    AccountCardView(
                        card: card, balances: snapshot.balances, total: snapshot.total,
                        monthSpent: snapshot.monthSpent[card] ?? 0, flipped: flipped == card,
                        revealed: seen.contains(card),
                        onFlip: { tap(card) }, onEdit: { onEdit(card.bank) })
                        .containerRelativeFrame(.horizontal)
                        .frame(maxHeight: .infinity)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .rotation3DEffect(.degrees(reduce ? 0 : phase.value * -22),
                                                  axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                .scaleEffect(reduce ? 1 : 1 - 0.08 * abs(phase.value))
                                .brightness(-0.25 * abs(phase.value))
                        }
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if visible { seen.insert(card) }
                        }
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
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Paso entre tarjetas medido en el contenido (n tarjetas + n−1 huecos), no en el contenedor: el ancho del
            // contenedor ya viene sin el margen lateral y restarlo otra vez desplazaba el indicador (1,2 en vez de 1).
            let count = CGFloat(AccountCard.allCases.count)
            let step = (geometry.contentSize.width + CarouselMetrics.spacing) / count
            return step > 0 ? (geometry.contentOffset.x + geometry.contentInsets.leading) / step : 0
        } action: { _, position in
            guard position.isFinite else { return }
            motion.carouselPosition = position
            let last = CGFloat(AccountCard.allCases.count - 1)
            let over = position < -0.04 || position > last + 0.04
            if over != motion.carouselOverscrolled { motion.carouselOverscrolled = over }
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
        .onChange(of: scrolledID) { _, new in
            // El dedo (o el sistema) dejó el carrusel en otra tarjeta: eso pasa a ser la elegida.
            guard measured, let new, new != selection else { return }
            selection = new
        }
        .onChange(of: selection) { _, new in
            if flipped != nil { flipped = nil }
            if let new { seen.insert(new) }
            // Segmentado, VoiceOver, toque en un vecino o llegada: el carrusel va hasta allí con su muelle.
            guard measured, let new, new != scrolledID else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) { scrolledID = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint("Desliza hacia arriba o hacia abajo para cambiar de cuenta")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: flipped == current ? "Ver el saldo" : "Ver detalles de la cuenta") { tap(current) }
        .accessibilityAction(named: current == .all ? "Editar saldos" : "Editar saldo") { onEdit(current.bank) }
    }

    /// Una sola vez, con el carrusel ya maquetado: se coloca en la tarjeta elegida sin animación (p. ej. la demo con Revolut).
    private func settleInitialPosition() {
        guard !measured else { return }
        measured = true
        // La tarjeta de delante cuenta su cifra aunque el aviso de visibilidad no llegue.
        seen.insert(current)
        if current != .all { scrolledID = current }
    }

    private func tap(_ card: AccountCard) {
        guard card == current else {
            withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) { selection = card }
            return
        }
        flipped = flipped == card ? nil : card
    }

    private func move(by step: Int) {
        let all = AccountCard.allCases
        let next = min(max(current.index + step, 0), all.count - 1)
        withAnimation(reduceMotion ? nil : Theme.Motion.cardSettle) { selection = all[next] }
    }

    private var spokenLabel: String {
        let hidden = preferences.privateMode
        let position = "\(current.index + 1) de \(AccountCard.allCases.count)"
        guard let bank = current.bank else {
            let total = snapshot.total.map { spokenAmount($0, hidden: hidden) } ?? "sin saldo"
            return "Todo, \(total) en tres cuentas, \(position)"
        }
        guard let info = snapshot.balances[bank] else { return "Cuenta, \(bank.displayName), sin saldo, \(position)" }
        let estimate = info.estimated ? ", estimado" : ""
        return "Cuenta, \(bank.displayName), \(spokenAmount(info.cents, hidden: hidden))\(estimate), \(position)"
    }
}
