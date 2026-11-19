import SwiftUI

/// Sin saldos todavía: una tarjeta «Todo» vacía (el mismo material, sin cifras) y un único paso a seguir.
struct HomeEmptyState: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Todo").titan(.cardTitle)
                Spacer(minLength: 24)
                Text("— €")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Theme.card2.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.label)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
            .background(CardSurface(material: .all, moves: false))
            .padding(.horizontal, CarouselMetrics.inset)
            .staggeredEntrance(1, rise: 36)

            VStack(alignment: .leading, spacing: Theme.Space.small) {
                Text("Configura el saldo de tus bancos para empezar")
                    .titan(.sheetTitle)
                    .foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Escribe lo que tienes en cada banco. Después, cada aviso lo mantiene al día.")
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: openSettings) {
                    Text("Ir a ajustes")
                        .titan(.option)
                        .fontWeight(.semibold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 48)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, Theme.Space.row)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, Theme.Space.section)
            .staggeredEntrance(2)
        }
        .padding(.top, Theme.Space.small)
    }
}
