import SwiftUI
import Observation
import MiBancoCore

/// Preferencias que cambian la presentación de toda la app. El modo privado (el ojo de Inicio y el interruptor de
/// Ajustes son el mismo estado) se guarda en UserDefaults; cambiarlo dentro de `withAnimation` anima cada importe.
@MainActor @Observable
final class AppPreferences {
    nonisolated static let privateModeKey = "privateMode"
    nonisolated static let pricesEnabledKey = "investmentPrices"
    nonisolated static let pricesAskedKey = "investmentPricesAsked"

    var privateMode: Bool {
        didSet {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            UserDefaults.standard.set(privateMode, forKey: Self.privateModeKey)
        }
    }

    /// Permiso para consultar precios diarios en Yahoo Finance (solo ISIN/símbolo; apagado por defecto).
    var pricesEnabled: Bool {
        didSet {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            UserDefaults.standard.set(pricesEnabled, forKey: Self.pricesEnabledKey)
        }
    }

    /// Si ya se ha mostrado y respondido la pregunta inicial de precios en Ajustes › Inversiones.
    var pricesAsked: Bool {
        didSet {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            UserDefaults.standard.set(pricesAsked, forKey: Self.pricesAskedKey)
        }
    }

    init() {
        #if DEBUG
        if DemoMode.isActive {
            privateMode = DemoMode.startsPrivate
            pricesEnabled = false
            pricesAsked = DemoMode.asksPrices ? false : DemoMode.includesPortfolio
            return
        }
        #endif
        privateMode = UserDefaults.standard.bool(forKey: Self.privateModeKey)
        pricesEnabled = UserDefaults.standard.bool(forKey: Self.pricesEnabledKey)
        pricesAsked = UserDefaults.standard.bool(forKey: Self.pricesAskedKey)
    }
}

/// Un importe que el modo privado oculta: desenfoque de 9 pt (proporcional al tamaño) + opacidad 0,75, como la maqueta.
/// Solo se animan opacidad y desenfoque de un texto corto, nunca el de una lista entera; VoiceOver deja de leer la cifra.
private struct PrivateAmount: ViewModifier {
    let radius: CGFloat
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        let hidden = preferences.privateMode
        content
            .blur(radius: hidden ? radius : 0, opaque: false)
            .opacity(hidden ? 0.75 : 1)
            .privacySensitive()
            .accessibilityHidden(hidden)
    }
}

/// Un importe con etiqueta explícita (U8): oculta visualmente en modo privado y sustituye la etiqueta por «importe oculto»
/// en el propio texto, sin ocultar el nodo (así VoiceOver lee «importe oculto» y XCUITest nunca ve «€» ni «%»).
private struct PrivateAmountSpoken: ViewModifier {
    let spoken: String
    let radius: CGFloat
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        let hidden = preferences.privateMode
        content
            .blur(radius: hidden ? radius : 0, opaque: false)
            .opacity(hidden ? 0.75 : 1)
            .privacySensitive()
            .accessibilityLabel(hidden ? "importe oculto" : spoken)
    }
}

/// Un campo editable con un importe (saldos, umbrales): con el modo privado se difumina solo mientras no se edita,
/// y nunca se oculta a VoiceOver (tiene que poder encontrarse y editarse).
private struct PrivateField: ViewModifier {
    let editing: Bool
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        let hidden = preferences.privateMode && !editing
        content
            .blur(radius: hidden ? 9 : 0, opaque: false)
            .opacity(hidden ? 0.75 : 1)
            .privacySensitive()
    }
}

extension View {
    /// `radius`: 9 para importes de fila, más para las cifras grandes.
    func privateAmount(radius: CGFloat = 9) -> some View { modifier(PrivateAmount(radius: radius)) }

    /// Variante U8 con etiqueta hablada explícita («importe oculto» cuando el ojo está cerrado).
    func privateAmount(spoken: String, radius: CGFloat = 9) -> some View {
        modifier(PrivateAmountSpoken(spoken: spoken, radius: radius))
    }

    /// Para campos de texto con importe: ver `PrivateField`.
    func privateField(editing: Bool) -> some View { modifier(PrivateField(editing: editing)) }
}

/// "340,20 euros" o "importe oculto": lo que dice VoiceOver de un importe según el modo privado.
func spokenAmount(_ cents: Int, hidden: Bool) -> String {
    hidden ? "importe oculto" : formatEUR(cents).replacingOccurrences(of: "\u{00A0}€", with: " euros")
}
