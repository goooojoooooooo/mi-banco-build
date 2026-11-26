import SwiftUI
import MiBancoCore

/// Presupuestos: «Del mes» y una fila por categoría, cada una con su campo de importe (vacío o 0 = sin presupuesto),
/// lo que sueles gastar y, si hay presupuesto, su barra de este mes. Guarda al terminar de escribir (intro, cambiar de campo
/// o salir) y traza un ✓. Los límites y las medias salen del snapshot; esta vista no calcula nada de gasto.
struct BudgetsView: View {
    let model: LedgerModel

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var texts: [BudgetScope: String] = [:]
    @State private var dirty: Set<BudgetScope> = []
    @State private var errors: [BudgetScope: String] = [:]
    @State private var savedFlash: Set<BudgetScope> = []
    @State private var saveTick = 0
    @State private var errorTick = 0
    @FocusState private var focused: BudgetScope?

    private static let invalidText = "Escribe un importe como 120,00"
    private static let saveFailedText = "No se pudo guardar. Inténtalo de nuevo."

    private static let scopes: [BudgetScope] = [.month] + SpendingCategory.allCases.filter { $0 != .sinCategoria }.map { .category($0) }

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(Self.scopes.enumerated()), id: \.element) { i, scope in
                        row(scope, index: i, snapshot: snapshot)
                        if i < Self.scopes.count - 1 {
                            // Desde el texto de la fila (o el borde, en tamaños de accesibilidad) hasta el margen de 16 pt.
                            Rectangle().fill(Theme.separator).frame(height: 0.5)
                                .padding(.leading, typeSize.isAccessibilitySize ? 16 : 70)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, Theme.Space.small)

                Text("Deja el campo vacío para quitar el límite. Te avisamos al 80 % y cuando te pasas. El aviso llega con los pagos al instante (notificaciones y Wallet); lo que solo entra por una importación o una sincronización cuenta en las barras, pero no avisa.")
                    .titan(.caption)
                    .foregroundStyle(Theme.label3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                    .padding(.top, Theme.Space.row)
                    .accessibilityIdentifier("presupuestos.pie")
            }
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Presupuestos")
        .navigationBarTitleDisplayMode(.large)
        .assemblesOnFirstAppear()
        .onAppear {
            restoreDrafts()
            refreshUntouched()
        }
        .onChange(of: model.state.budgets) { _, _ in refreshUntouched() }
        .onChange(of: focused) { old, _ in
            if let old { commit(old) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focused = nil }
        }
        .onDisappear { for scope in dirty { commit(scope) } }
        .sensoryFeedback(.success, trigger: saveTick)
        .sensoryFeedback(.error, trigger: errorTick)
    }

    // MARK: - Filas

    private func row(_ scope: BudgetScope, index: Int, snapshot: LedgerSnapshot) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(spacing: Theme.Space.row))
        let status = snapshot.budgets.first { $0.scope == scope }
        let barName = "Presupuesto \(scope == .month ? "del mes" : "de \(name(scope))")"
        return VStack(alignment: .leading, spacing: Theme.Space.small) {
            layout {
                HStack(spacing: 14) {
                    Image(systemName: symbol(scope))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Theme.label)
                        .frame(width: 40, height: 40)
                        .background(Theme.raised, in: .rect(cornerRadius: Theme.Radius.logoLarge, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name(scope)).titan(.row).foregroundStyle(Theme.label)
                        if let hint = hint(scope, snapshot: snapshot) {
                            Text(preferences.privateMode ? maskingAmounts(hint) : hint)
                                .titan(.meta)
                                .contentTransition(.identity)
                                .privacySensitive()
                                .foregroundStyle(Theme.label3)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel(preferences.privateMode ? maskingAmounts(hint, with: "importe oculto") : hint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AmountField(id: scope, text: binding(scope), focused: $focused, placeholder: "Sin límite",
                            label: barName, identifier: identifier(scope), saved: savedFlash.contains(scope),
                            stacked: stacked, onSubmit: { commit(scope) })
                    .padding(.leading, stacked ? 54 : 0)
            }
            if let error = errors[scope] {
                Text(error).titan(.meta).foregroundStyle(Theme.warning)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let status {
                // El porcentaje queda alineado con el texto del campo (que lleva 10 pt de margen dentro).
                BudgetBar(status: status, name: barName, index: index, textTrailingInset: stacked ? 0 : 10)
                    .padding(.leading, stacked ? 0 : 54)
                    .transition(.opacity)
                    .accessibilityIdentifier("\(identifier(scope)).barra")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: status != nil)
        .motionEntrance(index, rise: 10)
    }

    private func name(_ scope: BudgetScope) -> String {
        switch scope {
        case .month: "Del mes"
        case .category(let c): c.displayName
        }
    }

    private func symbol(_ scope: BudgetScope) -> String {
        switch scope {
        case .month: "calendar"
        case .category(let c): c.symbolName
        }
    }

    private func identifier(_ scope: BudgetScope) -> String {
        switch scope {
        case .month: "presupuestos.mes"
        case .category(let c): "presupuestos.cat.\(c.rawValue)"
        }
    }

    /// «Sueles gastar unos 640 € al mes» (el del mes) o «sueles: 190 €» (categorías); nada sin media.
    private func hint(_ scope: BudgetScope, snapshot: LedgerSnapshot) -> String? {
        switch scope {
        case .month: snapshot.budgetSuggestions["month"].map { "Sueles gastar unos \(formatEURWhole($0)) al mes" }
        case .category(let c): snapshot.budgetSuggestions["cat-\(c.rawValue)"].map { "sueles: \(formatEURWhole($0))" }
        }
    }

    // MARK: - Guardar (como los saldos de Ajustes: un campo sin tocar nunca pisa lo guardado)

    private func limit(_ scope: BudgetScope) -> Int? {
        let budgets = model.state.budgets
        let cents: Int? = switch scope {
        case .month: budgets.monthlyCents
        case .category(let c): budgets.byCategory[c]
        }
        return cents.flatMap { $0 > 0 ? $0 : nil }
    }

    private func binding(_ scope: BudgetScope) -> Binding<String> {
        Binding(get: { texts[scope] ?? "" }, set: { new in
            guard new != (texts[scope] ?? "") else { return }
            texts[scope] = new
            errors[scope] = nil
            dirty.insert(scope)
        })
    }

    private func refresh(_ scope: BudgetScope) {
        texts[scope] = limit(scope).map { formatEUR($0) } ?? ""
        errors[scope] = nil
    }

    /// Lo que quedó mal escrito la última vez vuelve a su campo, con su error, sin guardarse.
    private func restoreDrafts() {
        for (scope, text) in model.budgetDrafts {
            texts[scope] = text
            dirty.insert(scope)
            errors[scope] = parseBudgetInput(text) == .invalid ? Self.invalidText : Self.saveFailedText
        }
    }

    private func refreshUntouched() {
        for scope in Self.scopes where !dirty.contains(scope) && focused != scope { refresh(scope) }
    }

    private func commit(_ scope: BudgetScope) {
        guard dirty.contains(scope) else { return refresh(scope) }
        let text = (texts[scope] ?? "").trimmingCharacters(in: .whitespaces)
        // Vacío, 0 o un texto sin cifras («€», « €», «,») quita el presupuesto (R32).
        let cents: Int?
        switch parseBudgetInput(text) {
        case .remove:
            cents = nil
        case .set(let value):
            cents = value
        case .invalid:
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { errors[scope] = Self.invalidText }
            errorTick += 1
            model.budgetDrafts[scope] = text
            return
        }
        model.budgetDrafts[scope] = nil
        if cents == limit(scope) {
            dirty.remove(scope)
            return refresh(scope)
        }
        do {
            switch scope {
            case .month: try model.setMonthlyBudget(cents)
            case .category(let c): try model.setBudget(cents, for: c)
            }
            dirty.remove(scope)
            refresh(scope)
            flashSaved(scope)
        } catch {
            withAnimation(reduceMotion ? nil : Theme.Motion.quick) { errors[scope] = Self.saveFailedText }
            errorTick += 1
            // Lo escrito se queda aunque se salga de la pantalla (se recupera en `restoreDrafts`).
            model.budgetDrafts[scope] = text
        }
    }

    /// ✓ trazado 1,4 s junto al campo.
    private func flashSaved(_ scope: BudgetScope) {
        withAnimation(Theme.Motion.quick) { _ = savedFlash.insert(scope) }
        saveTick += 1
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) { _ = savedFlash.remove(scope) }
        }
    }
}
