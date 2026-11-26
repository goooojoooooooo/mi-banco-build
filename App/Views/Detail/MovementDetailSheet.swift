import SwiftUI
import MiBancoCore

/// Detalle de un movimiento, en una hoja (cristal del sistema en iOS 26). Llega con la transición de zoom desde el
/// logo de la fila; el importe vuela desde donde estaba en la fila hasta su sitio (D1) y las líneas entran escalonadas
/// desde 0,15 s (55 ms × 0,82ⁿ). «Te quedaban» empieza oculto y rueda cuando el importe se posa.
/// Todas las acciones pasan por `LedgerModel` (mutaciones de Core) y la lista de Inicio se actualiza sola.
struct MovementDetailSheet: View {
    let model: LedgerModel
    let id: UUID
    /// Dónde estaba el importe en la fila tocada (pantalla completa); nil si no se abrió desde una fila de Inicio.
    var amountOrigin: CGRect? = nil
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var entrance = Entrance()

    /// Solo en la demo de capturas con la hoja abierta por argumento (la fase de escena parpadea en el simulador de CI).
    private var demoKeepsVisible: Bool {
        #if DEBUG
        return DemoMode.isActive && DemoMode.opensDetail
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if let movement = model.movement(id) {
                DetailContent(movement: movement, snapshot: model.snapshot, model: model, amountOrigin: amountOrigin,
                              onClose: { dismiss() }, onDelete: { onDelete(id) })
            } else {
                Color.clear
            }
        }
        .environment(\.entrance, entrance)
        // Segunda línea de defensa (la primera: RootView cierra la hoja): fuera de primer plano, la hoja es negra.
        .overlay {
            if scenePhase != .active && !demoKeepsVisible {
                Theme.canvas
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            entrance = Entrance(token: 1, active: true, scope: .assembly)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.6))
            entrance.active = false
        }
    }
}

private struct DetailContent: View {
    let movement: Movement
    let snapshot: LedgerSnapshot
    let model: LedgerModel
    let amountOrigin: CGRect?
    let onClose: () -> Void
    let onDelete: () -> Void

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 60
    /// El importe entra (sube y aparece) y, cuando se ha posado, «Te quedaban» deja de estar oculto y rueda desde 0:
    /// nunca enseña su cifra final antes de contar.
    @State private var amountShown = false
    @State private var amountLanded = false
    /// m-9: cuándo se posa el importe (s desde que se pide); lo cumple un `.task(id:)`, que se cancela con la hoja.
    @State private var landingDue: Double?
    /// Lote final: los grupos de debajo del importe no entran mientras el importe vuela por encima de ellos (si vuela
    /// desde la fila); entran en cuanto se posa. Sin vuelo (o con Reducir movimiento), como siempre.
    private var groupsReleased: Bool { amountOrigin == nil || motion.reduce || amountLanded }
    /// D1: el vuelo del importe desde la fila (0 = donde estaba en la fila, 1 = en su sitio), desde dónde sale y a qué
    /// escala, y dónde está su sitio en la pantalla (se mide; solo se lee al empezar el vuelo).
    // Empieza en 0: sin origen (y con el desplazamiento a cero) es la identidad; con origen, el vuelo es un cambio de 0 a 1
    // (si empezara en 1 y se pusiera a 0 y a 1 en la misma actualización, no habría nada que animar).
    @State private var flight: CGFloat = 0
    @State private var flyDelta = CGSize.zero
    @State private var flyScale: CGFloat = 1
    @State private var slotFrame: CGRect?
    @State private var landingStarted = false
    /// El vuelo espera a que la hoja se pose (su subida o su zoom la lleva el sistema): mientras se mueve, el sitio
    /// medido del importe no es el final.
    @State private var flightArmed = false
    @State private var editingNote = false
    @State private var noteText = ""
    @State private var noteSaved = false
    @State private var flagTick = 0
    @State private var errorTick = 0
    @FocusState private var noteFocused: Bool

