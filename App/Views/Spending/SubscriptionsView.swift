import SwiftUI
import MiBancoCore

/// Suscripciones: lo que pagas al mes y al año, y una fila por suscripción con su próximo cobro y si te han subido el
/// precio. Mantener pulsada una fila: «Esto no es una suscripción» (se va con un muelle; se recupera en «Ocultas»).
/// Todo sale del snapshot.
struct SubscriptionsView: View {
    let model: LedgerModel

    @Environment(\.motion) private var motion
    @State private var errorTick = 0

    /// Solo en la demo con `-MiBancoDemoBigSubscriptions`: la cabecera enseña importes mil veces mayores (cinco y seis
    /// cifras), para comprobar que salta de línea en vez de salirse. En la app de verdad, 1.
    private static var headerScale: Int {
        #if DEBUG
        if DemoMode.isActive, DemoMode.bigSubscriptionTotals { return 1_000 }
        #endif
        return 1
    }

    var body: some View {
        let snapshot = model.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.subscriptions.isEmpty {
                    Text("Aún no hay suscripciones. Aparecen solas cuando un cobro se repite dos meses seguidos.")
                        .titan(.callout)
                        .foregroundStyle(Theme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, Theme.Space.small)
                        .accessibilityIdentifier("suscripciones.vacio")
                        .motionEntrance(0, rise: 8)
                } else {
                    SubscriptionsHeader(monthlyCents: snapshot.subscriptionsMonthlyCents * Self.headerScale,
                                        yearlyCents: snapshot.subscriptionsYearlyCents * Self.headerScale)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.bottom, 10)
                        .motionEntrance(0, rise: 8)
                    ForEach(Array(snapshot.subscriptions.enumerated()), id: \.element.id) { i, row in
                        SubscriptionRowView(row: row, isLast: i == snapshot.subscriptions.count - 1, index: i, hideAction: { hide(row) })
                            .motionEntrance(1 + i)
                            .transition(rowTransition)
                    }
                    // Ocultar una fila es un menú contextual: se dice aquí para que se pueda descubrir.
                    Text("Mantén pulsada una suscripción para ocultarla.")
                        .titan(.caption)
                        .foregroundStyle(Theme.label3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Space.gutter)
                        .padding(.top, Theme.Space.row)
                        .accessibilityIdentifier("suscripciones.pie")
                        .motionEntrance(1 + snapshot.subscriptions.count)
                }

                if !snapshot.hiddenSubscriptions.isEmpty {
                    NavigationLink(value: SpendingRoute.hiddenSubscriptions) {
                        HStack(spacing: Theme.Space.row) {
                            Text("Ocultas (\(snapshot.hiddenSubscriptions.count))")
                                .titan(.row)
                                .foregroundStyle(Theme.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.passive)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle(background: Theme.raised))
                    .background(Theme.grouped, in: RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, Theme.Space.section)
                    .accessibilityIdentifier("suscripciones.ocultas")
                    .transition(.opacity)
                }
            }
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Suscripciones")
        .navigationBarTitleDisplayMode(.large)
        .assemblesOnFirstAppear()
        .sensoryFeedback(.error, trigger: errorTick)
    }

    /// La fila se va con un muelle sin rebote hacia el lado; con Reducir movimiento, solo se funde.
    private var rowTransition: AnyTransition {
        motion.reduce ? .opacity : .asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading)))
    }

    private func hide(_ row: LedgerSnapshot.SubscriptionRow) {
        do {
            try withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
                try model.setSubscriptionDismissed(true, id: row.id)
            }
        } catch {
            errorTick += 1
        }
    }
}

/// Las ocultas, con «Volver a mostrar».
struct HiddenSubscriptionsView: View {
    let model: LedgerModel

    @Environment(\.motion) private var motion
    @Environment(\.dismiss) private var dismiss
    @State private var errorTick = 0

