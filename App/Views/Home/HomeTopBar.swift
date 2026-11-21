import SwiftUI

/// Barra fija de Inicio: "Tu dinero" y dos controles de cristal (ojo y lupa) en un mismo `GlassEffectContainer`.
/// La lupa se transforma en el campo de búsqueda (en iOS 26, el cristal se funde de una forma a otra con
/// `glassEffectID`; antes, un fundido con escala). El título se compacta un poco al bajar la lista.
struct HomeTopBar: View {
    @Binding var searching: Bool
    @Binding var query: String
    let motion: HomeMotion
    var openBriefing: () -> Void = {}

    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var fieldFocused: Bool
    @Namespace private var glass

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
                    Text("Tu dinero")
                        .titan(.homeTitle)
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .modifier(TitleCompression(motion: motion, enabled: !reduceMotion))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .transition(.opacity)
                    Button(action: openBriefing) {
                        AppMark(size: 22)
                            .frame(width: 44, height: 44)
                            .glassSurface(Circle())
                            .glassID("briefing", in: glass)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    .accessibilityLabel("Tu resumen")
                    .accessibilityIdentifier("home-briefing-button")
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
                    .buttonStyle(.pressable)
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
                    .buttonStyle(.pressable)
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
