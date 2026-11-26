import SwiftUI
import MiBancoCore

/// Una pieza de la lista (cabecera de día, movimiento o aviso sin leer). Siempre una sola vista por elemento.
struct ListEntryView: View {
    let entry: ListEntry
    /// Dominio del directorio del movimiento (del snapshot).
    let logoDomain: String?
    let isFresh: Bool
    let zoom: Namespace.ID
    let onOpen: (UUID) -> Void
    let onDeleteUnread: (UUID) -> Void
    /// La fila abierta por deslizamiento (solo una a la vez); `nil` = estas filas no se deslizan (búsqueda).
    var openRow: Binding<UUID?>? = nil
    /// «No es mío» / «Sí es mío» desde las acciones de la fila: (movimiento, marcado).
    var onFlag: ((UUID, Bool) -> Void)? = nil

    var body: some View {
        switch entry.kind {
        case let .header(title, isFirst):
            Text(title)
                .titan(.header)
                .foregroundStyle(Theme.label3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.gutter)
                .padding(.top, isFirst ? 14 : 22)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
        case let .row(row, isLast):
            switch row.item {
            case .movement(let m):
                MovementRowView(movement: m, row: row, logoDomain: logoDomain, isLast: isLast, isFresh: isFresh,
                                zoom: zoom, openRow: openRow, onFlag: onFlag) { onOpen(m.id) }
            case .unread(let n):
                UnreadRowView(notice: n, isLast: isLast) { onDeleteUnread(n.id) }
            }
        }
    }
}