    private var merchantKey: String? {
        movement.merchant.map(normalizeMerchant).flatMap { $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        let logo = logos.image(merchant: movement.merchant, domain: snapshot.logoDomains[movement.id], isShop: movement.isShop)
        let hidden = preferences.privateMode
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    MerchantTile(image: logo, symbol: movement.fallbackSymbol, size: tileSize)
                    Text(movement.displayTitle)
                        .titan(.sheetTitle)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .staggeredEntrance(0, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)
                    Text("\(DateText.moment(movement.date, dayOnly: movement.dayOnly)) · \(movement.bank.displayName)")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .padding(.top, 3)
                        .staggeredEntrance(1, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)
                    // El importe rueda (`RollingAmount` ya oculta las cifras con el ojo cerrado y se encoge si no cabe).
                    RollingAmount(cents: movement.amountCents, style: .plain(sign: true))
                        .font(.system(size: amountSize, weight: .semibold))
                        .tracking(-amountSize * 0.03)
                        .foregroundStyle(movement.amountCents > 0 && !movement.flaggedNotMine ? Theme.income : Theme.label)
                        // m-12: los dígitos que ruedan no salen de su línea (no pisan «Hoy, 16:43 · Revolut» de encima):
                        // el recorte deja fuera también el aire de arriba de la línea (el ascendente de la fuente), que
                        // era por donde entraban los dígitos hasta tocar la fecha (run12 `row-detail` 7–12).
                        .clipShape(TopTrimmed(fraction: 0.15))
                        // «No es mío»: la raya se dibuja encima (las cifras que ruedan no son texto que se pueda tachar).
                        .overlay {
                            if movement.flaggedNotMine {
                                Capsule()
                                    .fill(Theme.label3)
                                    .frame(height: max(1.5, amountSize * 0.055))
                                    .offset(y: amountSize * 0.06)
                                    .transition(.opacity)
                            }
                        }
                        // D1: el importe vuela desde la fila (solo transformaciones; sus dígitos ruedan dentro de su
                        // propio grupo, que no se deforma con el vuelo).
                        .geometryGroup()
                        .modifier(ArcFlight(progress: flight, delta: flyDelta, arc: motion.distance(30), startScale: flyScale))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            slotFrame = frame
                            landAmount()
                        }
                        .padding(.top, 10)
                        .opacity(amountShown ? 1 : 0)
                        .offset(y: amountShown || flyDelta != .zero ? 0 : motion.distance(10))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(movement.amountCents < 0 ? "Pago de" : "Ingreso de") \(spokenAmount(abs(movement.amountCents), hidden: hidden))")
                    if movement.flaggedNotMine {
                        Label("No es tuyo: no cuenta en tu gasto", systemImage: "exclamationmark.triangle.fill")
                            .titan(.meta)
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.warning.opacity(0.12), in: Capsule())
                            .padding(.top, 10)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                DetailGroup {
                    if let after = snapshot.balanceAfter[movement.id] {
                        DetailPair(key: "Te quedaban") {
                            HStack(spacing: 6) {
                                // Empieza oculto: ni un 0 ni la cifra final hasta que el importe de arriba se posa.
                                RollingAmount(cents: after, revealed: amountLanded)
                                    .opacity(amountLanded ? 1 : 0)
                                    .animation(motion.fade, value: amountLanded)
                                if snapshot.balances[movement.bank]?.estimated ?? false {
                                    Text("estimado").titan(.meta).foregroundStyle(Theme.label3)
                                }
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        // Hasta que el importe de arriba se posa, «Te quedaban» no dice cifra (tampoco a VoiceOver): no la
                        // enseña antes de contarla.
                        .accessibilityLabel(amountLanded ? "Te quedaban \(spokenAmount(after, hidden: hidden))" : "Te quedaban")
                    }
                    DetailPair(key: "Cuenta", divided: snapshot.balanceAfter[movement.id] != nil) {
                        HStack(spacing: 8) {
                            BankLogo(bank: movement.bank, size: 20)
                            Text(movement.bank.displayName)
                        }
                    }
                    DetailPair(key: "Tipo", divided: true) { Text(kindText) }
                    // Un traspaso entre tus cuentas no es gasto: no tiene categoría (la fila vuelve al apagar el interruptor).
                    if movement.kind == .payment && !snapshot.ownTransfers.contains(movement.id) {
                        CategoryPickerRow(movement: movement, current: snapshot.categories[movement.id] ?? .sinCategoria, model: model)
                    }
                    OwnTransferRow(movement: movement, isOn: snapshot.ownTransfers.contains(movement.id), model: model)
                }
                .staggeredEntrance(2, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)

                .modifier(HeldUntilLanded(released: groupsReleased, index: 0))

                if movement.kind == .payment, let key = merchantKey, let history = snapshot.histories[key] {
                    MerchantHistoryGroup(history: history, recent: snapshot.recentPayments[key] ?? [], current: movement.id)
                        .staggeredEntrance(3, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)

                        .modifier(HeldUntilLanded(released: groupsReleased, index: 1))
                }

                if editingNote || movement.note != nil {
                    noteGroup
                        .staggeredEntrance(4, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)

                        .modifier(HeldUntilLanded(released: groupsReleased, index: 2))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                DetailGroup {
                    DetailAction(title: movement.note == nil ? "Añadir nota" : "Editar nota", systemImage: "pencil", action: startNote)
                    DetailAction(title: movement.flaggedNotMine ? "Sí es mío" : "No es mío",
                                 systemImage: movement.flaggedNotMine ? "checkmark.circle" : "exclamationmark.triangle",
                                 tint: movement.flaggedNotMine ? Theme.label2 : Theme.warning, divided: true,
                                 bounce: flagTick, action: toggleFlag)
                    if let merchant = movement.merchant {
                        let muted = snapshot.isMuted(merchant)
                        DetailAction(title: muted ? "Dejar de silenciar \(merchant)" : "Silenciar \(merchant)",
                                     systemImage: muted ? "bell" : "bell.slash", divided: true) {
                            setMuted(!muted, merchant: merchant)
                        }
                    }
                }
                .staggeredEntrance(5, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)

                .modifier(HeldUntilLanded(released: groupsReleased, index: 3))

                SlideToConfirm(title: "Desliza para borrar el movimiento", action: onDelete)
                    .padding(.top, 6)
                    .staggeredEntrance(6, rise: 16, lead: Self.linesLead, firstGap: Self.linesGap, decay: Self.linesDecay)

                    .modifier(HeldUntilLanded(released: groupsReleased, index: 4))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: movement)
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: editingNote)
        }
        .scrollIndicators(.hidden)
        // Para las pruebas de toque: lo que hay DENTRO de la hoja (no lo de Inicio, debajo).
        .accessibilityIdentifier("movement-detail-scroll")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Cerrar")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .sensoryFeedback(Haptics.warning, trigger: flagTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .sensoryFeedback(Haptics.success, trigger: noteSaved) { _, new in new }
        .onChange(of: noteFocused) { _, focused in
            if !focused && editingNote { commitNote() }
        }
        .onAppear(perform: landAmount)
        .task { await backstop() }
        .task(id: flightArmed) { await flightAfterPresentation() }
        .task(id: landingDue) {
            guard let due = landingDue else { return }
            try? await Task.sleep(for: .seconds(due))
            guard !Task.isCancelled else { return }
            amountLanded = true
        }
    }

