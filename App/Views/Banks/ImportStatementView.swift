import MiBancoCore
import SwiftUI

/// Vista previa e importación de un extracto CSV (Plan 2, tarea 12).
/// Muestra el resumen de movimientos nuevos / ya existentes / ignorados, el periodo, el último saldo (tapado en modo
/// privado) y las operaciones de inversión separadas del gasto (R12).
struct ImportStatementView: View {
    let model: LedgerModel
    var portfolio: PortfolioModel? = nil
    let bank: BankID
    let preview: ImportPreview
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences

    @State private var applied = false
    @State private var errorText: String?
    @State private var countRevealed = false
    @State private var successTick = 0
    @State private var errorTick = 0

    private var hasNewOrLinked: Bool {
        preview.report.added + preview.report.linked > 0
    }

    /// Aunque haya 0 filas nuevas, `importStatement` guarda el periodo de cobertura (R33/R38), el último saldo si es
    /// más reciente y, en Trade Republic, las operaciones de cartera (Plan 4b tarea 6).
    private var canApply: Bool {
        hasNewOrLinked
            || !preview.statement.records.isEmpty
            || preview.statement.latestBalance != nil
            || (bank == .tr && !preview.tradeRepublicRows.isEmpty)
    }

    private var dateRangeText: String? {
        guard let first = preview.statement.firstDate, let last = preview.statement.lastDate else { return nil }
        return statementRangeText(first: first, last: last, now: Date(), calendar: DateText.madridCalendar)
    }

    var body: some View {
        let hidden = preferences.privateMode
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        BankLogo(bank: bank, size: 32)
                        Text(bank.displayName)
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                    }

                    let displayedReport = (countRevealed || reduceMotion)
                        ? preview.report
                        : ReconcileReport()
                    Text(importSummary(displayedReport))
                        .titan(.cardTitle)
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(importSummary(preview.report))
                        .accessibilityIdentifier("import-summary")

                    if let range = dateRangeText {
                        Text(range)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .accessibilityIdentifier("import-date-range")
                    }

                    if let latest = preview.statement.latestBalance {
                        let formattedBalance = formatEUR(latest.cents).replacingOccurrences(of: "-", with: "\u{2212}")
                        HStack(spacing: 6) {
                            Text("Saldo del extracto:")
                                .titan(.subtitle)
                                .foregroundStyle(Theme.label2)
                            Text(formattedBalance)
                                .titan(.subtitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.label)
                                .privateAmount()
                                .accessibilityLabel(hidden ? "importe oculto" : formattedBalance)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Saldo del extracto: \(spokenAmount(latest.cents, hidden: hidden))")
                        .accessibilityIdentifier("import-latest-balance")
                    }
                    if !hasNewOrLinked && canApply {
                        Text(statementZeroNewNote(preview.report))
                        .titan(.meta)
                        .foregroundStyle(Theme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    if preview.tradeRepublicInvestmentsFailed {
                        Text("No pude leer las operaciones de inversión de este fichero; los movimientos sí.")
                            .titan(.meta)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))

                if let errorText {
                    Text(errorText)
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    Button(action: apply) {
                        HStack(spacing: 8) {
                            if applied {
                                DrawnCheck(lineWidth: 2.5, color: Theme.onTileSelected)
                                    .frame(width: 18, height: 18)
                            }
                            Text(canApply ? "Importar" : "Nada nuevo que importar")
                                .titan(.option)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(canApply ? Theme.onTileSelected : Theme.label3)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canApply ? Theme.tileSelected : Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canApply || applied)
                    .accessibilityIdentifier("import-confirm")

                    Button {
                        // U80 (U49.6): `onFinished` quita la vista de la pila (`navigationDestination(item:)`); un `dismiss()`
                        // más sacaba también la pantalla del banco y dejaba en Ajustes.
                        onFinished()
                    } label: {
                        Text("Cancelar")
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.raised, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(applied)
                    .accessibilityIdentifier("import-cancel")
                }
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("import-statement-scroll")
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Importar extracto de \(bank.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !countRevealed else { return }
            withAnimation(reduceMotion ? nil : Theme.Motion.countUp) {
                countRevealed = true
            }
        }
        .sensoryFeedback(Haptics.success, trigger: successTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    private func apply() {
        guard canApply, !applied else { return }
        do {
            _ = try model.applyImport(preview)
        } catch {
            errorText = "No se pudo guardar el extracto. Inténtalo de nuevo."
            errorTick += 1
            return
        }
        if bank == .tr, !preview.tradeRepublicRows.isEmpty, let portfolio {
            do {
                try portfolio.mergeRows(preview.tradeRepublicRows)
                if preferences.pricesEnabled {
                    Task { await portfolio.refreshPrices(force: true) }
                }
            } catch {
                errorText = "Extracto guardado. La cartera no se pudo actualizar: impórtalo otra vez desde Ajustes › Inversiones."
                errorTick += 1
                return
            }
        }
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) {
            applied = true
        }
        successTick += 1
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            onFinished()
        }
    }
}
