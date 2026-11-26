import SwiftUI
import UIKit
import UserNotifications
import MiBancoCore

/// Contenido de la sección `Avisos al instante`: las guías por pasos (`GuideView`) y el botón de prueba.
struct AlertsGuideRows: View {
    let model: LedgerModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var testState: TestState = .idle
    /// El icono del botón pasa a ✓ un momento y vuelve al avión: el botón se puede usar otra vez.
    @State private var showsCheck = false

    private enum TestState: Equatable { case idle, sending, sent, denied }

    var body: some View {
        Group {
            GuideView(model: model)

            VStack(alignment: .leading, spacing: Theme.Space.tight) {
                Text("Cuando termines, pruébalo:")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.label2)
                // Se transforma: cápsula "Probar aviso" → círculo con indicador → ✓ trazado → vuelve.
                Button {
                    Task { await sendTest() }
                } label: {
                    let collapsed = testState == .sending || showsCheck
                    ZStack {
                        if testState == .sending {
                            ProgressView()
                                .tint(.black)
                                .transition(.opacity)
                        } else if showsCheck {
                            DrawnCheck(lineWidth: 2.4, color: .black)
                                .frame(width: 20, height: 20)
                                .transition(.opacity)
                        } else {
                            Label("Probar aviso", systemImage: "paperplane")
                                .labelStyle(.titleAndIcon)
                                .font(Theme.font(.body, weight: .semibold))
                                .foregroundStyle(.black)
                                .fixedSize()
                                .transition(.opacity)
                        }
                    }
                    .frame(width: collapsed ? 44 : nil, height: 44)
                    .padding(.horizontal, collapsed ? 0 : 20)
                    .background(.white, in: Capsule())
                    .animation(reduceMotion ? nil : Theme.Motion.morph, value: collapsed)
                    .animation(.easeOut(duration: 0.2), value: testState)
                }
                .buttonStyle(.pressable)
                .disabled(testState == .sending)
                .accessibilityLabel(testState == .sending ? "Enviando aviso de prueba" : "Probar aviso")
                .padding(.vertical, Theme.Space.tight)
            }
            .listRowBackground(Theme.grouped)

            switch testState {
            case .sent:
                Label {
                    Text("Aviso de prueba enviado. Mantenlo pulsado para verlo en grande.")
                        .font(Theme.font(.footnote))
                        .foregroundStyle(Theme.label2)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.label)
                }
                .transition(.opacity)
                .listRowBackground(Theme.grouped)
            case .denied:
                Text("Activa las notificaciones de \(AppIdentity.displayName) en Ajustes del iPhone.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.warning)
                    .transition(.opacity)
                    .listRowBackground(Theme.grouped)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Abrir Ajustes del iPhone", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .tint(Theme.label)
                .listRowBackground(Theme.grouped)
            case .idle, .sending:
                EmptyView()
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: testState)
        .sensoryFeedback(trigger: testState) { _, new in
            switch new {
            case .sent: SensoryFeedback.success
            case .denied: SensoryFeedback.warning
            default: nil
            }
        }
    }

    /// Igual que el camino real, pero sin tocar el libro de movimientos.
    private func sendTest() async {
        testState = .sending
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            testState = .denied
            return
        }
        let movement = Movement(
            bank: .rev, amountCents: Self.testAmountCents, merchant: Self.testMerchant,
            kind: .payment, source: .notification, date: Date())
        let snapshot = model.snapshot
        var balances: [String: Int] = [:]
        for (bank, info) in snapshot.balances { balances[bank.rawValue] = info.cents }
        let current = snapshot.balances[.rev]?.cents
        let estimated = snapshot.balances[.rev]?.estimated ?? false
        // Un céntimo más antes del "pago" de prueba: así la vista ampliada anima el río de verdad.
        await AlertPoster.post(movement: movement, balance: current, estimated: estimated,
                               balances: balances, previousBalance: current.map { $0 + 1 })
        let shown = await LiveActivityController.show(movement: movement, balance: current, estimated: estimated, total: snapshot.total)
        testState = .sent
        showsCheck = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            showsCheck = false
        }
        // La prueba no se queda 15 minutos en la Dynamic Island.
        guard shown else { return }
        try? await Task.sleep(for: Self.testActivityLifetime)
        await LiveActivityController.endTest(merchant: Self.testMerchant, amountCents: Self.testAmountCents)
    }

    private static let testMerchant = "Prueba"
    private static let testAmountCents = -1
    private static let testActivityLifetime: Duration = .seconds(20)
}
