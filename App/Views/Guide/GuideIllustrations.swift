import SwiftUI
import MiBancoCore

// Dibujos de la guía: maquetas simplificadas de la pantalla de Atajos hechas en SwiftUI (nunca capturas de Apple),
// con lo que hay que tocar resaltado por un aro blanco de 2 pt que late. Los nombres salen de `GuideNames`.

/// Aro blanco de 2 pt alrededor de lo que hay que tocar: al llegar el paso late tres veces (0,8 s cada media vuelta,
/// con los tiempos del kit `\.motion`) y se queda quieto y entero. Nada en bucle (lote 3, I-3). Con Reducir movimiento
/// no late: está quieto desde el principio.
/// Al aparecer el paso, además, un aro de «toca aquí» sale una vez de lo que hay que tocar (`TapRing`: crece de 0,4 a
/// 1,5 y se apaga en 760 ms, medio segundo después de que el paso llegue).
private struct PulseRing: ViewModifier {
    let radius: CGFloat
    @Environment(\.motion) private var motion
    @State private var taps = 0

    private struct Beat {
        var opacity: Double = 1
        var scale: CGFloat = 1
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                let ring = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
                    .padding(-4)
                if motion.reduce {
                    ring
                } else {
                    ring.keyframeAnimator(initialValue: Beat(), trigger: taps) { view, beat in
                        view.opacity(beat.opacity).scaleEffect(beat.scale)
                    } keyframes: { _ in
                        let half = motion.seconds(0.8)
                        KeyframeTrack(\.opacity) {
                            CubicKeyframe(0.5, duration: half)
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(0.5, duration: half)
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(0.5, duration: half)
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(1, duration: half)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(1.04, duration: half)
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(1.04, duration: half)
                            CubicKeyframe(1, duration: half)
                            CubicKeyframe(1.04, duration: half)
                            CubicKeyframe(1, duration: half)
                        }
                    }
                }
            }
            .overlay {
                GeometryReader { geo in
                    TapRing(trigger: taps, size: 40, delay: 0.52)
                        .position(x: geo.size.width * 0.72, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)
            }
            .onAppear {
                taps += 1
            }
    }
}

private extension View {
    @ViewBuilder func pulse(_ enabled: Bool, radius: CGFloat = 10) -> some View {
        if enabled { modifier(PulseRing(radius: radius)) } else { self }
    }
}

private enum Mock {
    static let screen = Color(hex: "#0A0A0B")
    static let row = Color(hex: "#1C1C1E")
    static let bar = Color(hex: "#2C2C2E")
    static let text = Font.system(size: 12, weight: .medium)
    static let small = Font.system(size: 10, weight: .regular)
}

/// Marco de iPhone dibujado, con isla y pantalla negra.
private struct PhoneFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Mock.screen)
            content
                .padding(.top, 38)
                .padding(.bottom, 14)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Capsule().fill(Color.black).frame(width: 64, height: 18).padding(.top, 10)
        }
        .overlay { RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1.5) }
        .frame(width: 236, height: 316)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        // El dibujo se agranda un 25 %: se lee de un vistazo sin llenar la pantalla de negro.
        .scaleEffect(1.25)
        .frame(width: 295, height: 395)
    }
}

/// Fila gris de maqueta: texto opcional y una barra gris cuando no importa lo que ponga.
private struct MockRow: View {
    var text: String?
    var symbol: String?
    var checked = false
    var highlighted = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.label2)
            }
            if let text {
                Text(text).font(Mock.text).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Capsule().fill(Mock.bar).frame(width: 70, height: 7)
            }
            Spacer(minLength: 0)
            if checked {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .pulse(highlighted, radius: 11)
    }
}

private struct MockNavBar: View {
    var title: String?
    var trailing: String?
    var trailingHighlighted = false

    var body: some View {
        HStack {
            Capsule().fill(Mock.bar).frame(width: 26, height: 7)
            Spacer()
            if let title { Text(title).font(Mock.text).foregroundStyle(Theme.label) }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: trailing == "+" ? 16 : 11, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .frame(minWidth: 26, minHeight: 24)
                    .background(Mock.bar, in: Capsule())
                    .pulse(trailingHighlighted, radius: 12)
            } else {
                Capsule().fill(Mock.bar).frame(width: 26, height: 7)
            }
        }
        .frame(height: 30)
    }
}

