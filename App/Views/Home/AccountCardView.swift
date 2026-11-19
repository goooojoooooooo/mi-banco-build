import SwiftUI
import MiBancoCore

/// Una tarjeta del carrusel con sus dos caras. Tocarla la voltea en 3D (muelle de 0,55 s, rebote 0,18);
/// detrás: si el saldo es exacto o estimado, desde cuándo, lo gastado este mes y "Editar saldo".
struct AccountCardView: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    let total: Int?
    let monthSpent: Int
    let flipped: Bool
    /// La cifra protagonista cuenta desde 0 la primera vez que la tarjeta se ve.
    let revealed: Bool
    let onFlip: () -> Void
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // La cara delantera es un botón (se hunde al tocar); la trasera lleva su propio botón "Editar saldo",
        // así que se voltea de vuelta con un toque en cualquier otro sitio.
        ZStack {
            Button(action: onFlip) {
                CardFront(card: card, balances: balances, total: total, revealed: revealed)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.985))
            .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: false))

            CardBack(card: card, balances: balances, monthSpent: monthSpent, flipped: flipped, onEdit: onEdit)
                .contentShape(.rect(cornerRadius: Theme.Radius.card))
                .onTapGesture(perform: onFlip)
                .modifier(FlipFace(angle: flipped ? 180 : 0, isBack: true))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.flip, value: flipped)
    }
}

/// Una cara del volteo: gira alrededor del eje Y con perspectiva y solo se ve (y se toca) mientras mira hacia delante.
/// Con Reducir movimiento no gira: las dos caras se funden.
private struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let a = isBack ? angle - 180 : angle
        let facing = abs(a) < 90
        content
            .rotation3DEffect(.degrees(reduceMotion ? 0 : a), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .opacity(reduceMotion ? 1 - abs(a) / 180 : (facing ? 1 : 0))
            .allowsHitTesting(facing)
            .accessibilityHidden(!facing)
    }
}

/// Cara delantera: «Todo» (total y los tres bancos) o un banco (logo, saldo, estado, total al pie).
private struct CardFront: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    let total: Int?
    let revealed: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private var secondary: Color { contrast == .increased ? Theme.card2High : Theme.card2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HeroBalance(cents: heroCents, revealed: revealed, centsColor: secondary)
                .padding(.top, 14)
            Spacer(minLength: 18)
            if card == .all {
                banks
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Total en los tres bancos")
                        .titan(.meta)
                        .foregroundStyle(secondary)
                    CountingAmount(cents: total ?? 0, revealed: revealed)
                        .titan(.cardTitle)
                        .privateAmount()
                }
            }
        }
        .foregroundStyle(Theme.label)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: CarouselMetrics.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(CardSurface(material: card.material))
    }

    private var heroCents: Int {
        card.bank.flatMap { balances[$0]?.cents } ?? (card == .all ? total ?? 0 : 0)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: Theme.Space.small) {
            if let bank = card.bank {
                HStack(spacing: 10) {
                    BankLogo(bank: bank, size: 30)
                    Text(bank.displayName).titan(.cardTitle)
                }
                Spacer(minLength: 0)
                if let info = balances[bank] {
                    if info.estimated {
                        Text("estimado")
                            .titan(.captionStrong)
                            .foregroundStyle(Color(hex: "#D6D6DA"))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    } else {
                        Text(DateText.balanceStatus(info)).titan(.meta).foregroundStyle(secondary)
                    }
                } else {
                    Text("sin saldo").titan(.meta).foregroundStyle(secondary)
                }
            } else {
                Text("Todo").titan(.cardTitle)
                Spacer(minLength: 0)
                Text("3 cuentas").titan(.meta).foregroundStyle(secondary)
            }
        }
        .frame(minHeight: 32)
    }

    private var banks: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        return layout {
            ForEach(BankID.allCases, id: \.self) { bank in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        BankLogo(bank: bank, size: 16)
                        Text(bank.shortName).lineLimit(1)
                    }
                    .titan(.meta)
                    .foregroundStyle(secondary)
                    if let info = balances[bank] {
                        CountingAmount(cents: info.cents, revealed: revealed)
                            .titan(.cardBalance)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privateAmount()
                            .padding(.top, 5)
                        Text(DateText.balanceStatus(info))
                            .titan(.caption)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .padding(.top, 2)
                    } else {
                        Text("—").titan(.cardBalance).padding(.top, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Cara trasera.
private struct CardBack: View {
    let card: AccountCard
    let balances: [BankID: BalanceInfo]
    let monthSpent: Int
    let flipped: Bool
    let onEdit: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    private var secondary: Color { contrast == .increased ? Theme.card2High : Theme.card2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let bank = card.bank {
                    BankLogo(bank: bank, size: 30)
                    Text(bank.displayName).titan(.cardTitle)
                } else {
                    Text("Tus tres cuentas").titan(.cardTitle)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 32)

            Text(title)
                .titan(.cardTitle)
                .padding(.top, 14)
            Text(explanation)
                .titan(.subtitle)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Spacer(minLength: 16)

            HStack(alignment: .bottom, spacing: Theme.Space.row) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Gastado este mes").titan(.meta).foregroundStyle(secondary)
                    CountingAmount(cents: monthSpent, revealed: flipped)
                        .titan(.cardTitle)
                        .privateAmount()
                }
                Spacer(minLength: 0)
                Button(action: onEdit) {
                    Text(card == .all ? "Editar saldos" : "Editar saldo")
                        .titan(.option)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .foregroundStyle(Theme.label)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: CarouselMetrics.minHeight, maxHeight: .infinity, alignment: .topLeading)
        .background(CardSurface(material: card.material, moves: false))
    }

    private var title: String {
        guard let bank = card.bank else { return "Este mes" }
        guard let info = balances[bank] else { return "Sin saldo" }
        return info.estimated ? "Saldo estimado" : "Saldo exacto"
    }

    private var explanation: String {
        guard let bank = card.bank else {
            let estimated = BankID.allCases.filter { balances[$0]?.estimated ?? false }.map(\.displayName)
            switch estimated.count {
            case 0: return "Los tres saldos son exactos: vienen del último aviso de cada banco."
            case 1: return "\(estimated[0]) es estimado: su aviso no trae el saldo, así que lo calculamos."
            default:
                let list = estimated.dropLast().joined(separator: ", ") + " y " + (estimated.last ?? "")
                return "\(list) son estimados: sus avisos no traen el saldo, así que los calculamos."
            }
        }
        return DateText.balanceExplanation(balances[bank], bank: bank)
    }
}

/// La cifra grande de la tarjeta: euros a 50 pt y céntimos a 26 pt en gris de tarjeta; escalan juntos con
/// Dynamic Type y, si no caben, se reducen juntos (los decimales mantienen su proporción).
struct HeroBalance: View {
    let cents: Int
    var revealed = true
    var centsColor = Theme.card2
    @ScaledMetric(relativeTo: .largeTitle) private var euroSize: CGFloat = 50
    @ScaledMetric(relativeTo: .largeTitle) private var centSize: CGFloat = 26

    var body: some View {
        CountingAmount(cents: cents, revealed: revealed,
                       style: .hero(euros: euroSize, cents: centSize, centsColor: centsColor))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .privateAmount(radius: 14)
    }
}

/// Logo de un banco en su ficha (radio ≈ 27 % del lado).
struct BankLogo: View {
    let bank: BankID
    var size: CGFloat = 20
    @Environment(MerchantLogos.self) private var logos

    var body: some View {
        ZStack {
            if let image = logos.bankImage(bank) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.27, style: .continuous))
        .accessibilityHidden(true)
    }
}
