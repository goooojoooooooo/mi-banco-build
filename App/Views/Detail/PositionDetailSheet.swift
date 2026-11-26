import SwiftUI
import UIKit
import MiBancoCore

/// Hoja de detalle de una posición de inversión (Plan 4b, tarea 7).
/// Vive dentro de `RootSheet` (única hoja de la app) y se cierra al bloquear o salir de primer plano.
struct PositionDetailSheet: View {
    let portfolio: PortfolioModel
    let instrument: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var entrance = Entrance()

    private var demoKeepsVisible: Bool {
        #if DEBUG
        return DemoMode.isActive && DemoMode.opensPosition
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if let value = portfolio.positionValue(for: instrument) {
                PositionDetailContent(
                    portfolio: portfolio,
                    value: value,
                    transactions: portfolio.recentTransactions(for: instrument, limit: 5),
                    onClose: { dismiss() }
                )
            } else {
                Color.clear
            }
        }
        .environment(\.entrance, entrance)
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

private struct PositionDetailContent: View {
    let portfolio: PortfolioModel
    let value: PositionValue
    let transactions: [InvestmentTransaction]
    let onClose: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 60

    @State private var editingPrice = false
    @State private var priceText = ""
    @State private var initialPriceText = ""
    @State private var priceError: String?
    @State private var priceSaved = false
    @State private var saveCloseTask: Task<Void, Never>?
    @State private var saveTick = 0
    @State private var errorTick = 0
    @FocusState private var priceFocused: Bool

    private static let tradeRepublicURL = URL(string: "traderepublic://")

    private var canOpenTradeRepublic: Bool {
        guard let url = Self.tradeRepublicURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private var positionChangeDay: Date? {
        guard case .market(let at) = value.origin else { return nil }
        return DateText.madridCalendar.startOfDay(for: at)
    }

    var body: some View {
        let hidden = preferences.privateMode
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    PositionMonogramTile(name: value.position.name, size: tileSize, circular: true)
                    Text(value.position.name)
                        .titan(.sheetTitle)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .staggeredEntrance(5, rise: 8)
                    Text(value.position.instrument)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label3)
                        .padding(.top, 3)
                        .staggeredEntrance(5, rise: 8)

                    if let cents = value.valueCents {
                        // Rueda; con el ojo cerrado `RollingAmount` dibuja la máscara y VoiceOver dice «importe oculto».
                        RollingAmount(cents: cents, style: .plain(sign: false))
                            .font(.system(size: amountSize, weight: .semibold))
                            .tracking(-amountSize * 0.03)
                            .foregroundStyle(Theme.label)
                            .padding(.top, 10)
                            .staggeredEntrance(6, rise: 10)
                    } else {
                        Text("Sin precio")
                            .titan(.sheetTitle)
                            .foregroundStyle(Theme.label2)
                            .padding(.top, 14)
                            .staggeredEntrance(6, rise: 10)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                DetailGroup {
                    metricRow(
                        key: "Acciones",
                        text: formatShares(value.position.shares),
                        spoken: hidden ? "Acciones: importe oculto" : "Acciones: \(formatShares(value.position.shares))",
                        divided: false
                    )
                    metricRow(
                        key: "Coste medio",
                        text: averageCostText,
                        spoken: !averageCostAvailable
                            ? "Coste medio: Sin coste completo"
                            : (hidden ? "Coste medio: importe oculto" : "Coste medio: \(averageCostText)"),
                        divided: true,
                        isSensitive: averageCostAvailable
                    )
                    metricRow(
                        key: "Precio",
                        text: priceSummaryText,
                        spoken: value.priceEUR == nil
                            ? "Precio: Sin precio"
                            : (hidden ? "Precio: importe oculto" : "Precio: \(priceSummaryText)"),
                        tint: isPriceStale ? Theme.warning : Theme.label,
                        divided: true,
                        isSensitive: value.priceEUR != nil
                    )
                    if let todayCents = value.todayChangeCents, let changeDay = positionChangeDay {
                        let key = DateText.madridCalendar.isDate(changeDay, inSameDayAs: Date())
                            ? "Hoy"
                            : "Última sesión (\(DateText.madridWeekday(changeDay)))"
                        let tenths = PositionFormatting.todayTenths(for: value)
                        let text = signedSummary(cents: todayCents, tenths: tenths)
                        metricRow(
                            key: key,
                            text: text,
                            spoken: hidden ? "\(key): importe oculto" : "\(key): \(spokenSigned(todayCents, tenths: tenths))",
                            tint: todayCents > 0 ? Theme.income : Theme.label,
                            divided: true
                        )
                    }
                    if let gainCents = value.gainCents {
                        let text = signedSummary(cents: gainCents, tenths: value.gainTenths)
                        metricRow(
                            key: "Desde la compra",
                            text: text,
                            spoken: hidden
                                ? "Desde la compra: importe oculto"
                                : "Desde la compra: \(spokenSigned(gainCents, tenths: value.gainTenths))",
                            tint: gainCents > 0 ? Theme.income : Theme.label,
                            divided: true
                        )
                    }
                }
                .staggeredEntrance(7)

                if !transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Últimas operaciones")
                            .titan(.header)
                            .foregroundStyle(Theme.label3)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                        DetailGroup {
                            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, op in
                                operationRow(op, divided: index > 0, hidden: hidden)
                            }
                        }
                    }
                    .staggeredEntrance(8)
                }

