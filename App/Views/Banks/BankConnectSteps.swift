import MiBancoCore
import SwiftUI

// En qué punto del trámite está ESTE banco y su porcentaje: `BankConnectStage` y `BankConnectProgress` (Core).

/// «Banco conectado» (momento 4 de los vídeos del dueño, final). Llega tras el remate de los pasos y cuando lo anterior
/// ya se ha apagado (0,15 s, `BankConnectProgress.clearBeforeSuccess`): por eso el ✓ salta casi en el acto (la
/// maqueta: 180 ms después de empezar a apagar los pasos). El ✓ blanco salta de 0,4 a 1 con un destello de luz;
/// cuando el destello se apaga (0,45 s), el título, el estado y el saldo llegan con 70 ms entre ellos, el saldo cuenta desde 0 mientras su fila llega (nunca
/// asoma la cifra final antes de contar) y los botones suben 44 pt al final. El ✓ es blanco, nunca verde. Con Reducir movimiento todo se
/// funde; el ✓ y la vibración de éxito siguen. Con el ojo cerrado el saldo es la máscara del kit.
struct BankConnectedFlash: View {
    let bank: BankID
    let status: String
    let balanceCents: Int?
    let onShowMovements: () -> Void
    let onDone: () -> Void

    @Environment(\.motion) private var motion
    @Environment(AppPreferences.self) private var preferences
    @State private var popped = false
    @State private var counts = false
    @State private var burst = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle().fill(.white)
                if popped {
                    DrawnCheck(lineWidth: 3, color: .black)
                        .frame(width: 24, height: 24)
                }
                // A media escala: el aro del kit (hasta 100 pt de radio) cruzaba el nombre del banco y el título y se
                // salía por el borde izquierdo; así se queda alrededor del ✓ (lote 3, m-2). El título entra cuando el aro
                // ya está casi apagado (0,45 s).
                SuccessBurst(trigger: burst)
                    .scaleEffect(0.5)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(popped || motion.reduce ? 1 : 0.4)
            .opacity(popped ? 1 : 0)
            .accessibilityHidden(true)

            Text("\(bank.displayName), conectado")
                .titan(.week)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("bank-connected-title")
                .risesIn(after: 0.45)

            Text(status)
                .titan(.subtitle)
                .foregroundStyle(Theme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .risesIn(after: 0.52)

            if let balanceCents {
                HStack(spacing: Theme.Space.row) {
                    Text("Saldo")
                        .titan(.option)
                        .foregroundStyle(Theme.label2)
                    Spacer(minLength: Theme.Space.small)
                    RollingAmount(cents: balanceCents, revealed: counts)
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.label)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(Theme.grouped, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Saldo: \(spokenAmount(balanceCents, hidden: preferences.privateMode))")
                .accessibilityIdentifier("bank-connected-balance")
                .padding(.top, 16)
                .risesIn(after: 0.59)
                // El saldo empieza a contar (desde 0) justo cuando su fila empieza a verse: rueda mientras llega y nunca
                // se queda parado en ceros ni enseña la cifra final antes de contar.
                .task {
                    try? await Task.sleep(for: .seconds(motion.seconds(0.59)))
                    counts = true
                }
            }

            HStack(spacing: 10) {
                Button(action: onShowMovements) {
                    Text("Ver movimientos")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.onTileSelected)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.tileSelected, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("bank-connected-show")
                Button(action: onDone) {
                    Text("Listo")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("bank-connected-done")
            }
            .padding(.top, 18)
            .risesIn(after: 0.90, rise: 44, bounce: 0.3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard !popped else { return }
            let spring = Animation.spring(response: motion.seconds(0.42),
                                          dampingFraction: max(0.45, 1 - 0.45 * motion.level.bounceScale))
            withAnimation((motion.reduce ? motion.fade : spring).delay(motion.seconds(0.03))) { popped = true }
            burst += 1
        }
        .sensoryFeedback(Haptics.success, trigger: popped) { _, new in new }
    }
}
