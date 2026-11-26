import SwiftUI
import MiBancoCore

/// Grupo "Inversiones" de Ajustes (Plan 4b, tarea 6): importación del extracto de Trade Republic,
/// pregunta inicial en línea sobre precios y control del permiso para consultar Yahoo Finance.
struct InvestmentsSection: View {
    let portfolio: PortfolioModel
    let importTradeRepublic: () -> Void

    static let scrollID = "inversiones"

    private static let pricesExplanation =
        "Para saber cuánto valen tus inversiones, \(AppIdentity.displayName) pregunta a Yahoo Finance el precio de cada valor usando solo su código. No envía cuántas acciones tienes, ni importes, ni tu nombre. Si lo apagas, puedes poner los precios a mano."

    private static let exportHint =
        "Cómo exportar: en Trade Republic, Perfil › Extractos › Exportar transacciones › Guardar en Archivos. Si ya importaste el extracto en Bancos, tus inversiones ya están."

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var successTick = 0
    @State private var errorTick = 0

    var body: some View {
        Section {
            Button(action: importTradeRepublic) {
                OptionLabel(title: "Importar de Trade Republic", detail: statusText, systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("investments-import")
            .id(Self.scrollID)
            .listRowBackground(Theme.grouped)
            .listRowSeparatorTint(Theme.separator)

            if let imported = portfolio.lastImport {
                Text(formatPortfolioImportSummary(imported))
                    .titan(.meta)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
            }

            if let error = portfolio.lastImportError {
                Text(error)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
            }

            if portfolio.portfolio.droppedEntries > 0 {
                Text("Algunas entradas de tus inversiones no se pudieron leer. Vuelve a importar tu extracto de Trade Republic.")
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
            }

            if portfolio.hasPositions && !preferences.pricesAsked {
                firstTimePricesAsk
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
            }

            Toggle(isOn: pricesBinding) {
                OptionLabel(
                    title: "Precios de tus inversiones",
                    detail: portfolio.isRefreshingPrices ? "Actualizando precios…" : "Solo envía el código de cada valor a Yahoo Finance, nunca cuánto tienes.",
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            }
            .toggleStyle(TitanToggleStyle())
            .accessibilityLabel("Precios de tus inversiones")
            .accessibilityIdentifier("investments-prices-toggle")
            .listRowBackground(Theme.grouped)
            .listRowSeparatorTint(Theme.separator)
        } header: {
            SettingsHeader("Inversiones")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Space.small) {
                SettingsFooter(Self.pricesExplanation)
                SettingsFooter(Self.exportHint)
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: preferences.pricesAsked)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: portfolio.importFeedbackToken)
        .onChange(of: portfolio.importFeedbackToken) { _, _ in
            if portfolio.lastImport != nil {
                successTick += 1
            } else if portfolio.lastImportError != nil {
                errorTick += 1
            }
        }
        .sensoryFeedback(.success, trigger: successTick)
        .sensoryFeedback(.error, trigger: errorTick)
        .onDisappear { portfolio.clearImportFeedback() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { portfolio.clearImportFeedback() }
        }
    }

    private var statusText: String {
        guard let summary = portfolio.summary else {
            if let imported = portfolio.portfolio.lastImport {
                return "Sin posiciones abiertas · importado el \(DateText.madridDay(imported))"
            }
            return "Aún no has importado nada"
        }
        let count = summary.positions.count
        let base = count == 1 ? "1 posición" : "\(count) posiciones"
        if let imported = portfolio.portfolio.lastImport {
            return "\(base) · importado el \(DateText.madridDay(imported))"
        }
        return base
    }

    private var firstTimePricesAsk: some View {
        let buttonsLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(spacing: Theme.Space.small))
        return VStack(alignment: .leading, spacing: Theme.Space.row) {
            Text("¿Buscar los precios cada día?")
                .titan(.option)
                .foregroundStyle(Theme.label)
                .accessibilityAddTraits(.isHeader)
            Text(Self.pricesExplanation)
                .titan(.meta)
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
            buttonsLayout {
                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                        preferences.pricesAsked = true
                        preferences.pricesEnabled = true
                    }
                    Task { await portfolio.refreshPrices(force: true) }
                } label: {
                    Text("Sí, buscar precios")
                        .titan(.subtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)

                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                        preferences.pricesAsked = true
                        preferences.pricesEnabled = false
                    }
                } label: {
                    Text("Los pondré yo")
                        .titan(.subtitle)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 6)
    }

    private var pricesBinding: Binding<Bool> {
        Binding(
            get: { preferences.pricesEnabled },
            set: { enabled in
                preferences.pricesAsked = true
                preferences.pricesEnabled = enabled
                if enabled {
                    Task { await portfolio.refreshPrices(force: true) }
                }
            }
        )
    }
}