/// Fila de 64 pt: logo (o monograma), comercio y subtítulo, importe a la derecha (verde con "+" si entra).
/// Al tocar (no al soltar): fondo #141416 y escala 0,985; abre el detalle con el logo como elemento compartido.
/// - Con el ojo cerrado el importe es su máscara («−•••,•• €»): la cifra no se monta bajo un desenfoque.
/// - Una fila recién llegada (`isFresh`) cae desde 22 pt más arriba al 96,5 % y una luz la barre una vez.
/// - En la lista de Inicio se desliza hacia la izquierda para «Nota» y «No es mío» (`SwipeActionsRow`).
struct MovementRowView: View {
    let movement: Movement
    let row: ListRow
    let logoDomain: String?
    var isLast = false
    var isFresh = false
    let zoom: Namespace.ID
    var openRow: Binding<UUID?>? = nil
    var onFlag: ((UUID, Bool) -> Void)? = nil
    let onOpen: () -> Void

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.motion) private var motion
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    private var flagTitle: String { movement.flaggedNotMine ? "Sí es mío" : "No es mío" }

    var body: some View {
        Group {
            if let openRow, let onFlag {
                let id = movement.id
                let flagged = movement.flaggedNotMine
                SwipeActionsRow(rowID: id, openRow: openRow, actions: [
                    RowSwipeAction(id: "note", title: "Nota", perform: onOpen),
                    RowSwipeAction(id: "flag", title: flagTitle, warning: true) { onFlag(id, !flagged) },
                ]) {
                    rowButton
                }
            } else {
                rowButton
            }
        }
        .modifier(FreshDrop(isFresh: isFresh))
    }

    @ViewBuilder private var rowButton: some View {
        let logo = logos.image(merchant: movement.merchant, domain: logoDomain, isShop: movement.isShop)
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        Button(action: onOpen) {
            layout {
                HStack(spacing: 14) {
                    MerchantTile(image: logo, symbol: movement.fallbackSymbol, size: tileSize)
                        .matchedTransitionSource(id: movement.id, in: zoom)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .titan(.row)
                            .foregroundStyle(Theme.label)
                            .lineLimit(stacked ? nil : 1)
                        if !row.subtitle.isEmpty || row.unconfirmed || movement.flaggedNotMine {
                            HStack(spacing: 4) {
                                if movement.flaggedNotMine {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.warning)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                if row.unconfirmed {
                                    if row.subtitle.isEmpty {
                                        Text("Sin confirmar por el banco")
                                            .foregroundStyle(Theme.warning)
                                            .lineLimit(1)
                                    } else {
                                        Text("\(row.subtitle)\(Text(" · Sin confirmar por el banco").foregroundStyle(Theme.warning))")
                                            .lineLimit(1)
                                    }
                                } else if !row.subtitle.isEmpty {
                                    Text(row.subtitle)
                                        .lineLimit(1)
                                }
                            }
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Con el ojo cerrado, la máscara (nunca la cifra bajo un desenfoque).
                MaskedAmountText(signedEUR(movement.amountCents), masked: maskedEUR(movement.amountCents, sign: true))
                    .titan(.row)
                    .foregroundStyle(amountColor)
                    .strikethrough(movement.flaggedNotMine, color: Theme.label3)
                    .lineLimit(1)
                    .fixedSize()
                    // Apunta dónde está el importe en pantalla: el del detalle sale volando desde aquí. Solo
                    // apunta el marco (no cambia el diseño ni los toques) y se lee al tocar la fila, nunca al dibujar.
                    .detailAmountSource(id: movement.id)
                    .modifier(IncomeArrivalCheck(active: isFresh && movement.amountCents > 0))
                    // En una fila deslizada se apaga con la apertura (ver `SwipeAmountFade`); fuera de ella, nada.
                    .modifier(SwipeAmountFade())
                    .padding(.leading, stacked ? tileSize + 14 : 0)
            }
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .background(Theme.fresh.opacity(isFresh ? 1 : 0))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 0.5)
                    .padding(.leading, stacked ? Theme.Space.gutter : Theme.Space.gutter + tileSize + 14)
                    .opacity(isLast ? 0 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .animation(motion.calmAnimation(.snap), value: movement.flaggedNotMine)
        .gatedContextMenu(privateTitle: movement.displayMerchant ?? "Movimiento") {
            if logo != nil, let merchant = movement.merchant {
                Button("No usar este logo", systemImage: "eye.slash") { logos.block(merchant: merchant) }
            }
        } preview: {
            HStack(spacing: 14) {
                MerchantTile(image: logo, symbol: movement.fallbackSymbol, size: tileSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MaskedAmountText(signedEUR(movement.amountCents), masked: maskedEUR(movement.amountCents, sign: true))
                    .titan(.row)
                    .foregroundStyle(amountColor)
                    .strikethrough(movement.flaggedNotMine, color: Theme.label3)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // Con el ajuste en la clave: al volver a activarlo, las filas visibles buscan su logo.
        .task(id: LogoTaskID(merchant: movement.merchant, downloads: logos.downloadsEnabled)) {
            logos.requestIfNeeded(for: movement, domain: logoDomain)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Abre el detalle")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("movementRow")
        .modifier(RowNamedActions(flagTitle: flagTitle, onNote: onFlag == nil ? nil : onOpen, onFlag: flagAction))
    }

    /// «No es mío» / «Sí es mío» sobre este movimiento; `nil` donde las filas no llevan acciones (búsqueda).
    private var flagAction: (() -> Void)? {
        guard let onFlag else { return nil }
        let id = movement.id
        let flagged = movement.flaggedNotMine
        return { onFlag(id, !flagged) }
    }

    private var amountColor: Color {
        if movement.flaggedNotMine { return Theme.label3 }
        return movement.amountCents > 0 ? Theme.income : Theme.label
    }

    private var spoken: String {
        let what = movement.amountCents < 0 ? "pago de" : "ingreso de"
        var text = "\(row.title), \(what) \(spokenAmount(abs(movement.amountCents), hidden: preferences.privateMode)). "
        text += "\(movement.bank.displayName), \(DateText.moment(movement.date, dayOnly: movement.dayOnly))"
        if let note = movement.note { text += ". Nota: \(note)" }
        if movement.bankStatus == .pending { text += ". Pendiente" }
        if row.unconfirmed { text += ". Sin confirmar por el banco" }
        if movement.flaggedNotMine { text += ". Marcado como no es mío" }
        return text
    }
}

/// Las acciones de deslizar, también para VoiceOver (que no desliza): «Nota» y «No es mío».
private struct RowNamedActions: ViewModifier {
    let flagTitle: String
    let onNote: (() -> Void)?
    let onFlag: (() -> Void)?

    func body(content: Content) -> some View {
        if let onNote, let onFlag {
            content
                .accessibilityAction(named: "Nota", onNote)
                .accessibilityAction(named: flagTitle, onFlag)
        } else {
            content
        }
    }
}

/// El ✓ verde junto al importe de un ingreso recién llegado. Entra creciendo desde el 20 %. Al terminar el momento se
/// retira en dos tiempos, sin montarse nunca sobre el «€»: primero el ✓ se apaga en su sitio (0,2 s, al 60 %) y solo
/// después el importe se desliza a su posición (0,25 s). El deslizamiento es un desplazamiento (`offset`) que compensa
/// el hueco que deja el ✓ al salir: la maquetación cambia una sola vez, sin animar, cuando el ✓ ya no se ve.
private struct IncomeArrivalCheck: ViewModifier {
    let active: Bool
    @Environment(\.motion) private var motion
    @State private var inLayout: Bool
    @State private var shown = false
    @State private var leaving = false
    @State private var slide = 0
    @State private var gap: CGFloat = 23

    init(active: Bool) {
        self.active = active
        _inLayout = State(initialValue: active)
    }

    func body(content: Content) -> some View {
        let distance = motion.reduce ? 0 : gap
        let duration = motion.seconds(0.25)
        HStack(spacing: 6) {
            content
                .keyframeAnimator(initialValue: CGFloat(0), trigger: slide) { view, x in
                    view.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(-distance)
                        CubicKeyframe(0, duration: duration)
                    }
                }
            if inLayout {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.income)
                    .scaleEffect(shown || motion.reduce ? 1 : (leaving ? 0.6 : 0.2))
                    .opacity(shown ? 1 : 0)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gap = $0 + 6 }
                    .accessibilityHidden(true)
            }
        }
        .onAppear { if active { enter() } }
        .onChange(of: active) { _, now in now ? enter() : leave() }
    }

    private func enter() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            inLayout = true
            leaving = false
        }
        withAnimation(motion.animation(.release)) { shown = true }
    }

    private func leave() {
        guard inLayout else { return }
        leaving = true
        withAnimation(.easeOut(duration: motion.seconds(0.2))) {
            shown = false
        } completion: {
            guard !active else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                inLayout = false
                slide += 1
            }
        }
    }
}

