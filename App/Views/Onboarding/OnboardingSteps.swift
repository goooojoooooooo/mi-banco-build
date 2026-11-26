import MiBancoCore
import SwiftUI

/// Paso 1 de la bienvenida: saldos iniciales de los tres bancos. Al aparecer, sus piezas llegan una tras otra (120 ms
/// entre ellas, subiendo 22 pt) mientras las bandas de titanio cruzan el fondo; el botón llega el último con un bote.
/// Con el ojo cerrado, un saldo ya escrito (y sin editar) es la máscara del kit: ninguna cifra en pantalla.
struct OnboardingBalancesStep: View {
    let model: LedgerModel
    /// La bienvenida ya está a la vista: las piezas empiezan a llegar.
    var arrived = true
    let onNext: () -> Void

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.motion) private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    /// El bloqueo, tal como lo da la carcasa (`RootView`).
    @Environment(\.shellReveal) private var shell
    @State private var texts: [BankID: String] = [:]
    @State private var errors: [BankID: String] = [:]
    @FocusState private var focused: BankID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tus saldos")
                            .titan(.homeTitle)
                            .foregroundStyle(Theme.label)
                            .accessibilityAddTraits(.isHeader)
                            .risesIn(when: arrived, after: 0.30, rise: 22)

                        Text("Escribe lo que tienes ahora en cada banco. \(AppIdentity.displayName) lo irá actualizando.")
                            .titan(.callout)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .risesIn(when: arrived, after: 0.42, rise: 22)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(BankID.allCases.enumerated()), id: \.element) { index, bank in
                            balanceRow(for: bank)
                            if index < BankID.allCases.count - 1 {
                                Divider()
                                    .overlay(Theme.separator)
                                    .padding(.leading, 58)
                            }
                        }
                    }
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .risesIn(when: arrived, after: 0.54, rise: 22)
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            Button(action: submitAndContinue) {
                Text("Seguir")
                    .titan(.option)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onTileSelected)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.tileSelected, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityIdentifier("onboarding-next-1")
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.gutter)
            .risesIn(when: arrived, after: 0.66, rise: 34, bounce: 0.28)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focused = nil }
        }
        .onChange(of: shell.locked) { _, locked in
            if locked { focused = nil }
        }
        // Al cerrarse el ojo (desde aquí o desde Inicio) un importe en edición suelta el foco en el acto y pasa a máscara, sin
        // animación: nunca queda una cifra a la vista con el ojo cerrado (lote de cierre, ronda 1, I-3). Lo escrito se
        // guarda como al soltar el foco.
        .onChange(of: preferences.privateMode) { _, on in
            guard on, focused != nil else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { focused = nil }
        }
    }

    private func balanceRow(for bank: BankID) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let isEditing = focused == bank
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(spacing: Theme.Space.row))
        return VStack(alignment: .leading, spacing: Theme.Space.tight) {
            layout {
                HStack(spacing: 14) {
                    BankLogo(bank: bank, size: 30)
                    Text(bank.displayName)
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                }
                if !stacked { Spacer(minLength: Theme.Space.small) }
                MaskedAmountTextField(placeholder: "0,00 €", text: binding(for: bank), hidden: preferences.privateMode, editing: isEditing)
                    .titan(.option)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(stacked ? .leading : .trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .focused($focused, equals: bank)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 108, maxWidth: stacked ? .infinity : 140, minHeight: 40)
                    .background(
                        Theme.fieldFill.opacity(isEditing ? 1 : 0),
                        in: .rect(cornerRadius: Theme.Radius.field)
                    )
                    .accessibilityLabel("Saldo de \(bank.displayName)")

            }
            if let error = errors[bank] {
                Text(error)
                    .titan(.meta)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            focused = bank
        }
    }

    private func binding(for bank: BankID) -> Binding<String> {
        Binding(
            get: { texts[bank] ?? "" },
            set: { newValue in
                texts[bank] = newValue
                errors[bank] = nil
            }
        )
    }

    private func submitAndContinue() {
        focused = nil
        var hasError = false
        for bank in BankID.allCases {
            let raw = (texts[bank] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            guard let cents = parseBalanceInput(raw) else {
                withAnimation(motion.fade) {
                    errors[bank] = "Escribe un importe como 340,20"
                }
                hasError = true
                continue
            }
            do {
                try model.setBalance(bank, cents: cents)
            } catch {
                withAnimation(motion.fade) {
                    errors[bank] = "No se pudo guardar. Inténtalo de nuevo."
                }
                hasError = true
            }
        }
        if !hasError {
            onNext()
        }
    }
}

/// Paso 2 de la bienvenida: configurar los avisos al instante en Atajos.
struct OnboardingAlertsStep: View {
    let onStartGuide: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Avisos al instante")
                            .titan(.homeTitle)
                            .foregroundStyle(Theme.label)
                            .accessibilityAddTraits(.isHeader)

                        Text("Para enterarte de cada pago, enseña a tu iPhone a pasarle los avisos a \(AppIdentity.displayName). Te guiamos paso a paso para cada banco.")
                            .titan(.callout)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                Button(action: onStartGuide) {
                    Text("Empezar la guía")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("onboarding-start-guide")

                Button(action: onLater) {
                    Text("Lo haré luego")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("onboarding-later")
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.gutter)
        }
    }
}

/// Paso 3 de la bienvenida: conexión bancaria y bloqueo con Face ID.
struct OnboardingBanksStep: View {
    let onConnectNow: () -> Void
    let onStart: () -> Void

    @AppStorage("lockEnabled") private var lockEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tus bancos, al día")
                            .titan(.homeTitle)
                            .foregroundStyle(Theme.label)
                            .accessibilityAddTraits(.isHeader)

                        Text("Si quieres, conecta Revolut e imagin para ver sus movimientos reales. Puedes hacerlo cuando quieras en Ajustes.")
                            .titan(.callout)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Toggle(isOn: $lockEnabled) {
                            OptionLabel(
                                title: "Bloquear con Face ID",
                                detail: "Pedirlo al volver a la app",
                                systemImage: "faceid"
                            )
                        }
                        .toggleStyle(TitanToggleStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                }
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 12) {
                Button(action: onConnectNow) {
                    Text("Conectar ahora")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("onboarding-connect-now")

                Button(action: onStart) {
                    Text("Empezar")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("onboarding-finish")
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.bottom, Theme.Space.gutter)
        }
    }
}
