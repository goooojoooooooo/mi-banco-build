import SwiftUI
import MiBancoCore

/// Gasto: el mes por categoría. Arriba el selector de mes (flechas o deslizar en horizontal), el total, la comparación con
/// el mes anterior y la previsión; debajo, una fila por categoría. Todo sale de `model.snapshot` (las páginas ya vienen hechas).
struct SpendingView: View {
    let model: LedgerModel
    let accountBook: AccountBookModel
    var isVisible = false
    /// Abre el detalle de un movimiento (la hoja de `RootView`).
    var openDetail: (UUID) -> Void = { _ in }
    var openMoveMoney: (MoveRequest) -> Void = { _ in }
    @Binding var openBudgetsRequest: Bool
    @Binding var budgetPrefillRequest: BudgetPrefillRequest?

    /// El movimiento del kit: intensidad, cámara lenta y Reducir movimiento (el del sistema o el forzado para grabar).
    @Environment(\.motion) private var motion
    /// El mes elegido (su inicio) y hacia dónde se fue, en un solo valor: cambian en la misma transacción.
    /// nil = el mes actual. Si ese mes deja de existir (otra lista de meses), se vuelve al actual.
    @State private var selection = Selection()
    @State private var entrance = Entrance()
    @State private var tick = 0
    @State private var path: [SpendingRoute] = []
    @State private var activeBudgetPrefill: BudgetPrefillRequest?
    /// La hoja única de `RootView` está abierta y tapa Gasto: sus barras no avisan (necesidad del lote 2, ya en el kit).
    @Environment(\.singleSheetOpen) private var singleSheetOpen
    /// El cambio de pestaña que anuncia `RootView`: juega la entrada de Gasto.
    @Environment(\.tabEntrance) private var tabEntrance

