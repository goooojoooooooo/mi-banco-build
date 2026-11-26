import SwiftUI
import Observation
import MiBancoCore

/// Preferencias que cambian la presentación de toda la app. El modo privado (el ojo de Inicio y el interruptor de
/// Ajustes son el mismo estado) se guarda en UserDefaults; cambiarlo dentro de `withAnimation` anima cada importe.
@MainActor @Observable
final class AppPreferences {
    /// M-4: la misma clave que la carga de los avisos y la suite compartida (una sola fuente).
    nonisolated static let privateModeKey = SharedPrivacy.key

    /// Dónde se guarda el ojo: `UserDefaults.standard`. En la demo (DEBUG), un dominio propio que se siembra al arranca
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
    /// M-4: la única lectura del ojo guardado (la usan también los avisos y la Live Activity).
    nonisolated static var storedPrivateMode: Bool { SharedPrivacy.appEye(from: privateModeStore) }

    nonisolated static let pricesEnabledKey = "investmentPrices"
    nonisolated static let pricesAskedKey = "investmentPricesAsked"

    var privateMode: Bool {
        didSet {
            Self.privateModeStore.set(privateMode, forKey: Self.privateModeKey)
            Self.shareEye(privateMode)
        }
    }

    /// I-2: copia el ojo en la suite del grupo de apps (clave `privateMode`) para la extensión de avisos, y lo lleva a
    /// la Live Activity que esté en pantalla. La fuente de verdad sigue siendo la de arriba. Al cambiar y al arrancar.
    static func shareEye(_ hidden: Bool) {
        let (shared, copy, reachesLiveActivity) = sharedTarget(hidden)
        SharedPrivacy.publish(copy, to: shared)
        #if DEBUG
        let word = { (closed: Bool) in closed ? "cerrado" : "abierto" }
        LaunchProbe.shared.sharedEye = SharedPrivacy.read(from: shared).map(word) ?? "-"
        // N-3: el ojo con el que se compondría ahora un aviso (y su carga) y la Live Activity.
        LaunchProbe.shared.alertEye = word(AlertPoster.eyeClosed)
        LaunchProbe.shared.activityEye = word(LiveActivityController.eyeClosed)
        #endif
        if reachesLiveActivity { Task { await LiveActivityController.syncEye() } }
    }

    /// Dónde va la copia del ojo, qué dice y si llega a la Live Activity.
    private static func sharedTarget(_ hidden: Bool) -> (suite: UserDefaults?, copy: Bool, reachesLiveActivity: Bool) {
        #if DEBUG
        if DemoMode.isActive {
            // N-5: la demo nunca escribe en el grupo de apps de verdad ni toca la Live Activity de verdad: su copia va a
            // un dominio propio, que solo lee la sonda `ojoCompartido`. Con `-MiBancoDemoSharedEyeOpposite` esa copia
            // dice lo CONTRARIO del ojo. (N-B: la prueba N-3 falla si los avisos leyeran la suite porque la del grupo
            // de verdad, en la demo, nunca se escribe; no por esta copia, que nadie más lee.)
            let copy = DemoMode.writesOppositeSharedEye ? !hidden : hidden
            return (UserDefaults(suiteName: "DemoSharedEye"), copy, false)
        }
        #endif
        return (SharedPrivacy.suite(infoDictionary: Bundle.main.infoDictionary), hidden, true)
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
        let storedEye = Self.storedPrivateMode
        privateMode = storedEye
        Self.shareEye(storedEye)
        #if DEBUG
        if DemoMode.isActive {
            motionLevel = DemoMode.motionLevelOverride ?? Self.defaultMotionLevel
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
        #if DEBUG
        motionLevel = DemoMode.motionLevelOverride ?? stored ?? Self.defaultMotionLevel
        #else
        motionLevel = stored ?? Self.defaultMotionLevel
        #endif
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

/// El patrón de privacidad para un importe (o una cantidad) que es texto: con el ojo cerrado el texto real
/// NO se monta — se dibuja su máscara —, porque un texto que solo va difuminado lo siguen leyendo
/// las pruebas de toque y cualquier cliente de accesibilidad. Sin transición de contenido (la cifra no se funde con la
/// máscara), marcado como dato privado, y VoiceOver dice «importe oculto».
struct MaskedText: View {
    /// El texto con el ojo abierto.
    let shown: String
    /// Lo que se dibuja con el ojo cerrado (no depende de las cifras).
    let mask: String
    /// Lo que dice VoiceOver con el ojo abierto.
    let spoken: String
    let hidden: Bool

    /// Un importe en euros: «12,50 €» ↔ «•••,•• €».
    init(cents: Int, sign: Bool = false, hidden: Bool) {
        shown = sign ? signedEUR(cents) : formatEUR(cents).replacingOccurrences(of: "-", with: "−")
        mask = maskedEUR(cents, sign: sign)
        spoken = spokenAmount(cents, hidden: false)
        self.hidden = hidden
    }

    /// Cualquier otro dato privado (un precio, unas acciones): la máscara es «•••,•• €» si el texto lleva «€» y
    /// «•••» si no; `unit` se conserva detrás («••• acc.»).
    init(_ shown: String, unit: String = "", spoken: String? = nil, hidden: Bool) {
        self.shown = shown
        mask = (shown.contains("€") ? "•••,••\u{00A0}€" : "•••") + unit
        self.spoken = spoken ?? shown
        self.hidden = hidden
    }

    var body: some View {
        Text(hidden ? mask : shown)
            .contentTransition(.identity)
            .privacySensitive()
            .accessibilityLabel(hidden ? "importe oculto" : spoken)
    }
}

/// "340,20 euros" o "importe oculto": lo que dice VoiceOver de un importe según el modo privado.
func spokenAmount(_ cents: Int, hidden: Bool) -> String {
    hidden ? "importe oculto" : formatEUR(cents).replacingOccurrences(of: "\u{00A0}€", with: " euros")
}
