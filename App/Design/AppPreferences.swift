import SwiftUI
import Observation
import MiBancoCore

/// Preferencias que cambian la presentación de toda la app. El modo privado (el ojo de Inicio y el interruptor de
/// Ajustes son el mismo estado) se guarda en UserDefaults; cambiarlo dentro de `withAnimation` anima cada importe.
@MainActor @Observable
final class AppPreferences {
    static let privateModeKey = "privateMode"

    var privateMode: Bool {
        didSet {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            UserDefaults.standard.set(privateMode, forKey: Self.privateModeKey)
        }
    }

    init() {
        #if DEBUG
        if DemoMode.isActive {
            privateMode = DemoMode.startsPrivate
            // La demo no guarda nada, salvo la prueba de reinicio de la guía (`-MiBancoDemoPersistGuide`).
            if DemoMode.persistsGuideProgress {
                if DemoMode.resetsGuideProgress { UserDefaults.standard.removeObject(forKey: Self.guideStepKey) }
                guideLastStep = Self.storedGuideSteps()
            } else {
                guideLastStep = DemoMode.guideProgressSeed
            }
            return
        }
        #endif
        privateMode = UserDefaults.standard.bool(forKey: Self.privateModeKey)
        guideLastStep = Self.storedGuideSteps()
    }

    // MARK: Guía de avisos: el último paso de cada guía

    static let guideStepKey = "guideLastStep"

    /// Último paso (desde 0) en que se quedó cada guía de Atajos, por `GuideTrack.rawValue`. Vive aquí y no en el libro:
    /// es una preferencia del aparato, y iOS puede cerrar la app mientras él está en Atajos. Se lee con tolerancia.
    /// Se guarda con el número de pasos que tenía la guía («8/22» = paso 9 de 22): si la guía cambia de largo, no se retoma.
    private(set) var guideLastStep: [String: String]

    func guideResume(_ track: GuideTrack) -> Int? {
        guideResumeIndex(saved: GuideSavedStep(stored: guideLastStep[track.rawValue]), total: guideSteps(for: track).count)
    }

    /// Guarda el paso al que llega una guía; en el primero (o al terminar) no queda nada que retomar.
    func setGuideStep(_ track: GuideTrack, _ index: Int?) {
        if let index, index > 0 {
            guideLastStep[track.rawValue] = GuideSavedStep(step: index, of: guideSteps(for: track).count).stored
        } else {
            guideLastStep.removeValue(forKey: track.rawValue)
        }
        #if DEBUG
        if DemoMode.isActive && !DemoMode.persistsGuideProgress { return }
        #endif
        UserDefaults.standard.set(guideLastStep, forKey: Self.guideStepKey)
    }

    /// Lo guardado con la forma antigua (un número suelto) se descarta al leerlo: no hay retoma.
    private static func storedGuideSteps() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: guideStepKey)?.compactMapValues { $0 as? String } ?? [:]
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

    /// Para campos de texto con importe: ver `PrivateField`.
    func privateField(editing: Bool) -> some View { modifier(PrivateField(editing: editing)) }
}

/// "340,20 euros" o "importe oculto": lo que dice VoiceOver de un importe según el modo privado.
func spokenAmount(_ cents: Int, hidden: Bool) -> String {
    hidden ? "importe oculto" : formatEUR(cents).replacingOccurrences(of: "\u{00A0}€", with: " euros")
}
