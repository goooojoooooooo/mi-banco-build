import SwiftUI

/// Barra fija de Inicio, como en la maqueta aprobada: a la izquierda la marca con el nombre de la app (la ranura a la que
/// vuela la marca del arranque; tocarla abre «Tu resumen») y a la derecha dos controles de cristal (ojo y lupa) en un
/// mismo `GlassEffectContainer`. La lupa se transforma en el campo de búsqueda (en iOS 26, el cristal se funde de una
/// forma a otra con `glassEffectID`; antes, un fundido con escala). El título «Tu dinero» va con el contenido
/// (`HomeTitle`) y se desliza bajo la barra.
struct HomeTopBar: View {
    @Binding var searching: Bool
    @Binding var query: String
    let motion: HomeMotion
    var openBriefing: () -> Void = {}

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @Namespace private var glass
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15

    var body: some View {
        let hidden = preferences.privateMode
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if searching {
                    searchField
                    Button(action: cancel) {
                        Text("Cancelar")
                            .titan(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.label)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .glassSurface(Capsule())
                            .glassID("cancel", in: glass)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                } else {
                    brand
                        .homeEntrance(.brand)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                    Button(action: togglePrivacy) {
                        Image(systemName: hidden ? "eye.slash" : "eye")
                            .font(.system(size: 18, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Theme.label)
                            .frame(width: 44, height: 44)
                            .glassSurface(Circle())
                            .glassID("eye", in: glass)
                            .contentShape(Circle())
                    }
                    // Cristal que reacciona: se hunde a 0,88 y rebota al soltar (el cristal en sí no es interactivo).
                    .buttonStyle(.glassPress)
                    .homeEntrance(.buttons)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel(hidden ? "Mostrar importes" : "Ocultar importes")
                    .accessibilityValue(hidden ? "Importes ocultos" : "Importes visibles")
                    Button(action: startSearch) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.label)
                            .frame(width: 44, height: 44)
                            .glassSurface(Circle())
                            .glassID("search", in: glass)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.glassPress)
                    .homeEntrance(.buttons)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel("Buscar movimientos")
                }
            }
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            TopEdgeFade(motion: motion)
                .padding(.bottom, -36)
                .ignoresSafeArea(edges: .top)
        }
        .sensoryFeedback(Haptics.toggle, trigger: hidden)
        .onChange(of: searching) { _, on in
            fieldFocused = on
        }
    }

    /// La ranura de la marca: la pieza negra de 30 pt y el nombre en mayúsculas, 15 pt seminegrita con 0,18 em entre
    /// letras. Su marco (marca + nombre, sin el margen del botón) es el destino del vuelo del arranque
    /// (`.launchBrandSlot()`). Es el botón de «Tu resumen»: antes era la misma marca dentro de un círculo de cristal.
    private var brand: some View {
        Button(action: openBriefing) {
            HStack(spacing: 10) {
                AppMark(size: 30)
                Text(AppIdentity.displayName.uppercased())
                    .font(.system(size: nameSize, weight: .semibold))
                    .tracking(nameSize * 0.18)
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
            }
            .launchBrandSlot()
            .padding(.trailing, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        // El nombre no crece sin límite: comparte fila con los dos botones.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel("Tu resumen")
        .accessibilityIdentifier("home-briefing-button")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.label2)
                .accessibilityHidden(true)
            TextField("Comercio, banco, nota o importe", text: $query)
                .titan(.body)
                .foregroundStyle(Theme.label)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.label3)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Borrar la búsqueda")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassSurface(Capsule())
        .glassID("search", in: glass)
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
        .onAppear { fieldFocused = true }
    }

    private func togglePrivacy() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.privacy) {
            preferences.privateMode.toggle()
        }
        AccessibilityNotification.Announcement(preferences.privateMode ? "Importes ocultos" : "Importes visibles").post()
    }

    private func startSearch() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph) { searching = true }
    }

    private func cancel() {
        fieldFocused = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.Motion.morph) {
            searching = false
            query = ""
        }
    }
}

/// «Tu dinero»: el título grande de Inicio. Va con el contenido, encima del carrusel, y se desliza bajo la barra al
/// bajar la lista (como en la maqueta aprobada).
struct HomeTitle: View {
    var body: some View {
        Text("Tu dinero")
            .titan(.homeTitle)
            .foregroundStyle(Theme.label)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.gutter)
            .padding(.top, 4)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}