/// La fila recién llegada: cae desde 22 pt más arriba (× el recorrido del nivel) al 96,5 % con el muelle de fila,
/// aparece en 0,2 s y una luz la barre una vez (0,76 s; sin luz en Bajo consumo). Con Reducir movimiento solo se funde.
/// Las filas de siempre (`isFresh` falso al montarse) no hacen nada.
private struct FreshDrop: ViewModifier {
    let isFresh: Bool
    @Environment(\.motion) private var motion
    @State private var landed: Bool
    @State private var shown: Bool
    /// Mientras cae, la fila se recorta a su propio hueco: sale de debajo del rótulo del día («Hoy»), nunca pasa por
    /// encima de él. Al asentarse deja de recortarse (sin animación).
    @State private var clipped: Bool
    @State private var sweep = 0

    init(isFresh: Bool) {
        self.isFresh = isFresh
        _landed = State(initialValue: !isFresh)
        _shown = State(initialValue: !isFresh)
        _clipped = State(initialValue: isFresh)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFresh, motion.richEffects {
                    RowSweep(trigger: sweep)
                }
            }
            .scaleEffect(landed || motion.reduce ? 1 : 0.965)
            .offset(y: landed ? 0 : -motion.distance(22))
            .opacity(shown ? 1 : 0)
            // Recortada a su hueco mientras cae; después, sin recorte (un rectángulo mucho mayor que la fila).
            .clipShape(Rectangle().inset(by: clipped ? 0 : -400))
            .onAppear {
                guard !landed else { return }
                withAnimation(motion.animation(.row)) {
                    landed = true
                } completion: {
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { clipped = false }
                }
                withAnimation(.easeOut(duration: motion.seconds(motion.reduce ? 0.26 : 0.2))) { shown = true }
                sweep += 1
            }
    }
}

/// La luz que barre la fila nueva: una franja blanca al 11 % que cruza de lado a lado en 0,76 s, tras 0,14 s; su
/// opacidad sube y baja. Solo se mueve con `offset` y cambia de opacidad.
private struct RowSweep: View {
    let trigger: Int
    @Environment(\.motion) private var motion

    private struct Values {
        var x = -1.0
        var opacity = 0.0
    }