    var body: some View {
        let snapshot = model.snapshot
        let months = snapshot.spendingMonths
        let index = selection.month.flatMap { months.firstIndex(of: $0) } ?? (months.count - 1)
        let page = index >= 0 ? months[index] : nil
        let content = page.flatMap { snapshot.spendingPages[$0] }
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let content, let page {
                        MonthSelector(title: content.title, canGoBack: index > 0, canGoForward: index < months.count - 1) { step in
                            move(by: step, months: months, from: index)
                        }
                        .padding(.horizontal, 4)
                        .tabGroupEntrance(0, rise: 8)

                        SpendingTotal(cents: content.month.totalCents, monthName: content.title)
                            .padding(.horizontal, Theme.Space.gutter)
                            .padding(.top, 2)
                            .tabGroupEntrance(1)

                        // Lo que cambia con el mes: se funde y se desliza hacia donde vas; las filas entran escalonadas.
                        VStack(alignment: .leading, spacing: 0) {
                            SpendingSentences(comparison: content.comparison, forecast: content.forecast)
                                .padding(.horizontal, Theme.Space.gutter)
                                .padding(.top, 8)
                                .motionEntrance(2, listIndex: 0)

                            // El gráfico del mes: se dibuja solo al entrar y al cambiar de mes (nada que dibujar sin gasto).
                            if !content.series.isEmpty {
                                MonthChart(series: content.series, title: content.title, previousTitle: content.previousTitle)
                                    .padding(.horizontal, Theme.Space.gutter)
                                    .padding(.top, 14)
                                    .motionEntrance(2, listIndex: 0)
                            }

                            // El presupuesto del mes («412 de 700 €  59 %»), solo en el mes en curso.
                            if index == months.count - 1, let budget = snapshot.budgets.first(where: { $0.scope == .month }) {
                                BudgetBar(status: budget, name: "Presupuesto del mes")
                                    .padding(.horizontal, Theme.Space.gutter)
                                    .padding(.top, 14)
                                    .accessibilityIdentifier("gasto.presupuestoMes")
                                    .motionEntrance(2, listIndex: 0)
                            }

                            Text("Por categoría")
                                .titan(.header)
                                .foregroundStyle(Theme.label3)
                                .padding(.horizontal, Theme.Space.gutter)
                                .padding(.top, Theme.Space.section)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                                .motionEntrance(3, listIndex: 0)

                            if !content.rows.isEmpty {
                                Text(content.markCaption)
                                    .titan(.caption)
                                    .foregroundStyle(Theme.label3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, Theme.Space.gutter)
                                    .padding(.bottom, 4)
                                    .motionEntrance(3, listIndex: 0)
                                    .accessibilityHidden(true)
                                    .accessibilityIdentifier("gasto.marca")
                            }

                            if content.rows.isEmpty {
                                Text(index == months.count - 1 ? "Este mes aún no has gastado nada." : "Ese mes no gastaste nada.")
                                    .titan(.callout)
                                    .foregroundStyle(Theme.label2)
                                    .padding(.horizontal, Theme.Space.gutter)
                                    .padding(.top, 8)
                                    .motionEntrance(4, listIndex: 1)
                                    .accessibilityIdentifier("gasto.vacio")
                            } else {
                                ForEach(Array(content.rows.enumerated()), id: \.element.id) { i, row in
                                    NavigationLink(value: SpendingRoute.category(row.category, page)) {
                                        CategoryRow(row: row, index: i, markName: content.markName)
                                    }
                                    .buttonStyle(.row)
                                    .motionEntrance(4 + i, listIndex: 1 + i)
                                }
                            }
                        }
                        .id(page)
                        .transition(blockTransition)

                        SpendingLinkRows(links: snapshot.spendingLinks)
                            .padding(.top, Theme.Space.section)
                            .motionEntrance(5, listIndex: 3)
                    }
                    #if DEBUG
                    // Solo en la demo con `-MiBancoDemoEntranceCount`: cuántas entradas (de pestaña o de mes) ha jugado
                    // Gasto, para comprobar desde una prueba que Reducir movimiento las apaga. En la app de verdad, nada.
                    if DemoMode.isActive, DemoMode.exposesEntranceCount {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityLabel("Entradas de Gasto")
                            .accessibilityValue("\(entrance.token)")
                            .accessibilityIdentifier("gasto.entradas")
                    }
                    #endif
                }
                .padding(.bottom, Theme.Space.section)
                // Las barras de la raíz solo avisan (ámbar con pulso y vibración) si Gasto es la pestaña que se ve y no
                // tiene ninguna pantalla empujada encima: la raíz sigue viva debajo y cruzaría el límite a la vez.
                .environment(\.fillBarsOnScreen, isVisible && !singleSheetOpen && path.isEmpty)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Gasto")
            .navigationDestination(for: SpendingRoute.self) { route in
                Group {
                    switch route {
                    case let .category(category, month): CategoryDetailView(model: model, category: category, month: month, openDetail: openDetail)
                    case .budgets: BudgetsView(model: model, prefill: activeBudgetPrefill)
                    case .transfers: TransfersView(model: model, openDetail: openDetail)
                    case .subscriptions: SubscriptionsView(model: model)
                    case .hiddenSubscriptions: HiddenSubscriptionsView(model: model)
                    case .upcoming: UpcomingCalendarView(model: model, accountBook: accountBook, onMoveMoney: openMoveMoney)
                    }
                }
                // Lo mismo para cada pantalla empujada: solo avisa la que está arriba del todo, con Gasto a la vista.
                .environment(\.fillBarsOnScreen, isVisible && !singleSheetOpen && path.last == route)
            }
            // Deslizar en horizontal cambia de mes (umbral 60 pt, y más horizontal que vertical).
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard abs(dx) >= 60, abs(dx) > abs(dy) * 1.5 else { return }
                        move(by: dx < 0 ? 1 : -1, months: months, from: index)
                    }
            )
            .sensoryFeedback(.selection, trigger: tick)
        }
        .environment(\.entrance, entrance)
        #if DEBUG
        .onAppear {
            guard DemoMode.isActive else { return }
            if let category = DemoMode.openCategory, let current = model.snapshot.spendingMonths.last {
                path = [.category(category, current)]
            } else if DemoMode.opensUpcoming {
                path = [.upcoming]
            } else if DemoMode.opensSubscriptions {
                path = [.subscriptions]
            } else if DemoMode.opensBudgets {
                path = [.budgets]
            }
            guard DemoMode.monthOffset != 0 else { return }
            let months = model.snapshot.spendingMonths
            guard !months.isEmpty else { return }
            let target = max(0, min(months.count - 1, months.count - 1 + DemoMode.monthOffset))
            selection.month = target == months.count - 1 ? nil : months[target]
        }
        #endif
        .onChange(of: openBudgetsRequest, initial: true) { _, open in
            guard open else { return }
            openBudgetsRequest = false
            activeBudgetPrefill = nil
            path = [.budgets]
        }
        .onChange(of: budgetPrefillRequest, initial: true) { _, request in
            guard let request else { return }
            budgetPrefillRequest = nil
            activeBudgetPrefill = request
            path = [.budgets]
        }
        // Al elegir la pestaña (`tabEntrance` de `RootView`, no `isVisible`): el selector de mes y el total entran con la
        // entrada del kit (`.tabGroupEntrance`); lo que cambia con el mes, con la propia (`motionEntrance`), que es la
        // misma que repite el cambio de mes. Cada pieza lleva UNA sola entrada: un cambio de mes en mitad de la entrada
        // de la pestaña la sustituye, nunca suma dos subidas (lote de cierre, ronda 1, m-5).
        .onChange(of: tabEntrance) { _, now in
            guard !now.suppressed, now.token > 0, !motion.reduce else { return }
            begin(.assembly)
        }
    }

    private var blockTransition: AnyTransition {
        guard !motion.reduce else { return .opacity }
        // El mes que entra se construye en el mismo render que cambia la dirección, así que siempre lleva la buena;
        // el que sale solo se funde (su transición se fijó antes del cambio y no puede conocer hacia dónde vas).
        let x = CGFloat(selection.direction) * motion.distance(28)
        // El mes que sale se apaga en 0,1 s: casi no coincide con el que entra (menor m-6).
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: x)),
                           removal: .opacity.animation(.easeOut(duration: motion.seconds(0.10))))
    }

    /// Mes y dirección cambian juntos, dentro de la misma animación: sin temporizador ni tarea.
    private func move(by step: Int, months: [Date], from index: Int) {
        let target = index + step
        guard target >= 0, target < months.count else { return }
        tick += 1
        if !motion.reduce { begin(.list) }
        withAnimation(motion.calmAnimation(.enter)) {
            // El mes en curso se guarda como nil: así sigue al mes nuevo cuando cambia el mes con la app abierta.
            selection = Selection(month: target == months.count - 1 ? nil : months[target], direction: step)
        }
    }

    private func begin(_ scope: Entrance.Scope) {
        let token = entrance.token + 1
        entrance = Entrance(token: token, active: true, scope: scope)
        // La ventana de la entrada dura 1,2 s del kit: sigue la intensidad y la cámara lenta.
        let window = motion.seconds(MotionEntranceWindow.seconds)
        Task {
            try? await Task.sleep(for: .seconds(window))
            if entrance.token == token { entrance.active = false }
        }
    }
}

/// El mes elegido y la dirección del último cambio (+1 = hacia un mes posterior).
private struct Selection: Equatable {
    var month: Date?
    var direction = 1
}
