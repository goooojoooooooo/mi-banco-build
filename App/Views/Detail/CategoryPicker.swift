import SwiftUI
import MiBancoCore

/// Fila «Categoría» de la hoja del movimiento (solo pagos): un chip con el símbolo y el nombre. Al tocarlo, la propia
/// fila se despliega (sin hoja nueva ni popover: la hoja de detalle es la única que hay y la cierra el bloqueo)
/// en una rejilla de fichas que entran escalonadas (4 x 3; 3 columnas en tamaños grandes y 2, de alto libre, en los de
/// accesibilidad). La elegida va en blanco con símbolo negro y una marca que se
/// dibuja con un muelle. Elegir guarda, da una háptica de selección y pliega la rejilla; el chip cambia de símbolo y de
/// nombre con un fundido. Con Reducir movimiento todo son fundidos.
struct CategoryPickerRow: View {
    let movement: Movement
    /// La categoría que tiene ahora el pago (calculada una vez por el snapshot, no aquí).
    let current: SpendingCategory
    let model: LedgerModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// D2: la ficha blanca de la elegida es UNA sola pieza que se desliza a la nueva al elegir.
    @Namespace private var selection
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 60
    @State private var expanded: Bool
    @State private var applyToMerchant: Bool
    @State private var selectTick = 0
    /// m-1: cuántas veces se ha elegido cada categoría: solo bota el símbolo de la que se elige (no el de la que se deja).
    @State private var bounces: [SpendingCategory: Int] = [:]
    @State private var errorTick = 0
    @State private var failed = false

    init(movement: Movement, current: SpendingCategory, model: LedgerModel) {
        self.movement = movement
        self.current = current
        self.model = model
        var open = false
        #if DEBUG
        open = DemoMode.isActive && DemoMode.opensCategory
        #endif
        _expanded = State(initialValue: open)
        // Un concepto genérico («Bizum a Ana», «Transferencia…») no es un comercio: por defecto, solo este pago.
        _applyToMerchant = State(initialValue: !isGenericPayee(movement.merchant))
    }

    /// 4 columnas; 3 en los tamaños grandes; 2 en los de accesibilidad (ahí la ficha crece con su texto).
    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 2 : (typeSize >= .xxLarge ? 3 : 4)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    /// El comercio con el nombre con que llegó; nil si el movimiento no lo tiene (entonces no hay "aplicar a todo").
    private var merchantName: String? {
        guard let merchant = movement.merchant, !normalizeMerchant(merchant).isEmpty else { return nil }
        return merchant
    }

    /// Con elección propia en el pago, el botón quita solo esa; sin ella y con una para todo el comercio, quita la del
    /// comercio y lo dice con su nombre (el mismo que muestra «Aplicar a todo lo de …»).
    private var resetTitle: String {
        if !model.hasOwnCategory(movement.id), let merchant = merchantName {
            return "Quitar mi categoría de todo \(merchant)"
        }
        return "Volver a la categoría automática"
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
                    // m-2 (lote final): sin doble exposición. Al desplegar, la rejilla se funde cuando las filas de
                    // debajo ya han bajado; al plegar, se va en 80 ms, antes de que suban. Solo opacidad.
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: motion.seconds(0.18)).delay(motion.seconds(0.12))),
                        removal: .opacity.animation(.easeIn(duration: motion.seconds(0.08)))))
            }
            if failed {
                SaveErrorText()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity)
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
            .background(Theme.chipFill, in: Capsule())
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
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(SpendingCategory.allCases.enumerated()), id: \.element) { index, category in
                    CategoryTile(category: category, selected: category == current, index: index, height: tileHeight,
                                 fixedHeight: !typeSize.isAccessibilitySize, selection: selection,
                                 bounce: bounces[category] ?? 0) {
                        choose(category)
                    }
                }
            }
            if model.hasChosenCategory(movement.id) {
                Button(action: resetToAutomatic) {
                    Text(resetTitle)
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.chipFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("category-automatic")
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
            // D2: la ficha blanca se desliza a la elegida (el muelle de los indicadores) y la rejilla se pliega cuando
            // ya ha llegado, para que se vea. Con Reducir movimiento, fundidos y sin espera.
            try withAnimation(motion.animation(.indicator)) {
                try model.setCategory(category, for: movement.id, applyToMerchant: applyToMerchant && merchantName != nil)
            }
            selectTick += 1
            if !motion.reduce { bounces[category, default: 0] += 1 }
            withAnimation(fold.delay(motion.reduce ? 0 : motion.seconds(0.32))) {
                failed = false
                expanded = false
            }
        } catch {
            errorTick += 1
            withAnimation(fold) { failed = true }
        }
    }

    private func resetToAutomatic() {
        do {
            try model.resetCategory(for: movement.id)
            selectTick += 1
            withAnimation(fold) {
                failed = false
                expanded = false
            }
        } catch {
            errorTick += 1
            withAnimation(fold) { failed = true }
        }
    }
}

/// Una ficha de la rejilla: símbolo y nombre. La elegida, blanca con símbolo negro y una marca dibujada.
private struct CategoryTile: View {
    let category: SpendingCategory
    let selected: Bool
    let index: Int
    let height: CGFloat
    /// false en tamaños de accesibilidad: la ficha crece con su texto en vez de recortarlo.
    let fixedHeight: Bool
    /// D2: la ficha blanca compartida (una sola, se desliza de la antigua a la nueva).
    let selection: Namespace.ID
    /// Sube solo cuando se elige ESTA ficha: su símbolo bota.
    let bounce: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @State private var shown = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                    // D2: el símbolo de la elegida da un bote al elegirla (con Reducir movimiento, no).
                    .symbolEffect(.bounce, value: bounce)
                Text(category.displayName)
                    .titan(.caption)
                    .lineLimit(fixedHeight ? 2 : nil)
                    .minimumScaleFactor(fixedHeight ? 0.8 : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: !fixedHeight)
            }
            .foregroundStyle(selected ? Theme.onTileSelected : Theme.label)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: fixedHeight ? height : nil)
            .background {
                if selected {
                    shape.fill(Theme.tileSelected).matchedGeometryEffect(id: "selected-category", in: selection)
                } else {
                    shape.fill(Theme.chipFill)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(Theme.onTileSelected)
                        DrawnCheck(lineWidth: 1.8, color: Theme.tileSelected).frame(width: 9, height: 9)
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
    @State private var failed = false

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
                .padding(.bottom, failed ? 4 : 10)
            if failed {
                SaveErrorText()
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
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
            failed = false
        } catch {
            errorTick += 1
            withAnimation(Theme.Motion.quick) { failed = true }
        }
    }
}

/// Mensaje visible cuando no se pudo guardar (además de la háptica de error).
private struct SaveErrorText: View {
    var body: some View {
        Text("No se pudo guardar. Inténtalo de nuevo.")
            .titan(.meta)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("detail-save-error")
    }
}