    /// D1. El importe sale volando desde donde estaba en la fila (si se abrió desde una fila de Inicio y se conocen
    /// los dos sitios) con el muelle de vuelo y un arco de 30 pt; si no, sube 10 pt y aparece, como antes. Con Reducir
    /// movimiento, solo un fundido. Al posarse destapa «Te quedaban», que rueda desde 0 (nunca enseña antes su cifra).
    /// Se llama al aparecer y cuando se mide su sitio: empieza una sola vez, con lo que se sepa entonces.
    private func landAmount() {
        guard !landingStarted else { return }
        if !motion.reduce, amountOrigin != nil {
            // La presentación de la hoja (subida o zoom desde el logo) la anima el sistema, a su velocidad: el vuelo
            // sale cuando ha terminado (0,45 s reales), desde donde estaba el importe en la fila hasta su sitio ya quieto.
            flightArmed = true
            return
        }
        startFlight()
    }

    private func startFlight() {
        guard !landingStarted else { return }
        landingStarted = true
        if !motion.reduce, let start = FlyInGeometry.start(from: amountOrigin, to: slotFrame) {
            // Desde la fila: en su sitio de salida, sin animar, y desde ahí vuela (el sitio ya está medido).
            flyDelta = start.delta
            flyScale = start.scale
            amountShown = true
            withAnimation(motion.animation(.fly).delay(motion.seconds(0.05))) { flight = 1 }
            landingDue = motion.seconds(0.05) + flightSettle
            return
        }
        withAnimation(motion.animation(.fly).delay(motion.seconds(0.3))) { amountShown = true }
        // m-1: con Reducir es un fundido: se posa cuando acaba (no tras la espera del muelle).
        landingDue = motion.seconds(0.3) + (motion.reduce ? motion.fadeDuration : flightSettle)
    }