    var body: some View {
        let hidden = model.snapshot.hiddenSubscriptions
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Las ocultas no cuentan en el total ni te avisan del cobro.")
                    .titan(.callout)
                    .foregroundStyle(Theme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.gutter)
                    .padding(.bottom, 8)
                    .motionEntrance(0, rise: 8)
                ForEach(Array(hidden.enumerated()), id: \.element.id) { i, row in
                    SubscriptionRowView(row: row, isLast: i == hidden.count - 1, restoreAction: { restore(row) })
                        .motionEntrance(1 + i)
                        .transition(motion.reduce ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.bottom, Theme.Space.section)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Ocultas")
        .navigationBarTitleDisplayMode(.large)
        .assemblesOnFirstAppear()
        .onChange(of: hidden.isEmpty) { _, empty in
            if empty { dismiss() }
        }
        .sensoryFeedback(.error, trigger: errorTick)
    }

    private func restore(_ row: LedgerSnapshot.SubscriptionRow) {
        do {
            try withAnimation(motion.reduce ? motion.fade : motion.animation(.row)) {
                try model.setSubscriptionDismissed(false, id: row.id)
            }
        } catch {
            errorTick += 1
        }
    }
}

/// «24,98 € al mes · 299,76 € al año»: las dos cifras ruedan desde 0 al montar y de la anterior a la nueva si cambian
/// (`RollingAmount`; con el ojo cerrado, «•••,•• €» y nunca una cifra). Las dos partes se colocan como un párrafo
/// (`ParagraphFlow`): si no caben en una línea (importes largos, letra grande), la segunda baja a la línea siguiente; nunca
/// se salen del ancho ni se montan dos copias. Con letra de accesibilidad, una debajo de la otra.
private struct SubscriptionsHeader: View {
    let monthlyCents: Int
    let yearlyCents: Int

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(ParagraphFlow())
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                RollingAmount(cents: monthlyCents, inline: true)
                Text(stacked ? " al mes" : " al mes · ")
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                RollingAmount(cents: yearlyCents, inline: true)
                Text(" al año")
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .titan(.cardTitle)
        .foregroundStyle(Theme.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenAmount(monthlyCents, hidden: preferences.privateMode)) al mes, \(spokenAmount(yearlyCents, hidden: preferences.privateMode)) al año")
        .accessibilityIdentifier("suscripciones.total")
    }
}

/// «HOY»: la etiqueta de la suscripción que se cobra hoy. Sale con un salto (muelle `snap`, de 0,3 a 1) poco después de
/// su fila; con Reducir movimiento, se funde. La fila ya dice «Próximo cobro: hoy»: para VoiceOver la etiqueta no existe.
private struct TodayTag: View {
    /// Orden de su fila: sale después de que la fila haya entrado.
    let index: Int

    @Environment(\.motion) private var motion
    @State private var popped = false

    var body: some View {
        Text("HOY")
            .titan(.captionStrong)
            .fontWeight(.semibold)
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.label, in: Capsule())
            .scaleEffect(popped || motion.reduce ? 1 : 0.3)
            .opacity(popped ? 1 : 0)
            .accessibilityHidden(true)
            .onAppear {
                guard !popped else { return }
                let delay = motion.seconds(0.32) + motion.stagger(index, firstGap: 0.055, decay: 0.8)
                withAnimation(motion.animation(.snap).delay(motion.reduce ? 0 : delay)) { popped = true }
            }
    }
}

/// Fila de 64 pt: logo, comercio y próximo cobro, importe a la derecha y, debajo, la etiqueta de precio (ámbar si sube,
/// gris si baja). En las activas, el menú contextual la oculta; en las ocultas, el botón «Volver a mostrar».
struct SubscriptionRowView: View {
    let row: LedgerSnapshot.SubscriptionRow
    var isLast = false
    /// Orden en la lista: retrasa el salto de «HOY» hasta que la fila ha entrado.
    var index = 0
    /// Nil en las ocultas.
    var hideAction: (() -> Void)?
    /// Solo en las ocultas.
    var restoreAction: (() -> Void)?

