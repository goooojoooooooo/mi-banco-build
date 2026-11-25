import MiBancoCore
import SwiftUI

/// «Importar» que se transforma: cápsula blanca con su título → círculo con la rueda de carga mientras se guarda → ✓ que
/// salta de 0,4 a 1 cuando el extracto está guardado. Es el mismo gesto que el `MorphingButton` del kit, hecho aquí
/// porque el del kit parte su título en varias líneas mientras se encoge (se ve en la cámara lenta) y no avisa de cuándo
/// ha terminado. El título va en una sola línea y no se encoge: se funde. Con Reducir movimiento la cápsula no cambia
/// de forma: título, rueda y ✓ se funden. Un solo elemento para VoiceOver, que dice lo que está pasando.
private struct ImportMorphButton: View {
    enum Phase { case idle, working, done }
    let phase: Phase
    let action: () -> Void

    @Environment(\.motion) private var motion

    private var collapsed: Bool { phase != .idle && !motion.reduce }

    var body: some View {
        Button(action: action) {
            // La cápsula se encoge hasta ser un círculo, centrada. El título, la rueda y el ✓ van en una capa aparte,
            // centrada en el ancho entero de la fila (que no cambia): así no se mueven de sitio mientras la cápsula se
            // encoge. El título es negro: lo que sobresale de la cápsula, sobre el fondo negro, no se ve.
            Capsule()
                .fill(Theme.tileSelected)
                .frame(maxWidth: collapsed ? 52 : .infinity, minHeight: 52, maxHeight: 52)
                .frame(maxWidth: .infinity)
                .overlay {
                    ZStack {
                        Text("Importar")
                            .titan(.option)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.onTileSelected)
                            .lineLimit(1)
                            .fixedSize()
                            .opacity(phase == .idle ? 1 : 0)
                            // El título se va en 0,1 s y solo entonces entra la rueda: nunca uno debajo de la otra (m-6).
                            .animation(.easeOut(duration: motion.seconds(0.10)), value: phase)
                        if phase == .working {
                            ProgressView()
                                .tint(.black)
                                .transition(.opacity.animation(.easeOut(duration: motion.seconds(0.15))
                                    .delay(motion.seconds(0.10))))
                        }
                        if phase == .done {
                            DrawnCheck(lineWidth: 2.8, color: .black)
                                .frame(width: 22, height: 22)
                                .transition(motion.reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(phase != .idle)
        // Sin rebote: con el muelle que se pasa, la cápsula se quedaba un instante más estrecha que el círculo.
        .animation(motion.calmAnimation(.snap), value: phase)
        .accessibilityLabel(phase == .done ? "Importado" : (phase == .working ? "Importando" : "Importar"))
        .accessibilityIdentifier("import-confirm")
    }
}

/// Vista previa e importación de un extracto CSV (Plan 2, tarea 12).
/// Muestra el resumen de movimientos nuevos / ya existentes / ignorados, el periodo, el último saldo (tapado en modo
/// privado) y las operaciones de inversión separadas del gasto (R12).
///
/// Pasos con porcentaje (fase B, S10): Leer › Revisar › Importar. Leer y revisar el fichero es casi instantáneo, así que
/// cada paso se enseña al menos 0,35 s (del kit); después aparece la vista previa (sus piezas entran una tras otra y el
/// recuento cuenta) con el porcentaje parado en 67: el tercer paso espera a que el dueño toque «Importar» (el botón se
/// transforma: rueda y ✓). El 100 llega
/// solo cuando el extracto se ha guardado de verdad; si falla, el porcentaje se queda donde estaba.
struct ImportStatementView: View {
    let model: LedgerModel
    var portfolio: PortfolioModel? = nil
    let bank: BankID
    let preview: ImportPreview
    var onFinished: () -> Void = {}

    @Environment(\.motion) private var motion
    @Environment(AppPreferences.self) private var preferences

    @State private var applied = false
    @State private var errorText: String?
    @State private var countRevealed = false
    @State private var successTick = 0
    @State private var errorTick = 0
    /// El porcentaje de los tres pasos.
    @State private var steps = StepPercent()
    /// Cuándo empezó el paso en curso (lejos en el futuro = el paso espera al dueño y el porcentaje no cuenta).
    @State private var stepStarted = Date()
    /// La vista previa ya se puede ver (Leer y Revisar han terminado).
    @State private var reviewed = false
    /// Se está guardando el extracto (tercer paso en marcha).
    @State private var importing = false
    @State private var started = false

    private static let stepTitles = ["Leer", "Revisar", "Importar"]

    /// Lo mínimo que se ve cada paso: 0,35 s del kit (sigue la intensidad y la cámara lenta).
    private var stepSeconds: Double {
        #if DEBUG
        if DemoMode.slowsImportSteps { return 8 }
        #endif
        return motion.seconds(0.35)
    }

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
                StepperProgress(steps: Self.stepTitles, current: steps.step, finished: applied, percent: steps,
                                since: stepStarted, spins: !reviewed || importing, identifier: "import-steps")
                    // Los títulos de los extremos sobresalen de su nodo.
                    .padding(.horizontal, 30)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        BankLogo(bank: bank, size: 32)
                        Text(bank.displayName)
                            .titan(.option)
                            .foregroundStyle(Theme.label2)
                    }
                    .risesIn(when: reviewed, after: 0.05)

                    let displayedReport = (countRevealed || motion.reduce)
                        ? preview.report
                        : ReconcileReport()
                    Text(importSummary(displayedReport))
                        .titan(.cardTitle)
                        .foregroundStyle(Theme.label)
                        .contentTransition(.numericText())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(importSummary(preview.report))
                        .accessibilityIdentifier("import-summary")
                        .risesIn(when: reviewed, after: 0.09)

                    if let range = dateRangeText {
                        Text(range)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .accessibilityIdentifier("import-date-range")
                            .risesIn(when: reviewed, after: 0.13)
                    }

                    if let latest = preview.statement.latestBalance {
                        let formattedBalance = formatEUR(latest.cents).replacingOccurrences(of: "-", with: "\u{2212}")
                        HStack(spacing: 6) {
                            Text("Saldo del extracto:")
                                .titan(.subtitle)
                                .foregroundStyle(Theme.label2)
                            // Con el ojo cerrado, la máscara: ninguna cifra montada.
                            Text(hidden ? maskedEUR(latest.cents, sign: false) : formattedBalance)
                                .titan(.subtitle)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.label)
                                .contentTransition(.identity)
                                .privacySensitive()
                                // Las pruebas de toque ven este texto aunque su fila ignore a sus hijos: su etiqueta
                                // tampoco lleva importe (ni el símbolo del euro) con el ojo cerrado.
                                .accessibilityLabel(hidden ? "importe oculto" : formattedBalance)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Saldo del extracto: \(spokenAmount(latest.cents, hidden: hidden))")
                        .accessibilityIdentifier("import-latest-balance")
                        .risesIn(when: reviewed, after: 0.17)
                    }
                    if !hasNewOrLinked && canApply {
                        Text(statementZeroNewNote(preview.report))
                            .titan(.meta)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .risesIn(when: reviewed, after: 0.21)
                    }
                    if preview.tradeRepublicInvestmentsFailed {
                        Text("No pude leer las operaciones de inversión de este fichero; los movimientos sí.")
                            .titan(.meta)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .risesIn(when: reviewed, after: 0.25)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .risesIn(when: reviewed, rise: 20)

                if let errorText {
                    Text(errorText)
                        .titan(.meta)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    if canApply {
                        // Se transforma: cápsula «Importar» → círculo con rueda → ✓.
                        ImportMorphButton(phase: applied ? .done : (importing ? .working : .idle)) {
                            Task { _ = await apply() }
                        }
                    } else {
                        // Un botón de verdad, deshabilitado: VoiceOver dice «atenuado» (menor m-7).
                        Button {} label: {
                            Text("Nada nuevo que importar")
                                .titan(.option)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.label3)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Theme.raised, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                        .accessibilityIdentifier("import-confirm")
                    }

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
                    .disabled(applied || importing)
                    .accessibilityIdentifier("import-cancel")
                }
                .risesIn(when: reviewed, after: 0.24, rise: 24)
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
        .task {
            guard !started else { return }
            started = true
            await runReadingSteps()
        }
        .sensoryFeedback(Haptics.success, trigger: successTick)
        .sensoryFeedback(Haptics.error, trigger: errorTick)
    }

    /// Leer y Revisar: el fichero ya está leído y cotejado cuando se abre esta pantalla, así que cada paso se enseña su
    /// mínimo y la vista previa aparece al terminar el segundo. El tercero (Importar) queda en curso, esperando el toque.
    private func runReadingSteps() async {
        stepStarted = Date()
        try? await Task.sleep(for: .seconds(stepSeconds))
        steps.enter(step: 1)
        stepStarted = Date()
        try? await Task.sleep(for: .seconds(stepSeconds))
        steps.enter(step: 2)
        // Parado en 67 hasta que se toque «Importar»: nada cuenta mientras se espera al dueño.
        stepStarted = .distantFuture
        reviewed = true
        withAnimation(motion.reduce ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: motion.seconds(1.0))) {
            countRevealed = true
        }
    }

    /// Guarda el extracto (tercer paso). Devuelve si se guardó: el botón enseña su ✓ o vuelve a «Importar» con el error.
    private func apply() async -> Bool {
        guard canApply, reviewed, !applied, !importing else { return false }
        // Un intento nuevo tras un fallo: el tercer paso vuelve a empezar en su suelo.
        if !steps.isRunning {
            var fresh = StepPercent()
            fresh.enter(step: 2)
            steps = fresh
        }
        importing = true
        stepStarted = Date()
        errorText = nil
        let began = Date()
        let ok = save()
        // El paso se ve al menos su mínimo, aunque guardar sea inmediato.
        let rest = stepSeconds - Date().timeIntervalSince(began)
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        let stretch = max(0.05, motion.level.timeScale * motion.timeMultiplier)
        // Justo la cifra que se DIBUJABA (con Reducir movimiento, el suelo del paso: menor m-2).
        let drawn = steps.drawn(elapsed: Date().timeIntervalSince(began) / stretch, reduce: motion.reduce)
        guard ok else {
            // No se guardó: el porcentaje se queda congelado donde estaba.
            importing = false
            steps.fail(shown: drawn)
            errorTick += 1
            return false
        }
        // Guardado de verdad: el porcentaje corre de lo que se veía a 100 (0,25 s, la rueda sigue en el botón) y, justo
        // cuando llega a 100, en la misma transacción el tercer nodo se rellena con su ✓ y el botón pasa a su ✓: los tres
        // a la vez (menor m-5 del lote 2 y m-13 del lote 3; antes el ✓ llegaba con 99).
        steps.succeed(shown: drawn)
        stepStarted = Date()
        try? await Task.sleep(for: .seconds(motion.reduce ? 0 : motion.seconds(StepPercent.finishSeconds)))
        withAnimation(motion.calmAnimation(.row)) {
            importing = false
            applied = true
        }
        successTick += 1
        let linger = motion.seconds(0.6)
        Task {
            // El ✓ del botón se ve un momento antes de volver a la pantalla del banco.
            try? await Task.sleep(for: .seconds(linger))
            onFinished()
        }
        return true
    }

    /// Lo de siempre: guarda el extracto y, en Trade Republic, sus operaciones de cartera. Falso si algo no se pudo.
    private func save() -> Bool {
        do {
            _ = try model.applyImport(preview)
        } catch {
            errorText = "No se pudo guardar el extracto. Inténtalo de nuevo."
            return false
        }
        if bank == .tr, !preview.tradeRepublicRows.isEmpty, let portfolio {
            do {
                try portfolio.mergeRows(preview.tradeRepublicRows)
                if preferences.pricesEnabled {
                    Task { await portfolio.refreshPrices(force: true) }
                }
            } catch {
                errorText = "Extracto guardado. La cartera no se pudo actualizar: impórtalo otra vez desde Ajustes › Inversiones."
                return false
            }
        }
        return true
    }
}