                if editingPrice {
                    manualPriceEditor
                        .staggeredEntrance(9)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                DetailGroup {
                    PositionSheetAction(
                        title: "Poner precio a mano",
                        systemImage: "pencil",
                        divided: false,
                        action: startEditingPrice
                    )
                    if canOpenTradeRepublic, let url = Self.tradeRepublicURL {
                        PositionSheetAction(
                            title: "Abrir Trade Republic",
                            systemImage: "arrow.up.forward.app",
                            divided: true,
                            action: { openURL(url) }
                        )
                    }
                }
                .staggeredEntrance(10)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 32)
            .animation(reduceMotion ? nil : Theme.Motion.morph, value: editingPrice)
            .animation(reduceMotion ? nil : Theme.Motion.quick, value: priceError)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("position-scroll")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Cerrar")
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
        }
        .sensoryFeedback(Haptics.success, trigger: saveTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { priceFocused = false }
        }
        // SEC-05: al cerrarse el ojo mientras se edita el precio, soltar el foco en el acto y sin animación.
        .onChange(of: preferences.privateMode) { _, on in
            guard on, priceFocused else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { priceFocused = false }
        }
        #if DEBUG
        .onChange(of: priceFocused, initial: true) { _, focused in
            guard DemoMode.isActive, focused, !preferences.privateMode,
                  let seconds = DemoMode.closeEyeWhenFocusedSeconds else { return }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, priceFocused else { return }
                preferences.privateMode = true
            }
        }
        #endif
        .onDisappear {
            saveCloseTask?.cancel()
            saveCloseTask = nil
        }
    }

    private var averageCostAvailable: Bool {
        value.position.costCents > 0 && !value.position.costIncomplete && value.position.shares > 0
    }

    private var averageCostText: String {
        guard averageCostAvailable else { return "Sin coste completo" }
        let avg = Decimal(value.position.costCents) / (value.position.shares * 100)
        return formatUnitPriceEUR(avg)
    }

    private var isPriceStale: Bool {
        guard value.priceEUR != nil else { return false }
        let timestamp: Date?
        switch value.origin {
        case .market(let date): timestamp = date
        case .manual(let date): timestamp = date
        case .none: timestamp = nil
        }
        guard let timestamp else { return false }
        return Date().timeIntervalSince(timestamp) > 4 * 86_400
    }

    private var priceSummaryText: String {
        guard let price = value.priceEUR else { return "Sin precio" }
        let formatted = formatUnitPriceEUR(price)
        let staleSuffix = isPriceStale ? " · antiguo" : ""
        switch value.origin {
        case .market(let date):
            let when = DateText.madridCalendar.isDate(date, inSameDayAs: Date())
                ? DateText.madridTime(date)
                : DateText.madridDay(date)
            return "\(formatted) · mercado, \(when)\(staleSuffix)"
        case .manual(let date):
            return "\(formatted) · a mano, \(DateText.madridDay(date))\(staleSuffix)"
        case .none:
            return formatted
        }
    }

    private func signedSummary(cents: Int, tenths: Int?) -> String {
        let eur = formatSignedEUR(cents).replacingOccurrences(of: "-", with: "\u{2212}")
        guard let tenths else { return eur }
        let pct = formatPercentTenths(tenths, signed: true).replacingOccurrences(of: "-", with: "\u{2212}")
        return "\(eur) (\(pct))"
    }

    private func spokenSigned(_ cents: Int, tenths: Int?) -> String {
        let prefix = cents > 0 ? "más " : (cents < 0 ? "menos " : "")
        var text = prefix + spokenAmount(abs(cents), hidden: false)
        if let tenths {
            let pct = formatPercentTenths(tenths, signed: true)
                .replacingOccurrences(of: "\u{00A0}%", with: " por ciento")
                .replacingOccurrences(of: "+", with: "más ")
                .replacingOccurrences(of: "-", with: "menos ")
            text += ", \(pct)"
        }
        return text
    }

    private func metricRow(
        key: String,
        text: String,
        spoken: String,
        tint: Color = Theme.label,
        divided: Bool,
        isSensitive: Bool = true
    ) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(key)
                .foregroundStyle(Theme.label2)
            if !stacked { Spacer(minLength: 8) }
            Group {
                if isSensitive {
                    // Con el ojo cerrado no se monta el dato: se dibuja su máscara.
                    MaskedText(text, hidden: preferences.privateMode)
                        .fontWeight(.medium)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                } else {
                    Text(text)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.label3)
                        .multilineTextAlignment(stacked ? .leading : .trailing)
                }
            }
        }
        .titan(.option)
        .fontWeight(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 50)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func operationRow(_ op: InvestmentTransaction, divided: Bool, hidden: Bool) -> some View {
        let kind: String
        if op.acquired {
            kind = "Recibido"
        } else if op.disposed {
            kind = "Salida"
        } else {
            kind = op.shares >= 0 ? "Compra" : "Venta"
        }
        let shares = "\(formatShares(op.shares.magnitude)) acc."
        let day = DateText.madridDay(op.date)
        let amount = op.cashCents != 0 ? formatEUR(abs(op.cashCents)) : nil
        let spoken = hidden
            ? "\(kind) el \(day), importe oculto"
            : "\(kind), \(shares), \(day)" + (op.cashCents != 0 ? ", \(spokenAmount(abs(op.cashCents), hidden: false))" : "")
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 6))

        return layout {
            HStack(spacing: 6) {
                Text("\(kind) ·")
                    .foregroundStyle(Theme.label)
                MaskedText(hidden ? "" : shares, unit: hidden ? " acc." : "", spoken: shares, hidden: hidden)
                    .foregroundStyle(Theme.label2)
                Text("· \(day)")
                    .foregroundStyle(Theme.label2)
            }
            if !stacked { Spacer(minLength: 4) }
            if amount != nil {
                MaskedText(cents: abs(op.cashCents), hidden: hidden)
                    .foregroundStyle(Theme.label)
            }
        }
        .titan(.subtitle)
        .lineLimit(stacked ? nil : 1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, stacked ? 10 : 6)
        .frame(minHeight: 46)
        .overlay(alignment: .top) {
            if divided {
                Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var manualPriceEditor: some View {
        DetailGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    // SEC-05: componente único enmascarado; con el ojo cerrado nunca monta ni desenfoca la cifra real.
                    MaskedAmountTextField(
                        placeholder: "Precio en € (vacío para quitar)",
                        text: $priceText,
                        hidden: preferences.privateMode,
                        editing: priceFocused
                    )
                        .titan(.option)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .focused($priceFocused)
                        .onSubmit(commitManualPrice)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                        .accessibilityLabel("Precio a mano en euros")
                        .accessibilityIdentifier("manualPriceField")
                        // El teclado decimal no tiene tecla de volver: «Hecho» solo quita el foco, no guarda (U75).
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                // A la derecha con un marco flexible, no con un `Spacer()`. (Se probó por si el `Spacer`
                                // de la barra del teclado causaba el aviso de ejecución «Invalid frame dimension» de
                                // las pruebas de inversiones: NO era eso, el aviso sigue saliendo con este cambio.)
                                Button("Hecho") { priceFocused = false }
                                    .accessibilityIdentifier("manualPriceKeyboardDone")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }

                    if priceSaved {
                        DrawnCheck(lineWidth: 2, color: Theme.label)
                            .frame(width: 18, height: 18)
                            .transition(.opacity)
                            .accessibilityLabel("Guardado")
                    }

                    Button(action: commitManualPrice) {
                        Text("Guardar")
                            .titan(.subtitle)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.onTileSelected)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Theme.tileSelected, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }

                if let priceError {
                    Text(priceError)
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    private func startEditingPrice() {
        saveCloseTask?.cancel()
        saveCloseTask = nil
        priceSaved = false
        if let current = value.priceEUR {
            priceText = formatUnitPriceEUR(current)
                .replacingOccurrences(of: "\u{00A0}€", with: "")
                .replacingOccurrences(of: ".", with: "")
        } else {
            priceText = ""
        }
        initialPriceText = priceText
        priceError = nil
        editingPrice = true
        priceFocused = !preferences.privateMode
    }

    private func commitManualPrice() {
        saveCloseTask?.cancel()
        saveCloseTask = nil
        priceFocused = false
        // Con el ojo cerrado, salir o guardar sin escribir un precio distinto conserva el valor existente.
        if preferences.privateMode, priceText == initialPriceText {
            priceError = nil
            withAnimation(motion.fade) {
                editingPrice = false
            }
            return
        }
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearManualPrice()
            return
        }
        guard let parsed = parseManualPriceES(trimmed), parsed > 0, parsed <= 1_000_000_000 else {
            priceError = "Escribe un precio válido, por ejemplo 110,50."
            errorTick += 1
            return
        }
        do {
            try portfolio.setManualPrice(parsed, for: value.position.instrument)
            priceError = nil
            priceSaved = true
            saveTick += 1
            saveCloseTask = Task {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    priceSaved = false
                    editingPrice = false
                }
                saveCloseTask = nil
            }
        } catch PortfolioImportError.unreadable {
            priceError = "Escribe un precio válido, por ejemplo 110,50."
            errorTick += 1
        } catch {
            priceError = "No se pudo guardar el precio. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func clearManualPrice() {
        saveCloseTask?.cancel()
        saveCloseTask = nil
        priceFocused = false
        do {
            try portfolio.setManualPrice(nil, for: value.position.instrument)
            priceError = nil
            priceSaved = false
            saveTick += 1
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                editingPrice = false
            }
        } catch {
            priceError = "No se pudo quitar el precio. Inténtalo de nuevo."
            errorTick += 1
        }
    }
}

private struct PositionSheetAction: View {
    let title: String
    let systemImage: String
    var divided = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.label2)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .lineLimit(2)
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