    init(row: LedgerSnapshot.SubscriptionRow, isLast: Bool, index: Int = 0, hideAction: @escaping () -> Void) {
        self.row = row
        self.isLast = isLast
        self.index = index
        self.hideAction = hideAction
    }

    init(row: LedgerSnapshot.SubscriptionRow, isLast: Bool, restoreAction: @escaping () -> Void) {
        self.row = row
        self.isLast = isLast
        self.restoreAction = restoreAction
    }

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        VStack(alignment: .leading, spacing: 0) {
            layout {
                HStack(spacing: 14) {
                    MerchantTile(image: logos.image(merchant: row.merchant, domain: row.logoDomain, isShop: true),
                                 symbol: "repeat", size: tileSize)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(row.merchant)
                                .titan(.row)
                                .foregroundStyle(Theme.label)
                                .lineLimit(stacked ? nil : 1)
                            // Solo en las activas: una oculta no avisa de su cobro.
                            if row.chargesToday, restoreAction == nil {
                                TodayTag(index: index)
                            }
                        }
                        Text(row.nextCharge)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                    amountTexts
                }
                .padding(.leading, stacked ? tileSize + 14 : 0)
            }
            if let restoreAction {
                Button(action: restoreAction) {
                    Text("Volver a mostrar")
                        .titan(.option)
                        .foregroundStyle(Theme.label)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Theme.raised, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 8)
                .padding(.leading, stacked ? 0 : tileSize + 14)
                .accessibilityIdentifier("suscripciones.volverAMostrar")
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)
                .padding(.leading, stacked ? Theme.Space.gutter : Theme.Space.gutter + tileSize + 14)
                .opacity(isLast ? 0 : 1)
        }
        .contentShape(Rectangle())
        .gatedContextMenu(privateTitle: row.merchant) {
            if let hideAction {
                Button("Esto no es una suscripción", systemImage: "eye.slash", action: hideAction)
            }
        } preview: {
            HStack(spacing: 14) {
                MerchantTile(image: logos.image(merchant: row.merchant, domain: row.logoDomain, isShop: true),
                             symbol: "repeat", size: tileSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.merchant)
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Text(row.nextCharge)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    amountTexts
                }
            }
        }
        .accessibilityElement(children: restoreAction == nil ? .ignore : .contain)
        .accessibilityLabel(restoreAction == nil ? spoken : "")
        .accessibilityAction(named: restoreAction == nil ? "Esto no es una suscripción" : "Volver a mostrar") {
            hideAction?()
            restoreAction?()
        }
        .accessibilityIdentifier(restoreAction == nil ? "suscripciones.fila" : "suscripciones.filaOculta")
    }

    /// El importe y, debajo, el cambio de precio. Con el ojo cerrado no se monta ninguna cifra: la máscara del kit
    /// («•••,•• €») y «Sube ••• €», no un desenfoque.
    @ViewBuilder private var amountTexts: some View {
        let hidden = preferences.privateMode
        Text(hidden ? maskedEUR(row.amountCents, sign: false) : formatEUR(row.amountCents))
            .titan(.row)
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.identity)
            .privacySensitive()
        if let change = row.priceChange {
            Text(hidden ? maskingAmounts(change) : change)
                .titan(.meta)
                .foregroundStyle(row.priceWentUp ? Theme.warning : Theme.label2)
                .lineLimit(1)
                .contentTransition(.identity)
                .privacySensitive()
        }
    }

    private var spoken: String {
        let amount = spokenAmount(row.amountCents, hidden: preferences.privateMode)
        var text = "\(row.merchant), \(amount) al mes. \(row.nextCharge)"
        if let change = row.priceChange {
            text += ". \(preferences.privateMode ? row.priceWentUp ? "Sube el precio" : "Baja el precio" : change)"
        }
        return text
    }
}