    /// La entrada escalonada de las líneas del detalle: desde 0,15 s, 55 ms × 0,82ⁿ (la usan también los grupos que
    /// esperan a que el importe se pose).
    static let linesLead = 0.15
    static let linesGap = 0.055
    static let linesDecay = 0.82

    /// I-1 (ronda 1): cuándo se VE posado el importe que vuela: la envolvente de su muelle `fly` (con la intensidad y la
    /// cámara lenta) baja del 5 % (`MotionMath.visibleSettle`, ~0,28 s en Equilibrado). Antes no se suelta nada: la
    /// garantía de m-12 sigue (es una pausa que lee `\.motion`, no una `completion`).
    private var flightSettle: Double {
        MotionMath.visibleSettle(
            MotionMath.scaled(SpringToken.fly.base, level: motion.level, timeMultiplier: motion.timeMultiplier))
    }

    /// La espera del vuelo: la presentación de la hoja la lleva el sistema a su velocidad (no va a cámara lenta), así
    /// que son 0,45 s reales; después, el vuelo con lo medido.
    private func flightAfterPresentation() async {
        guard flightArmed, !landingStarted else { return }
        try? await Task.sleep(for: .seconds(0.45))
        guard !Task.isCancelled else { return }
        startFlight()
    }

    /// Respaldo (m-5): si el vuelo no llegara a avisar de que se posó, a los 0,8 s (según intensidad y cámara lenta)
    /// más 1 s de pausa (cámara lenta incluida) el importe se FUNDE en su sitio y «Te quedaban» rueda: nunca aparece
    /// de golpe. La espera es una pausa que lee `\.motion` (se probó a encadenarla al final de una animación invisible
    /// y SwiftUI la daba por acabada al instante: «Te quedaban» se destapaba antes de tiempo, run 45608404581).
    private func backstop() async {
        try? await Task.sleep(for: .seconds(motion.seconds(0.8) + motion.pause(1) + (amountOrigin == nil ? 0 : 0.45)))
        guard !Task.isCancelled, !amountLanded else { return }
        withAnimation(motion.fade) {
            amountShown = true
            if flyDelta != .zero { flight = 1 }
        }
        amountLanded = true
    }