private struct MockTabBar: View {
    let highlighted: Int?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i == highlighted ? Theme.label : Mock.bar)
                        .frame(width: 18, height: 14)
                    if i == highlighted {
                        Text(GuideNames.automationTab)
                            .font(Mock.small).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        Capsule().fill(Mock.bar).frame(width: 30, height: 5)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .pulse(i == highlighted, radius: 10)
            }
        }
        .padding(.horizontal, 6)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// La tarjeta de la acción dentro de la automatización, con sus campos.
/// Los campos hasta el resaltado ya llevan su dato; el resaltado enseña de dónde sale («Notificación › Título»).
private struct MockActionCard: View {
    let track: GuideTrack
    let highlight: String
    /// Todos los campos con su dato (el paso final).
    var allFilled = false
    /// La ficha que se abre bajo el campo resaltado (la que hay que tocar); sin ella se resalta el propio campo.
    var tray: String?

    private var fields: [String] {
        track.isApplePay
            ? [GuideNames.bankField, GuideNames.amountField, GuideNames.merchantField]
            : [GuideNames.bankField, GuideNames.titleField, GuideNames.subtitleField, GuideNames.bodyField]
    }

    private var variable: String {
        track.isApplePay ? GuideNames.transactionVariable : GuideNames.notificationVariable
    }

