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
                                zoom: zoom) { onOpen(m.id) }
            case .unread(let n):
                UnreadRowView(notice: n, isLast: isLast) { onDeleteUnread(n.id) }
            }
        }
    }
}

/// Fila de 64 pt: logo (o monograma), comercio y subtítulo, importe a la derecha (verde con "+" si entra).
/// Al tocar (no al soltar): fondo #141416 y escala 0,985; abre el detalle con el logo como elemento compartido.
struct MovementRowView: View {
    let movement: Movement
    let row: ListRow
    let logoDomain: String?
    var isLast = false
    var isFresh = false
    let zoom: Namespace.ID
    let onOpen: () -> Void

    @Environment(MerchantLogos.self) private var logos
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    var body: some View {
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
                HStack(spacing: 6) {
                    Text(signedEUR(movement.amountCents))
                        .titan(.row)
                        .foregroundStyle(amountColor)
                        .strikethrough(movement.flaggedNotMine, color: Theme.label3)
                        .lineLimit(1)
                        .fixedSize()
                        .privateAmount()
                    if isFresh && movement.amountCents > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.income)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
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
        .animation(Theme.Motion.morph, value: isFresh)
        .animation(Theme.Motion.quick, value: movement.flaggedNotMine)
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
                Text(signedEUR(movement.amountCents))
                    .titan(.row)
                    .foregroundStyle(amountColor)
                    .strikethrough(movement.flaggedNotMine, color: Theme.label3)
                    .lineLimit(1)
                    .fixedSize()
                    .privateAmount()
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

private struct LogoTaskID: Equatable {
    let merchant: String?
    let downloads: Bool
}

/// Aviso con importe que Mi Banco no supo leer: tus cifras pueden no estar al día, así que se ve como una fila.
/// Muestra su texto (2 líneas, se amplía al tocar) y se borra con la ✕.
struct UnreadRowView: View {
    let notice: UnreadNotice
    var isLast = false
    let onDelete: () -> Void

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        withAnimation(reduceMotion ? nil : Theme.Motion.quick) { expanded.toggle() }
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
