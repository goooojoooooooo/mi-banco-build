import SwiftUI
import MiBancoCore

/// Gasto: el mes por categoría. Arriba el selector de mes (flechas o deslizar en horizontal), el total, la comparación con
/// el mes anterior y la previsión; debajo, una fila por categoría. Todo sale de `model.snapshot` (las páginas ya vienen hechas).
struct SpendingView: View {
    let model: LedgerModel
    var isVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Posición en `spendingMonths`; nil = el mes actual (el último).
    @State private var chosen: Int?
    /// +1 = hacia un mes posterior (el contenido sale hacia la izquierda). Se fija un instante antes de cambiar de mes.
    @State private var direction = 1
    @State private var entrance = Entrance()
    @State private var tick = 0

    var body: some View {
        let snapshot = model.snapshot
        let months = snapshot.spendingMonths
        let index = min(chosen ?? (months.count - 1), months.count - 1)
        let page = index >= 0 ? months[index] : nil
        let content = page.flatMap { snapshot.spendingPages[$0] }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let content, let page {
                        MonthSelector(title: content.title, canGoBack: index > 0, canGoForward: index < months.count - 1) { step in
                            move(by: step, count: months.count, from: index)
                        }
                        .padding(.horizontal, 8)
                        .staggeredEntrance(0, rise: 8)

                        SpendingTotal(cents: content.month.totalCents, monthName: content.title)
                            .padding(.horizontal, Theme.Space.gutter)
                            .padding(.top, 2)
                            .staggeredEntrance(1)

                        // Lo que cambia con el mes: se funde y se desliza hacia donde vas; las filas entran escalonadas.
                        VStack(alignment: .leading, spacing: 0) {
                            SpendingSentences(comparison: content.comparison, forecast: content.forecast)
                                .padding(.horizontal, Theme.Space.gutter)
                                .padding(.top, 8)
                                .staggeredEntrance(2, listIndex: 0)

                            Text("Por categoría")
                                .titan(.header)
                                .foregroundStyle(Theme.label3)
                                .padding(.horizontal, Theme.Space.gutter)
                                .padding(.top, Theme.Space.section)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                                .staggeredEntrance(3, listIndex: 0)

                            if content.rows.isEmpty {
                                Text("Este mes aún no has gastado nada.")
                                    .titan(.callout)
                                    .foregroundStyle(Theme.label2)
                                    .padding(.horizontal, Theme.Space.gutter)
                                    .padding(.top, 8)
                                    .staggeredEntrance(4, listIndex: 1)
                                    .accessibilityIdentifier("gasto.vacio")
                            } else {
                                ForEach(Array(content.rows.enumerated()), id: \.element.id) { i, row in
                                    CategoryRow(row: row, index: i)
                                        .staggeredEntrance(4 + i, listIndex: 1 + i)
                                }
                            }
                        }
                        .id(page)
                        .transition(blockTransition)
                    }
                }
                .padding(.bottom, Theme.Space.section)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Gasto")
            // Deslizar en horizontal cambia de mes (umbral 60 pt, y más horizontal que vertical).
            .simultaneousGesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard abs(dx) >= 60, abs(dx) > abs(dy) * 1.5 else { return }
                        move(by: dx < 0 ? 1 : -1, count: months.count, from: index)
                    }
            )
            .sensoryFeedback(.selection, trigger: tick)
        }
        .environment(\.entrance, entrance)
        #if DEBUG
        .onAppear {
            guard DemoMode.isActive, DemoMode.monthOffset != 0 else { return }
            let count = model.snapshot.spendingMonths.count
            chosen = max(0, min(count - 1, count - 1 + DemoMode.monthOffset))
        }
        #endif
        .onChange(of: isVisible) { _, visible in
            guard visible, !reduceMotion else { return }
            begin(.assembly)
        }
    }

    private var blockTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let x = CGFloat(direction) * 28
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: x)),
                           removal: .opacity.combined(with: .offset(x: -x)))
    }

    /// Primero se fija la dirección (el contenido que sale ya la lleva) y en el ciclo siguiente se cambia de mes.
    private func move(by step: Int, count: Int, from index: Int) {
        let target = index + step
        guard target >= 0, target < count else { return }
        direction = step
        tick += 1
        Task { @MainActor in
            if !reduceMotion { begin(.list) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.reveal) { chosen = target }
        }
    }

    private func begin(_ scope: Entrance.Scope) {
        let token = entrance.token + 1
        entrance = Entrance(token: token, active: true, scope: scope)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if entrance.token == token { entrance.active = false }
        }
    }
}