    private var kindText: String {
        if movement.source == .bank { return "Tu banco" }
        if movement.source == .statement { return "Extracto importado" }
        if movement.bankRef != nil { return "Aviso · confirmado por tu banco" }
        if movement.source == .wallet { return "Apple Pay" }
        if movement.kind == .income { return "Ingreso" }
        return movement.isShop ? "Compra con tarjeta" : "Pago"
    }

    private var noteGroup: some View {
        DetailGroup {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "note.text")
                    .foregroundStyle(Theme.label2)
                    .accessibilityHidden(true)
                if editingNote {
                    TextField("Escribe una nota", text: $noteText, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onSubmit(commitNote)
                } else {
                    Text(movement.note ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: startNote)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Toca para editar la nota")
                }
                if noteSaved {
                    DrawnCheck(lineWidth: 2, color: Theme.label)
                        .frame(width: 18, height: 18)
                        .transition(.opacity)
                }
            }
            .titan(.option)
            .foregroundStyle(Theme.label)
            .padding(16)
            .frame(minHeight: 52)
        }
    }

    private func startNote() {
        noteText = movement.note ?? ""
        editingNote = true
        noteFocused = true
    }

    private func commitNote() {
        noteFocused = false
        editingNote = false
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (movement.note ?? "") else { return }
        do {
            try model.setNote(trimmed.isEmpty ? nil : trimmed, for: movement.id)
            noteSaved = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.3)) { noteSaved = false }
            }
        } catch {
            errorTick += 1
        }
    }

    private func toggleFlag() {
        do {
            try model.setFlaggedNotMine(!movement.flaggedNotMine, for: movement.id)
            flagTick += 1
        } catch {
            errorTick += 1
        }
    }

    private func setMuted(_ muted: Bool, merchant: String) {
        do {
            try model.setMuted(muted, merchant: merchant)
        } catch {
            errorTick += 1
        }
    }
}

/// Grupo de la hoja: blanco al 7 % sobre el cristal (nunca cristal sobre cristal), radio 22.
struct DetailGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }
}

/// "Te quedaban ............ 327,70 €"
private struct DetailPair<Value: View>: View {
    let key: String
    var divided = false
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(key).foregroundStyle(Theme.label2)
            Spacer(minLength: 8)
            value
                .fontWeight(.medium)
                .foregroundStyle(Theme.label)
        }
        .titan(.option)
        .fontWeight(.regular)
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
            }
        }
    }
}

/// Una acción de la hoja (52 pt): icono a la izquierda, texto, sin chevron.
private struct DetailAction: View {
    let title: String
    let systemImage: String
    var tint = Theme.label2
    var divided = false
    var bounce = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 24)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: bounce)
                Text(title)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .lineLimit(2)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(background: .white.opacity(0.06)))
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 54)
            }
        }
    }
}

/// Lote final: un grupo del detalle que espera a que el importe se pose (`released`) para entrar: sube 16 pt y aparece
/// con el muelle `enter`, escalonado (55 ms × 0,82ⁿ). Si ya estaba suelto al aparecer, está desde el principio.
private struct HeldUntilLanded: ViewModifier {
    let released: Bool
    let index: Int
    @Environment(\.motion) private var motion
    @State private var shown: Bool?

    func body(content: Content) -> some View {
        let visible = shown ?? released
        // Se tapa con una máscara (no con `opacity`): mientras espera sigue a la vista de VoiceOver y de las pruebas, que
        // leen «Te quedaban» desde que se abre la hoja.
        content
            .mask { Color.black.opacity(visible ? 1 : 0) }
            // I-2 (ronda 1): mientras espera no recibe toques (no se cambia nada que no se ve).
            .allowsHitTesting(visible)
            .offset(y: visible ? 0 : motion.distance(16))
            .onAppear { if shown == nil { shown = released } }
            .onChange(of: released) { _, now in
                guard now, shown != true else { return }
                withAnimation(motion.animation(.enter).delay(motion.stagger(index, firstGap: DetailContent.linesGap, decay: DetailContent.linesDecay))) {
                    shown = true
                }
            }
    }
}