    /// Lo que lleva un campo: el banco (salvo en el paso de elegirlo) o «variable › propiedad».
    private func value(_ field: String) -> String? {
        if field == GuideNames.bankField { return highlight == field ? nil : track.bankName }
        let index = fields.firstIndex(of: field) ?? 0
        let reached = fields.firstIndex(of: highlight) ?? -1
        // Con la ficha abierta, el campo resaltado aún está vacío: solo los anteriores llevan su dato.
        return allFilled || index < reached || (tray == nil && index == reached) ? "\(variable) › \(field)" : nil
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                AppMark(size: 18)
                Text(track.isApplePay ? GuideNames.walletAction : GuideNames.noticeAction)
                    .font(Mock.text).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            ForEach(fields, id: \.self) { field in
                HStack(spacing: 6) {
                    Text(field).font(Mock.text).foregroundStyle(Theme.label2)
                    Spacer(minLength: 0)
                    if let text = value(field) {
                        Text(text)
                            .font(Mock.small).foregroundStyle(Theme.label)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(Mock.bar, in: Capsule())
                            .lineLimit(1).minimumScaleFactor(0.6)
                    } else {
                        Capsule().fill(Mock.bar).frame(width: 36, height: 6)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Mock.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .pulse(field == highlight && tray == nil, radius: 9)
                if field == highlight, let tray {
                    // La lista que se abre bajo el campo: la ficha que hay que tocar y otra de relleno.
                    HStack(spacing: 6) {
                        Text(tray)
                            .font(Mock.small).foregroundStyle(Theme.label)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(Mock.bar, in: Capsule())
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .pulse(true, radius: 11)
                        Capsule().fill(Mock.bar).frame(width: 44, height: 22)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(8)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Tarjeta de la acción rápida «Pasar aviso a Onyx» con su único campo «Notificación».
private struct MockQuickActionCard: View {
    var filled = false
    var tray: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                AppMark(size: 18)
                Text(GuideNames.quickNoticeAction)
                    .font(Mock.text).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(GuideNames.notificationField).font(Mock.text).foregroundStyle(Theme.label2)
                Spacer(minLength: 0)
                if filled {
                    Text(GuideNames.notificationVariable)
                        .font(Mock.small).foregroundStyle(Theme.label)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(Mock.bar, in: Capsule())
                        .lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Capsule().fill(Mock.bar).frame(width: 44, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Mock.screen, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .pulse(!filled && tray == nil, radius: 9)

            if let tray {
                HStack(spacing: 6) {
                    Text(tray)
                        .font(Mock.small).foregroundStyle(Theme.label)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Mock.bar, in: Capsule())
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .pulse(true, radius: 11)
                    Capsule().fill(Mock.bar).frame(width: 44, height: 22)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MockButton: View {
    let text: String
    var highlighted = false

    /// Dibujado como contorno, para que no parezca el botón «Siguiente» de verdad de la guía.
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.label)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .overlay(Capsule().stroke(Theme.label2, lineWidth: 1))
            .pulse(highlighted, radius: 15)
    }
}

/// Fila con un interruptor: encendido (blanco, bolita a la derecha) o apagado (gris, bolita a la izquierda).
private struct MockToggleRow: View {
    let text: String
    let isOn: Bool
    var highlighted = false

    var body: some View {
        HStack {
            Text(text).font(Mock.text).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Capsule().fill(isOn ? Theme.label : Mock.bar).frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Color.black : Theme.label).frame(width: 16, height: 16).padding(.horizontal, 2)
                }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .pulse(highlighted, radius: 11)
    }
}

/// La maqueta de un paso: se elige por `step.illustration`; lo que se resalta es `step.tapTarget`.
struct GuideIllustrationView: View {
    let step: GuideStep
    let track: GuideTrack
    /// El dibujo se encoge (con sus proporciones) al espacio que le dan; sin esto mide siempre 295 × 395 pt.
    var fitted = false

    var body: some View {
        Group {
            if fitted {
                GeometryReader { geo in
                    let scale = max(0.001, min(1, geo.size.width / 295, geo.size.height / 395))
                    PhoneFrame { mock }
                        .scaleEffect(scale)
                        .opacity(min(1, max(0, geo.size.height / 120)))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .clipped()
            } else {
                PhoneFrame { mock }
            }
        }
        .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.spokenLabel)
    }

    @ViewBuilder private var mock: some View {
        let target = step.tapTarget
        switch step.illustration {
        case .openShortcuts:
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<16, id: \.self) { i in
                    VStack(spacing: 4) {
                        if i == 6 {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 18)).foregroundStyle(Theme.label)
                                .frame(width: 40, height: 40)
                                .background(LinearGradient(colors: [Color(hex: "#5E5CE6"), Color(hex: "#BF5AF2")],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .pulse(true, radius: 12)
                            Text(GuideNames.shortcutsApp).font(Mock.small).foregroundStyle(Theme.label)
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Mock.bar).frame(width: 40, height: 40)
                            Capsule().fill(Mock.row).frame(width: 26, height: 5)
                        }
                    }
                }
            }
            .padding(.top, 6)
        case .automationTab:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.shortcutsApp)
                MockRow()
                MockRow()
                MockRow()
                Spacer(minLength: 0)
                MockTabBar(highlighted: 1)
            }
        case .plusButton:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.automationTab, trailing: "+", trailingHighlighted: true)
                Spacer(minLength: 0)
                Image(systemName: "bolt.badge.clock").font(.system(size: 30)).foregroundStyle(Theme.passive)
                Capsule().fill(Mock.bar).frame(width: 90, height: 7)
                Spacer(minLength: 0)
                MockTabBar(highlighted: 1)
            }
        case .triggerType:
            // Hay que escribir en el buscador: es lo que se resalta; todavía no hay resultados que tocar.
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: target, symbol: "magnifyingglass", highlighted: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
            }
        case .triggerSearch:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: target, symbol: "magnifyingglass")
                MockRow()
                MockRow(text: target, symbol: track.isApplePay ? "wallet.pass" : "bell.badge", highlighted: true)
                MockRow()
                Spacer(minLength: 0)
            }
        case .appField:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.notificationTrigger)
                MockRow()
                MockRow(text: target, symbol: "app.fill", highlighted: true)
                MockRow()
                Spacer(minLength: 0)
            }
        case .appPicker:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.appField, trailing: GuideNames.ok)
                MockRow()
                MockRow(text: target, symbol: "app.fill", highlighted: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
            }
        case .appOK:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.appField, trailing: GuideNames.ok, trailingHighlighted: true)
                MockRow()
                MockRow(text: track.bankName, symbol: "app.fill", checked: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
            }
        case .walletCards, .walletNext:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.walletApp)
                // Tarjetas con su nombre y sus últimos números (no hay una fila que se llame como el banco).
                MockRow(text: "Tarjeta  •••• 1234", symbol: "creditcard", checked: true,
                        highlighted: step.illustration == .walletCards)
                MockRow(text: "Otra tarjeta  •••• 5678", symbol: "creditcard")
                Spacer(minLength: 0)
                MockButton(text: GuideNames.next, highlighted: step.illustration == .walletNext)
            }
        case .runImmediately:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: target, highlighted: true)
                MockRow()
                Spacer(minLength: 0)
                MockButton(text: GuideNames.next)
            }
        case .notifyOff:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: GuideNames.runImmediately, checked: true)
                MockRow()
                // Así llega el interruptor (encendido): hay que apagarlo.
                MockToggleRow(text: target, isOn: true, highlighted: true)
                Spacer(minLength: 0)
                MockButton(text: GuideNames.next)
            }
        case .runNext:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: GuideNames.runImmediately, checked: true)
                MockRow()
                MockToggleRow(text: GuideNames.notifyWhenRun, isOn: false)
                Spacer(minLength: 0)
                MockButton(text: target, highlighted: true)
            }
        case .blankAutomation:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(symbol: "sparkles")
                MockRow(symbol: "sparkles")
                Spacer(minLength: 0)
                MockButton(text: target, highlighted: true)
                Spacer(minLength: 0)
            }
        case .addActionButton:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation, trailing: GuideNames.ok)
                Spacer(minLength: 0)
                MockRow(text: target, symbol: "plus.circle", highlighted: true)
                Spacer(minLength: 0)
            }
        case .addActionSearch:
            // Tocar el buscador: aún vacío.
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.addAction)
                MockRow(text: "Buscar", symbol: "magnifyingglass", highlighted: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
            }
        case .addActionType:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.addAction)
                MockRow(text: target, symbol: "magnifyingglass", highlighted: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
            }
        case .addAction:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.addAction)
                MockRow(text: guideAppName, symbol: "magnifyingglass")
                HStack(spacing: 6) {
                    AppMark(size: 18)
                    Text(guideAppName).font(Mock.small).foregroundStyle(Theme.label2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                MockRow(text: target, symbol: track.isApplePay ? "wallet.pass" : "bell.badge", highlighted: true)
                MockRow()
                Spacer(minLength: 0)
            }
        case .bankPicker:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockActionCard(track: track, highlight: target)
                Spacer(minLength: 0)
            }
        case .bankChoice:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.bankField)
                ForEach(BankID.allCases, id: \.self) { bank in
                    MockRow(text: bank.displayName, symbol: "building.columns", highlighted: bank == track.bank)
                }
                Spacer(minLength: 0)
            }
        case .variablePicker:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockActionCard(track: track, highlight: step.focus, tray: target)
                Spacer(minLength: 0)
            }
        case .done:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation, trailing: GuideNames.ok, trailingHighlighted: true)
                MockActionCard(track: track, highlight: "", allFilled: true)
                Spacer(minLength: 0)
            }
        case .quickTrigger:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation, trailing: GuideNames.plus)
                MockRow(text: GuideNames.notificationTrigger, symbol: "bell.badge", highlighted: true)
                MockRow()
                MockRow()
                Spacer(minLength: 0)
                MockTabBar(highlighted: 1)
            }
        case .quickRun:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: GuideNames.runImmediately, checked: true, highlighted: true)
                MockToggleRow(text: GuideNames.notifyWhenRun, isOn: false)
                Spacer(minLength: 0)
                MockButton(text: GuideNames.next)
            }
        case .quickAction:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.addAction)
                MockRow(text: guideAppName, symbol: "magnifyingglass")
                HStack(spacing: 6) {
                    AppMark(size: 18)
                    Text(guideAppName).font(Mock.small).foregroundStyle(Theme.label2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                MockRow(text: GuideNames.quickNoticeAction, symbol: "bell.badge", highlighted: true)
                Spacer(minLength: 0)
            }
        case .quickNoticeInput:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockQuickActionCard(filled: false, tray: target)
                Spacer(minLength: 0)
            }
        case .quickDone:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation, trailing: GuideNames.ok, trailingHighlighted: true)
                MockQuickActionCard(filled: true)
                VStack(spacing: 5) {
                    MockRow(text: BankID.rev.displayName, symbol: "bell.badge", checked: true)
                    MockRow(text: BankID.tr.displayName, symbol: "bell.badge", checked: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
