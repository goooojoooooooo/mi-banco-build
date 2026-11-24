import SwiftUI
import MiBancoCore

/// Detalle de un movimiento, en una hoja (cristal del sistema en iOS 26). Llega con la transición de zoom desde el
/// logo de la fila; cuando el logo se ha posado, el resto entra escalonado (60 ms). El importe cuenta desde 0.
/// Todas las acciones pasan por `LedgerModel` (mutaciones de Core) y la lista de Inicio se actualiza sola.
struct MovementDetailSheet: View {
    let model: LedgerModel
    let id: UUID
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
                DetailContent(movement: movement, snapshot: model.snapshot, model: model,
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
                        .staggeredEntrance(5, rise: 8)
                    Text("\(DateText.moment(movement.date, dayOnly: movement.dayOnly)) · \(movement.bank.displayName)")
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .padding(.top, 3)
                        .staggeredEntrance(5, rise: 8)
                    // El importe rueda (`RollingAmount` ya oculta las cifras con el ojo cerrado y se encoge si no cabe).
                    RollingAmount(cents: movement.amountCents, style: .plain(sign: true))
                        .font(.system(size: amountSize, weight: .semibold))
                        .tracking(-amountSize * 0.03)
                        .foregroundStyle(movement.amountCents > 0 && !movement.flaggedNotMine ? Theme.income : Theme.label)
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
                        .padding(.top, 10)
                        .opacity(amountShown ? 1 : 0)
                        .offset(y: amountShown ? 0 : motion.distance(10))
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
                        .accessibilityLabel("Te quedaban \(spokenAmount(after, hidden: hidden))")
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
                .staggeredEntrance(7)

                if movement.kind == .payment, let key = merchantKey, let history = snapshot.histories[key] {
                    MerchantHistoryGroup(history: history, recent: snapshot.recentPayments[key] ?? [], current: movement.id)
                        .staggeredEntrance(8)
                }

                if editingNote || movement.note != nil {
                    noteGroup
                        .staggeredEntrance(9)
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
                .staggeredEntrance(10)

                SlideToConfirm(title: "Desliza para borrar el movimiento", action: onDelete)
                    .padding(.top, 6)
                    .staggeredEntrance(11)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: movement)
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: editingNote)
        }
        .scrollIndicators(.hidden)
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
        .task {
            // Respaldo: si la animación de entrada no llegara a avisar, «Te quedaban» no se queda oculto.
            try? await Task.sleep(for: .seconds(motion.seconds(0.8) + 1))
            amountShown = true
            amountLanded = true
        }
    }

    /// El importe entra con el muelle de vuelo (con Reducir movimiento, un fundido) y al posarse destapa «Te quedaban».
    private func landAmount() {
        guard !amountShown else { return }
        withAnimation(motion.animation(.fly).delay(motion.seconds(0.3)), completionCriteria: .logicallyComplete) {
            amountShown = true
        } completion: {
            amountLanded = true
        }
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
