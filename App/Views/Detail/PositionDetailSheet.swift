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
                    changeDay: portfolio.summary?.changeDay,
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
    let changeDay: Date?
    let transactions: [InvestmentTransaction]
    let onClose: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 60

    @State private var editingPrice = false
    @State private var priceText = ""
    @State private var priceError: String?
    @State private var priceSaved = false
    @State private var saveTick = 0
    @State private var errorTick = 0
    @FocusState private var priceFocused: Bool

    private static let tradeRepublicURL = URL(string: "traderepublic://")

    private var canOpenTradeRepublic: Bool {
        guard let url = Self.tradeRepublicURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private var hasManualPrice: Bool {
        if case .manual = value.origin { return true }
        return false
    }

    var body: some View {
        let hidden = preferences.privateMode
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    PositionMonogramTile(name: value.position.name, size: tileSize)
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
                        CountingAmount(cents: cents, style: .plain(sign: false))
                            .font(.system(size: amountSize, weight: .semibold))
                            .tracking(-amountSize * 0.03)
                            .monospacedDigit()
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .privateAmount(radius: 14)
                            .padding(.top, 10)
                            .staggeredEntrance(6, rise: 10)
                            .accessibilityLabel(spokenAmount(cents, hidden: hidden))
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
                        spoken: hidden ? "Coste medio: importe oculto" : "Coste medio: \(averageCostText)",
                        divided: true,
                        isSensitive: averageCostAvailable
                    )
                    metricRow(
                        key: "Precio",
                        text: priceSummaryText,
                        spoken: hidden ? "Precio: importe oculto" : "Precio: \(priceSummaryText)",
                        divided: true,
                        isSensitive: value.priceEUR != nil
                    )
                    if let todayCents = value.todayChangeCents {
                        let key = isChangeToday ? "Hoy" : "Última sesión"
                        let text = signedSummary(cents: todayCents, tenths: PositionFormatting.todayTenths(for: value))
                        metricRow(
                            key: key,
                            text: text,
                            spoken: hidden ? "\(key): importe oculto" : "\(key): \(spokenSigned(todayCents))",
                            tint: todayCents > 0 ? Theme.income : Theme.label,
                            divided: true
                        )
                    }
                    if let gainCents = value.gainCents {
                        let text = signedSummary(cents: gainCents, tenths: value.gainTenths)
                        metricRow(
                            key: "Desde la compra",
                            text: text,
                            spoken: hidden ? "Desde la compra: importe oculto" : "Desde la compra: \(spokenSigned(gainCents))",
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
                    if hasManualPrice {
                        PositionSheetAction(
                            title: "Quitar precio a mano",
                            systemImage: "arrow.uturn.backward",
                            divided: true,
                            action: clearManualPrice
                        )
                    }
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
    }

    private var isChangeToday: Bool {
        guard let changeDay else { return true }
        return madridCalendar.isDate(changeDay, inSameDayAs: Date())
    }

    private var averageCostAvailable: Bool {
        value.position.costCents > 0 && !value.position.costIncomplete && value.position.shares > 0
    }

    private var averageCostText: String {
        guard averageCostAvailable else { return "Sin coste completo" }
        let avg = Decimal(value.position.costCents) / (value.position.shares * 100)
        return formatUnitPriceEUR(avg)
    }

    private var priceSummaryText: String {
        guard let price = value.priceEUR else { return "Sin precio" }
        let formatted = formatUnitPriceEUR(price)
        switch value.origin {
        case .market(let date):
            let when = madridCalendar.isDate(date, inSameDayAs: Date()) ? DateText.time(date) : DateText.day(date)
            return "\(formatted) · mercado, \(when)"
        case .manual(let date):
            return "\(formatted) · a mano, \(DateText.day(date))"
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

    private func spokenSigned(_ cents: Int) -> String {
        let prefix = cents > 0 ? "más " : (cents < 0 ? "menos " : "")
        return prefix + spokenAmount(abs(cents), hidden: false)
    }

    private func metricRow(
        key: String,
        text: String,
        spoken: String,
        tint: Color = Theme.label,
        divided: Bool,
        isSensitive: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .foregroundStyle(Theme.label2)
            Spacer(minLength: 8)
            Group {
                if isSensitive {
                    Text(text)
                        .fontWeight(.medium)
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.trailing)
                        .privateAmount()
                } else {
                    Text(text)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.label3)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .titan(.option)
        .fontWeight(.regular)
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
        } else {
            kind = op.shares >= 0 ? "Compra" : "Venta"
        }
        let shares = "\(formatShares(op.shares.magnitude)) acc."
        let day = DateText.day(op.date)
        let amount = op.cashCents != 0 ? formatEUR(abs(op.cashCents)) : nil
        let spoken = hidden
            ? "\(kind) el \(day), importe oculto"
            : "\(kind), \(shares), \(day)" + (op.cashCents != 0 ? ", \(spokenAmount(abs(op.cashCents), hidden: false))" : "")

        return HStack(spacing: 6) {
            Text("\(kind) ·")
                .foregroundStyle(Theme.label)
            Text(shares)
                .foregroundStyle(Theme.label2)
                .privateAmount()
            Text("· \(day)")
                .foregroundStyle(Theme.label2)
            Spacer(minLength: 4)
            if let amount {
                Text(amount)
                    .foregroundStyle(Theme.label)
                    .privateAmount()
            }
        }
        .titan(.subtitle)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
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
                    TextField("Precio en € (vacío para quitar)", text: $priceText)
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .focused($priceFocused)
                        .onSubmit(commitManualPrice)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.fieldFill, in: .rect(cornerRadius: Theme.Radius.field))
                        .privateField(editing: priceFocused)
                        .accessibilityLabel("Precio a mano en euros")
                        .accessibilityIdentifier("manualPriceField")

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
        if let current = value.priceEUR {
            priceText = formatUnitPriceEUR(current).replacingOccurrences(of: "\u{00A0}€", with: "")
        } else {
            priceText = ""
        }
        priceError = nil
        editingPrice = true
        priceFocused = true
    }

    private func commitManualPrice() {
        priceFocused = false
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "€", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearManualPrice()
            return
        }
        guard let parsed = parseDecimal(trimmed), parsed > 0, parsed <= 1_000_000_000 else {
            priceError = "Escribe un precio válido, por ejemplo 110,50."
            errorTick += 1
            return
        }
        do {
            try portfolio.setManualPrice(parsed, for: value.position.instrument)
            priceError = nil
            priceSaved = true
            saveTick += 1
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
                    priceSaved = false
                    editingPrice = false
                }
            }
        } catch {
            priceError = "No se pudo guardar el precio. Inténtalo de nuevo."
            errorTick += 1
        }
    }

    private func clearManualPrice() {
        priceFocused = false
        do {
            try portfolio.setManualPrice(nil, for: value.position.instrument)
            priceError = nil
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
