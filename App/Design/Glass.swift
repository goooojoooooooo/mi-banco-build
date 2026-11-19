import SwiftUI

/// Cristal de la capa de navegación (ojo, lupa, campo de búsqueda, indicador del segmentado).
/// iOS 26+: Liquid Glass. iOS 18–25: material fino con un trazo blanco del 12 %.
/// Reducir transparencia: superficie opaca #1C1C1E con trazo del 15 %. Nunca sobre contenido.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(white: 0.11), in: shape)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

extension View {
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = true) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive))
    }

    /// iOS 26+: identidad para que el cristal se transforme (morph) dentro de un `GlassGroup`.
    @ViewBuilder
    func glassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Agrupa piezas de cristal hermanas en un `GlassEffectContainer` (se funden y se transforman entre sí;
/// el cristal no puede muestrear otro cristal). Antes de iOS 26, solo el contenido.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
