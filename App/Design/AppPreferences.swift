import SwiftUI
import Observation
import MiBancoCore

/// Preferencias que cambian la presentación de toda la app. El modo privado (el ojo de Inicio y el interruptor de
/// Ajustes son el mismo estado) se guarda en UserDefaults; cambiarlo dentro de `withAnimation` anima cada importe.
@MainActor @Observable
final class AppPreferences {
    nonisolated static let privateModeKey = "privateMode"

    /// Dónde se guarda el ojo: `UserDefaults.standard`. En la demo (DEBUG), un dominio propio que se siembra al arrancar
    /// con `-MiBancoDemoPrivate`, para que la demo nunca toque el ojo del dueño y, aun así, quien observe lo guardado
    /// (`RollingAmount` sin preferencias) lo vea cambiar en vivo.
    nonisolated(unsafe) static let privateModeStore: UserDefaults = {
        #if DEBUG
        if DemoMode.isActive, let demo = UserDefaults(suiteName: "MiBancoDemoPreferences") {
            demo.set(DemoMode.startsPrivate, forKey: privateModeKey)
            return demo
        }
        #endif
        return .standard
    }()

    /// El modo privado guardado (la misma clave y el mismo almacén que lee `init`): para quien no tiene las preferencias
    /// en el entorno y aun así nunca debe enseñar un importe que el dueño tiene oculto.
    static var storedPrivateMode: Bool { privateModeStore.bool(forKey: privateModeKey) }

    nonisolated static let pricesEnabledKey = "investmentPrices"
    nonisolated static let pricesAskedKey = "investmentPricesAsked"

    var privateMode: Bool {
        didSet { Self.privateModeStore.set(privateMode, forKey: Self.privateModeKey) }
    }

    static let motionLevelKey = "motionLevel"
    /// Intensidad con la que se estrena la app (el dueño aprobó el movimiento en «Expresivo»): una sola constante.
    static let defaultMotionLevel = MotionLevel.expressive

    /// Intensidad del movimiento (Ajustes › Animaciones). Se guarda en UserDefaults.
    var motionLevel: MotionLevel {
        didSet {
            #if DEBUG
            if DemoMode.isActive { return }
            #endif
            UserDefaults.standard.set(motionLevel.rawValue, forKey: Self.motionLevelKey)
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
        let stored = UserDefaults.standard.string(forKey: Self.motionLevelKey).flatMap(MotionLevel.init(rawValue:))
        privateMode = Self.storedPrivateMode
        #if DEBUG
        if DemoMode.isActive {
            motionLevel = Self.defaultMotionLevel
            pricesEnabled = false
            pricesAsked = DemoMode.asksPrices ? false : DemoMode.includesPortfolio
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
        motionLevel = stored ?? Self.defaultMotionLevel
        pricesEnabled = UserDefaults.standard.bool(forKey: Self.pricesEnabledKey)
        pricesAsked = UserDefaults.standard.bool(forKey: Self.pricesAskedKey)
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
