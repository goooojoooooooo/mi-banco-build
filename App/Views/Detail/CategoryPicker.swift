import SwiftUI
import MiBancoCore

/// Fila «Categoría» de la hoja del movimiento (solo pagos): un chip con el símbolo y el nombre. Al tocarlo, la propia
/// fila se despliega (sin hoja nueva ni popover: la hoja de detalle es la única que hay y la cierra el bloqueo)
/// en una rejilla de 4 x 3 fichas que entran escalonadas. La elegida va en blanco con símbolo negro y una marca que se
/// dibuja con un muelle. Elegir guarda, da una háptica de selección y pliega la rejilla; el chip cambia de símbolo y de
/// nombre con un fundido. Con Reducir movimiento todo son fundidos.
struct CategoryPickerRow: View {
    let movement: Movement
    /// La categoría que tiene ahora el pago (calculada una vez por el snapshot, no aquí).
    let current: SpendingCategory
    let model: LedgerModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 60
    @State private var expanded: Bool
    @State private var applyToMerchant = true
    @State private var selectTick = 0
    @State private var errorTick = 0

    init(movement: Movement, current: SpendingCategory, model: LedgerModel) {
        self.movement = movement
        self.current = current
        self.model = model
        var open = false
        #if DEBUG
        open = DemoMode.isActive && DemoMode.opensCategory
        #endif
        _expanded = State(initialValue: open)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    /// El comercio con el nombre con que llegó; nil si el movimiento no lo tiene (entonces no hay "aplicar a todo").
    private var merchantName: String? {
        guard let merchant = movement.merchant, !normalizeMerchant(merchant).isEmpty else { return nil }
        return merchant
    }

    private var fold: Animation { reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Categoría").foregroundStyle(Theme.label2)
                Spacer(minLength: 8)
                chip
            }
            .titan(.option)
            .fontWeight(.regular)
            .padding(.horizontal, 16)
            .frame(minHeight: 50)

            if expanded {
                picker
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
        }
        .sensoryFeedback(Haptics.detent, trigger: selectTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private var chip: some View {
        Button {
            withAnimation(fold) { expanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: current.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 20)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: reduceMotion ? 0 : selectTick)
                Text(current.displayName)
                    .fontWeight(.medium)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.white.opacity(0.10), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph, value: current)
        .accessibilityIdentifier("category-chip")
        .accessibilityLabel("Categoría: \(current.displayName)")
        .accessibilityHint(expanded ? "Toca para cerrar la lista" : "Toca para cambiarla")
    }

    private var picker: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Array(SpendingCategory.allCases.enumerated()), id: \.element) { index, category in
                    CategoryTile(category: category, selected: category == current, index: index, height: tileHeight) {
                        choose(category)
                    }
                }
            }
            if let merchant = merchantName {
                Toggle(isOn: $applyToMerchant) {
                    Text("Aplicar a todo lo de \(merchant)")
                        .titan(.callout)
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                }
                .toggleStyle(TitanToggleStyle())
                .padding(.horizontal, 4)
                .accessibilityIdentifier("category-apply-merchant")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func choose(_ category: SpendingCategory) {
        // Tocar la que ya tiene no fija nada: la categoría sigue siendo la que decide la app.
        guard category != current else {
            withAnimation(fold) { expanded = false }
            return
        }
        do {
            try model.setCategory(category, for: movement.id, applyToMerchant: applyToMerchant && merchantName != nil)
            selectTick += 1
            withAnimation(fold) { expanded = false }
        } catch {
            errorTick += 1
        }
    }
}

/// Una ficha de la rejilla: símbolo y nombre. La elegida, blanca con símbolo negro y una marca dibujada.
private struct CategoryTile: View {
    let category: SpendingCategory
    let selected: Bool
    let index: Int
    let height: CGFloat
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                Text(category.displayName)
                    .titan(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Color.black : Theme.label)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(selected ? Color.white : Color.white.opacity(0.10), in: shape)
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(Color.black)
                        DrawnCheck(lineWidth: 1.8, color: .white).frame(width: 9, height: 9)
                    }
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.35), value: selected)
        // Entrada escalonada de la rejilla (30 ms por ficha); con Reducir movimiento, solo un fundido.
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : 0.86)
        .offset(y: shown || reduceMotion ? 0 : 6)
        .onAppear {
            guard !shown else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.assemble.delay(Double(index) * 0.03)) {
                shown = true
            }
        }
        .accessibilityIdentifier("category-tile-\(category.rawValue)")
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Fila «Traspaso entre tus cuentas»: un interruptor. Encenderlo guarda `true`; apagarlo guarda `false` (también si el
/// traspaso lo había detectado la app: así no vuelve a emparejarse solo).
struct OwnTransferRow: View {
    let movement: Movement
    /// Ya calculado por el snapshot (pares detectados y marcados a mano).
    let isOn: Bool
    let model: LedgerModel

    @State private var tick = 0
    @State private var errorTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(get: { isOn }, set: { newValue in apply(newValue) })) {
                Text("Traspaso entre tus cuentas")
                    .titan(.option)
                    .foregroundStyle(Theme.label)
            }
            .toggleStyle(TitanToggleStyle())
            .accessibilityIdentifier("own-transfer-toggle")
            Text("No cuenta como gasto ni como ingreso.")
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
        }
        .sensoryFeedback(Haptics.toggle, trigger: tick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private func apply(_ on: Bool) {
        do {
            try model.setOwnTransfer(on, for: movement.id)
            tick += 1
        } catch {
            errorTick += 1
        }
    }
}
