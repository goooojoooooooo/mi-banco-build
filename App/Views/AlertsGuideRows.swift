import SwiftUI
import UIKit
import UserNotifications
import MiBancoCore

/// Contenido de la sección `Avisos al instante`: guía numerada de Atajos y botón de prueba.
/// Los nombres que hay que buscar en Atajos van resaltados; el resto, apagado.
struct AlertsGuideRows: View {
    let model: LedgerModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var testState: TestState = .idle
    /// El icono del botón pasa a ✓ un momento y vuelve al avión: el botón se puede usar otra vez.
    @State private var showsCheck = false
    @ScaledMetric(relativeTo: .callout) private var badgeSize: CGFloat = 24

    private enum TestState: Equatable { case idle, sending, sent, denied }

    private struct Step: Identifiable {
        let id: Int
        /// Markdown: lo que va en **negrita** es lo que se ve en Atajos.
        let text: String
        var optional = false
    }

    private let steps: [Step] = [
        Step(id: 1, text: "Abre **Atajos**, ve a **Automatización** y pulsa\u{00A0}**+**."),
        Step(id: 2, text: "Elige **Notificación** y selecciona **Revolut**. Marca **Ejecutar inmediatamente** y desactiva **Notificar al ejecutar**."),
        Step(id: 3, text: "Añade la acción **Registrar aviso** de Mi Banco. En **Banco** escribe Revolut; en **Título**, **Subtítulo** y **Cuerpo** elige los datos de la notificación."),
        Step(id: 4, text: "Repite los pasos con **Trade Republic**."),
        Step(id: 5, text: "Para Apple Pay, crea otra automatización de **Cartera**, elige tus tarjetas y añade **Registrar pago con Cartera** de Mi Banco, con su **Banco**, **Importe** y **Comercio**.", optional: true),
    ]

    var body: some View {
        Group {
            Text("Tu iPhone le pasa a Mi Banco los avisos de tus bancos. Se configura una vez, en la app Atajos.")
                .font(Theme.font(.subheadline))
                .foregroundStyle(Theme.label2)
                .listRowBackground(Theme.grouped)

            ForEach(steps) { step in
                stepRow(step)
                    .listRowBackground(Theme.grouped)
                    .listRowSeparatorTint(Theme.separator)
            }

            Label {
                Text("imagin no avisa de los pagos: solo verás al instante los que hagas con Apple Pay.")
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.label2)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.label2)
            }
            .listRowBackground(Theme.grouped)

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
                Text("Activa las notificaciones de Mi Banco en Ajustes del iPhone.")
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

    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.row) {
            if step.optional {
                Color.clear.frame(width: badgeSize, height: 1)
            } else {
                Text("\(step.id)")
                    .font(Theme.font(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            VStack(alignment: .leading, spacing: Theme.Space.small) {
                if step.optional {
                    Text("Opcional")
                        .font(Theme.font(.caption, weight: .semibold))
                        .foregroundStyle(Theme.label2)
                }
                Text(Self.styled(step.text))
                    .fixedSize(horizontal: false, vertical: true)
                if step.id == 1 {
                    Button {
                        if let url = URL(string: "shortcuts://") { openURL(url) }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Abrir Atajos")
                            Image(systemName: "arrow.up.forward")
                                .font(Theme.font(.caption, weight: .semibold))
                        }
                        .font(Theme.font(.footnote, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, Theme.Space.row)
                        .frame(minHeight: 32)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.Space.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((step.optional ? "Opcional. " : "Paso \(step.id). ") + step.text.replacingOccurrences(of: "**", with: ""))
        .modifier(OpenShortcutsAction(enabled: step.id == 1) {
            if let url = URL(string: "shortcuts://") { openURL(url) }
        })
    }

    /// Markdown -> texto de 15 pt: lo resaltado en el color de texto y seminegrita, el resto apagado.
    private static func styled(_ markdown: String) -> AttributedString {
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in text.runs {
            let strong = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
            text[run.range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = strong ? Theme.label : Theme.label2
            text[run.range][AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Theme.font(.callout, weight: strong ? .semibold : .regular)
        }
        return text
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

/// El paso 1 se lee entero con VoiceOver y ofrece "Abrir Atajos" como acción.
private struct OpenShortcutsAction: ViewModifier {
    let enabled: Bool
    let open: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: "Abrir Atajos", open)
        } else {
            content
        }
    }
}
