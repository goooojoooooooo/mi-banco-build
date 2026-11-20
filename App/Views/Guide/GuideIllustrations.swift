import SwiftUI
import MiBancoCore

// Dibujos de la guía: maquetas simplificadas de la pantalla de Atajos hechas en SwiftUI (nunca capturas de Apple),
// con lo que hay que tocar resaltado por un aro blanco de 2 pt que late. Los nombres salen de `GuideNames`.

/// Aro blanco de 2 pt que late cada 1,6 s. Con Reducir movimiento se queda quieto.
private struct PulseRing: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
                    .padding(-4)
                    .opacity(reduceMotion || on ? 1 : 0.3)
                    .scaleEffect(reduceMotion || !on ? 1 : 1.04)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            }
            .onAppear { on = true }
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
private struct MockActionCard: View {
    let track: GuideTrack
    let highlight: String
    var filled = false

    private var fields: [String] {
        track == .wallet
            ? [GuideNames.bankField, GuideNames.amountField, GuideNames.merchantField]
            : [GuideNames.bankField, GuideNames.titleField, GuideNames.subtitleField, GuideNames.bodyField]
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                AppMark(size: 18)
                Text(track == .wallet ? GuideNames.walletAction : GuideNames.noticeAction)
                    .font(Mock.text).foregroundStyle(Theme.label).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            ForEach(fields, id: \.self) { field in
                HStack(spacing: 6) {
                    Text(field).font(Mock.text).foregroundStyle(Theme.label2)
                    Spacer(minLength: 0)
                    if field == highlight || filled {
                        Text(field == GuideNames.bankField ? (track.bankName ?? "—") : GuideNames.shortcutInput)
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
                .pulse(field == highlight, radius: 9)
            }
        }
        .padding(8)
        .background(Mock.row, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MockButton: View {
    let text: String
    var highlighted = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color.white, in: Capsule())
            .pulse(highlighted, radius: 15)
    }
}

/// La maqueta de un paso: se elige por `step.illustration`; lo que se resalta es `step.tapTarget`.
struct GuideIllustrationView: View {
    let step: GuideStep
    let track: GuideTrack

    var body: some View {
        PhoneFrame { mock }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dibujo de la pantalla con «\(step.tapTarget)» resaltado")
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
        case .triggerSearch:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: target, symbol: "magnifyingglass")
                MockRow()
                MockRow(text: target, symbol: track == .wallet ? "wallet.pass" : "bell.badge", highlighted: true)
                MockRow()
                Spacer(minLength: 0)
            }
        case .appPicker:
            VStack(spacing: 8) {
                if track == .wallet {
                    MockNavBar(title: GuideNames.walletApp)
                    MockRow(symbol: "creditcard", checked: true)
                    MockRow(symbol: "creditcard", checked: true)
                    MockRow(symbol: "creditcard", checked: true)
                    Spacer(minLength: 0)
                    MockButton(text: target, highlighted: true)
                } else {
                    MockNavBar(title: GuideNames.appField, trailing: GuideNames.ok)
                    MockRow()
                    MockRow(text: target, symbol: "app.fill", checked: true, highlighted: true)
                    MockRow()
                    MockRow()
                    Spacer(minLength: 0)
                }
            }
        case .runImmediately:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockRow(text: target, checked: true, highlighted: true)
                MockRow()
                HStack {
                    Text(GuideNames.notifyWhenRun).font(Mock.text).foregroundStyle(Theme.label)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Capsule().fill(Mock.bar).frame(width: 34, height: 20)
                        .overlay(alignment: .leading) { Circle().fill(Theme.label).frame(width: 16, height: 16).padding(.leading, 2) }
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(Mock.row, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer(minLength: 0)
                MockButton(text: GuideNames.next)
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
                MockRow(text: target, symbol: "bolt.fill", highlighted: true)
                MockRow()
                Spacer(minLength: 0)
            }
        case .bankPicker:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockActionCard(track: track, highlight: target)
                Spacer(minLength: 0)
            }
        case .variablePicker:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation)
                MockActionCard(track: track, highlight: target, filled: true)
                Spacer(minLength: 0)
            }
        case .done:
            VStack(spacing: 8) {
                MockNavBar(title: GuideNames.newAutomation, trailing: GuideNames.ok, trailingHighlighted: true)
                MockActionCard(track: track, highlight: "", filled: true)
                Spacer(minLength: 0)
            }
        }
    }
}