    var body: some View {
        let wait = motion.seconds(0.14)
        let half = motion.seconds(0.38)
        LinearGradient(
            stops: [.init(color: .white.opacity(0), location: 0.3),
                    .init(color: .white.opacity(0.11), location: 0.5),
                    .init(color: .white.opacity(0), location: 0.7)],
            startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6))
            .keyframeAnimator(initialValue: Values(), trigger: trigger) { view, value in
                view
                    .offset(x: value.x * 440)
                    .opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    LinearKeyframe(-1.0, duration: wait)
                    CubicKeyframe(1.0, duration: half * 2)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.0, duration: wait)
                    CubicKeyframe(1.0, duration: half)
                    CubicKeyframe(0.0, duration: half)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct LogoTaskID: Equatable {
    let merchant: String?
    let downloads: Bool
}

/// Aviso con importe que la app no supo leer: tus cifras pueden no estar al día, así que se ve como una fila.
/// Muestra su texto (2 líneas, se amplía al tocar) y se borra con la ✕.
struct UnreadRowView: View {
    let notice: UnreadNotice
    var isLast = false
    let onDelete: () -> Void

    @State private var expanded = false
    @Environment(\.motion) private var motion
    @Environment(AppPreferences.self) private var preferences
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    /// En modo privado, el texto del banco sin cifras (no se sabe en qué formato trae el importe).
    private var shownText: String {
        preferences.privateMode ? maskingAmounts(notice.text, everyNumber: true) : notice.text
    }
    private var spokenText: String {
        preferences.privateMode ? maskingAmounts(notice.text, with: "importe oculto", everyNumber: true) : notice.text
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.small) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 14) {
                    MerchantTile(image: nil, symbol: "questionmark", size: tileSize, symbolColor: Theme.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No se pudo leer este aviso")
                            .titan(.row)
                            .foregroundStyle(Theme.label)
                        Text(shownText)
                            .contentTransition(.opacity)
                            .titan(.subtitle)
                            .foregroundStyle(Theme.label3)
                            .lineLimit(expanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(notice.bank.displayName) · \(DateText.time(notice.date))")
                            .titan(.meta)
                            .foregroundStyle(Theme.label3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.label3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(.top, -8)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
                .padding(.leading, Theme.Space.gutter + tileSize + 14)
                .opacity(isLast ? 0 : 1)
        }
        .gatedContextMenu(privateTitle: "Aviso sin leer") {
            Button("Borrar", systemImage: "trash", role: .destructive, action: onDelete)
        } preview: {
            HStack(alignment: .top, spacing: 14) {
                MerchantTile(image: nil, symbol: "questionmark", size: tileSize, symbolColor: Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No se pudo leer este aviso")
                        .titan(.row)
                        .foregroundStyle(Theme.label)
                    Text(shownText)
                        .titan(.subtitle)
                        .foregroundStyle(Theme.label3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(notice.bank.displayName) · \(DateText.time(notice.date))")
                        .titan(.meta)
                        .foregroundStyle(Theme.label3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No se pudo leer este aviso. \(spokenText). \(notice.bank.displayName), \(DateText.moment(notice.date))")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(expanded ? "Toca para resumir" : "Toca para ver el aviso entero")
        .accessibilityAction(.default) { toggle() }
        .accessibilityAction(named: "Borrar", onDelete)
    }

    private func toggle() {
        withAnimation(motion.reduce ? nil : motion.calmAnimation(.snap)) { expanded.toggle() }
    }
}

/// Ficha de 40 pt (radio 10): el logo llenándola, o un símbolo en #1C1C1E. Un filo de medio punto.
struct MerchantTile: View {
    let image: UIImage?
    let symbol: String
    var size: CGFloat = 40
    var symbolColor = Theme.monogram

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        ZStack {
            if let image {
                Color.white
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Theme.raised
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(symbolColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

extension Movement {
    /// Símbolo del monograma cuando no hay logo.
    var fallbackSymbol: String {
        let name = (merchant ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if name.contains("nomina") || name.contains("salario") { return "briefcase" }
        if name.contains("interes") { return "percent" }
        if name.contains("bizum") || name.contains("transferencia") { return "arrow.left.arrow.right" }
        if source == .wallet { return "wave.3.right" }
        if source == .bank || source == .statement { return "building.columns" }
        return kind == .income ? "arrow.down.left" : "creditcard"
    }
}
