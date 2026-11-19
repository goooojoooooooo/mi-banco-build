import SwiftUI
import MiBancoCore

/// Avisos (Parte 1): lo que merece tu atención, de `insights(for:now:calendar:)` vía el snapshot.
/// La Parte 2 añadirá aquí los interruptores de cada tipo de aviso.
struct AlertsView: View {
    let model: LedgerModel
    var isVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Al entrar en la pestaña, los avisos llegan uno tras otro.
    @State private var entrance = Entrance()

    var body: some View {
        let insights = model.snapshot.insights
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if insights.isEmpty {
                        AlertsEmptyState()
                    } else {
                        Text("Novedades")
                            .titan(.header)
                            .foregroundStyle(Theme.label3)
                            .padding(.horizontal, 36)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                                InsightRow(insight: insight, isLast: index == insights.count - 1)
                                    .staggeredEntrance(index)
                                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                            }
                        }
                        .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                        .padding(.horizontal, 16)
                        Text("Todo se calcula en tu iPhone con tus movimientos. Nada sale del teléfono.")
                            .titan(.meta)
                            .foregroundStyle(Theme.label3)
                            .padding(.horizontal, 36)
                            .padding(.top, 8)
                    }
                }
                .animation(reduceMotion ? nil : Theme.Motion.morph, value: insights.map(\.id))
                .padding(.bottom, Theme.Space.section)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Avisos")
        }
        .environment(\.entrance, entrance)
        .onChange(of: isVisible) { _, visible in
            guard visible, !reduceMotion else { return }
            let token = entrance.token + 1
            entrance = Entrance(token: token, active: true, scope: .assembly)
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if entrance.token == token { entrance.active = false }
            }
        }
    }
}

/// Un aviso: icono con el color de su gravedad (ámbar = atención, verde = dinero que entra), título, detalle y cuándo.
private struct InsightRow: View {
    let insight: Insight
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(insight.severity == .info ? 0 : 0.14), in: .rect(cornerRadius: 9, style: .continuous))
                .background(Theme.raised, in: .rect(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .titan(.option)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = insight.detail {
                    Text(detail)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(when)
                .titan(.meta)
                .foregroundStyle(Theme.label3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: 60)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.leading, 64).opacity(isLast ? 0 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([severityWord, insight.title, insight.detail, when].compactMap { $0 }.joined(separator: ". "))
    }

    private var tint: Color {
        switch insight.severity {
        case .warning: Theme.warning
        case .positive: Theme.income
        case .info: Theme.monogram
        }
    }

    private var severityWord: String? {
        switch insight.severity {
        case .warning: "Atención"
        case .positive, .info: nil
        }
    }

    private var symbol: String {
        switch insight.kind {
        case .lowBalance: "battery.25"
        case .largePayment: "exclamationmark.circle"
        case .unusualPayment: "waveform.path.ecg"
        case .salary: "briefcase"
        case .largeIncome: "arrow.down.circle"
        case .duplicateCharge: "square.on.square"
        case .subscriptionUpcoming: "calendar"
        case .subscriptionPriceChange: "arrow.up.right"
        case .spendingPace: "gauge.with.dots.needle.33percent"
        case .weeklyDigest: "doc.text"
        }
    }

    /// "hoy", "ayer", "mañana", "17 nov".
    private var when: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(insight.date) { return "hoy" }
        if calendar.isDateInYesterday(insight.date) { return "ayer" }
        if calendar.isDateInTomorrow(insight.date) { return "mañana" }
        return DateText.day(insight.date)
    }
}

private struct AlertsEmptyState: View {
    var body: some View {
        VStack(spacing: Theme.Space.row) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.passive)
                .accessibilityHidden(true)
            Text("Todo en orden. Aquí verás lo que merece tu atención.")
                .titan(.callout)
                .foregroundStyle(Theme.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
        .padding(.top, 120)
    }
}
