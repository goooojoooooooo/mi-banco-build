import Foundation

/// Las decisiones de la carcasa de la app, sin SwiftUI, para poder probarlas TODAS en Linux: qué hay encima de qué
/// (bloqueo, tapa del selector de apps, arranque, marca que vuela, Inicio) y cómo cambia con cada cosa que pasa.
///
/// Esto NO autentica a nadie: Face ID sigue en `LockView`. Aquí solo entra el resultado (`unlockSucceeded`) y sale lo
/// que hay que dibujar. Reglas que este tipo hace cumplir y que sus pruebas recorren en todos los estados alcanzables:
/// - con la escena fuera de primer plano, arriba del todo hay siempre algo opaco: el bloqueo o la tapa — con el
///   bloqueo activado o sin él (la captura del selector de apps nunca enseña dinero);
/// - el arranque y la marca que vuela nunca existen con el bloqueo puesto;
/// - el arranque solo ocurre una vez por vida de la app: volver de segundo plano no lo repite;
/// - Inicio se monta por capas una sola vez por desbloqueo, en el instante del desbloqueo (debajo de la tapa si la
///   escena aún no está activa), nunca después de haberse visto ya montado; solo el vuelo de la marca espera a
///   primer plano;
/// - el bloqueo solo lo quita `unlockSucceeded`;
/// - al desbloquear, el bloqueo solo se funde si la escena está activa; si no, lo releva la tapa de golpe, de modo que
///   la marca que espera a primer plano para volar nunca arranca sobre un bloqueo a medio fundir;
/// - mientras el bloqueo se funde, Inicio no recibe toques;
/// - con el bloqueo activado, la app nunca está desbloqueada en segundo plano: un éxito de la autenticación que llegue
///   con la escena ya en segundo plano se ignora (la app sigue bloqueada y vuelve a pedirlo al volver).
public struct ShellState: Equatable, Hashable, Sendable {
    /// La fase de la escena, como la da el sistema.
    public enum Scene: Hashable, Sendable, CaseIterable {
        case active, inactive, background
    }

    /// Lo que puede pasar.
    public enum Event: Hashable, Sendable {
        /// La autenticación ha salido bien (o el bloqueo de demo ha cumplido su tiempo).
        case unlockSucceeded
        /// El sistema cambia la fase de la escena.
        case scene(Scene)
        /// El arranque sin bloqueo llega a su segundo 0,78 (o se salta con un toque): Inicio empieza a montarse.
        case launchAssembled
        /// El arranque sin bloqueo ha terminado: su capa se quita.
        case launchFinished
        /// El respaldo de 1,5 s del arranque.
        case safetyFired
        /// La marca que volaba ha llegado (o no había de dónde ni a dónde volar).
        case exitFinished(id: Int)
        /// Cambia el ajuste del bloqueo: si el bloqueo se enseña cuando toca y si la app se bloquea al ir a segundo plano.
        case lockSettingChanged(lockApplies: Bool, relocksOnBackground: Bool)
        /// El fundido `id` (`fadeCount` cuando empezó) con el que se iba el bloqueo, ya desbloqueado, ha terminado: ya
        /// no queda nada suyo en pantalla. El aviso de un fundido anterior no da por acabado uno posterior.
        case lockFadeFinished(id: Int)
    }

    /// Cómo deja la pantalla el bloqueo al desbloquear.
    public enum LockExit: Hashable, Sendable {
        /// Se funde sobre Inicio (es lo único que se anima en la carcasa).
        case fades
        /// Se quita de golpe: la tapa del selector de apps se pone encima en esa misma actualización.
        case covered
    }

    /// La marca del bloqueo volando a su ranura de la barra superior.
    public struct Exit: Hashable, Sendable {
        public let id: Int
        /// Es el desbloqueo del arranque en frío: cruzan además las bandas.
        public let cold: Bool
    }

    /// Las capas, de abajo arriba.
    public enum Layer: Hashable, Sendable, CaseIterable {
        case home, launch, lock, exit, cover
    }

    // MARK: Estado

    /// El bloqueo se enseña cuando la app está bloqueada (el ajuste; en la demo, su bandera).
    public internal(set) var lockApplies: Bool
    /// La app se bloquea al ir a segundo plano (el ajuste).
    public internal(set) var relocksOnBackground: Bool
    public internal(set) var locked = true
    public internal(set) var scene = Scene.active
    /// Arranque en frío sin bloqueo delante: su capa está puesta hasta que termina. Solo es `true` al principio.
    public internal(set) var launching = true
    /// Inicio aún no se ha enseñado ni una vez desde que se abrió la app.
    public internal(set) var coldStart = true
    /// Sube cada vez que Inicio debe montarse por capas.
    public internal(set) var revealToken = 0
    /// Se desbloqueó con la escena aún inactiva: la marca volará al volver a primer plano (`true` = arranque en frío).
    public internal(set) var pendingFlight: Bool?
    public internal(set) var exit: Exit?
    public internal(set) var exitCount = 0
    /// El bloqueo, ya desbloqueado, se está fundiendo sobre Inicio. Dura lo que el fundido (`lockFadeFinished`).
    public internal(set) var lockFading = false
    /// Cuántos fundidos del bloqueo han empezado: el número del último es el que acepta `lockFadeFinished(id:)`.
    public internal(set) var fadeCount = 0
    /// Un cambio del ajuste que llegó con el bloqueo delante: se aplica al desbloquear (nunca quita el bloqueo).
    var settingAfterUnlock: Setting?

    struct Setting: Hashable, Sendable {
        let lockApplies: Bool
        let relocksOnBackground: Bool
    }

    public init(lockApplies: Bool, relocksOnBackground: Bool) {
        self.lockApplies = lockApplies
        self.relocksOnBackground = relocksOnBackground
    }

    // MARK: Lo que se dibuja

    /// El bloqueo está delante.
    public var showsLock: Bool { locked && lockApplies }

    /// La tapa opaca del selector de apps: siempre que la escena no esté activa y el bloqueo no esté ya delante,
    /// con el bloqueo activado o sin él. Nunca va encima del bloqueo (así no tapa su botón ni su marca).
    public var showsCover: Bool { Self.showsCover(scene: scene, showsLock: showsLock) }

    /// La misma regla para quien la calcula con la fase de escena de este mismo instante (la vista la lee del entorno,
    /// para que la tapa esté puesta en la misma actualización en que cambia la fase).
    public static func showsCover(scene: Scene, showsLock: Bool) -> Bool {
        scene != .active && !showsLock
    }

    /// La capa del arranque (solo sin bloqueo delante).
    public var showsLaunch: Bool { launching && !showsLock }

    /// La marca que vuela (solo sin bloqueo delante).
    public var shownExit: Exit? { showsLock ? nil : exit }

    /// El bloqueo monta las piezas sobre su marca (arranque en frío) o sale con la marca quieta (re-bloqueo).
    public var lockPlaysLaunch: Bool { coldStart }

    /// Inicio no se toca ni se lee con el bloqueo delante.
    public var hidesHome: Bool { showsLock }

    /// VoiceOver no lee Inicio con el bloqueo delante ni mientras el arranque sin bloqueo sigue en negro (Inicio aún no
    /// se ha montado: la pantalla no enseña lo que leería).
    public var hidesHomeFromVoiceOver: Bool { showsLock || (showsLaunch && coldStart) }

    /// Un éxito de la autenticación se acepta ahora mismo: en segundo plano no (la app seguiría desbloqueada sin
    /// ningún paso posterior por segundo plano que la volviera a bloquear). El bloqueo lo pregunta antes de irse.
    public var acceptsUnlock: Bool { scene != .background }

    /// Si se desbloqueara ahora mismo, la marca echaría a volar en ese instante (la escena está activa). Es lo mismo
    /// que `lockExitOnUnlock == .fades`, que es lo que pregunta el bloqueo.
    public var fliesOnUnlock: Bool { showsLock && scene == .active }

    /// Si se desbloqueara ahora mismo, cómo se iría el bloqueo (nil: no hay bloqueo delante, o está en segundo plano y
    /// no se iría: ver `acceptsUnlock`). En primer plano se funde
    /// sobre Inicio. Fuera de primer plano (Face ID aún tiene la escena inactiva) se quita de golpe: la tapa se pone
    /// encima en esa misma actualización, y así no queda debajo un bloqueo a medio fundir que asome —con su marca, su
    /// lema y su botón— si la escena vuelve a activa antes de que el fundido hubiera acabado.
    public var lockExitOnUnlock: LockExit? {
        guard showsLock, acceptsUnlock else { return nil }
        return scene == .active ? .fades : .covered
    }

    /// Inicio recibe los toques: ni con el bloqueo delante ni mientras el bloqueo, ya desbloqueado, se está fundiendo
    /// (un toque tardío sobre «Desbloquear» caería en la barra de pestañas que hay justo debajo).
    public var homeTakesTouches: Bool { !showsLock && !lockFading }

    /// Las capas que hay ahora, de abajo arriba. La última es la que se ve encima.
    public var layers: [Layer] { layers(liveScene: scene) }

    /// Las mismas capas para quien dibuja: la tapa se decide con la fase de escena de este mismo instante (la vista la
    /// lee del entorno). La vista pinta exactamente esta lista, a la altura que dice `zIndex(of:)`.
    public func layers(liveScene: Scene) -> [Layer] {
        var layers: [Layer] = [.home]
        if showsLock { layers.append(.lock) } else if showsLaunch { layers.append(.launch) }
        if shownExit != nil { layers.append(.exit) }
        if Self.showsCover(scene: liveScene, showsLock: showsLock) { layers.append(.cover) }
        return layers
    }

    /// La altura de cada capa: la vista la usa tal cual. El bloqueo y el arranque nunca coinciden; la marca que vuela
    /// va por encima del bloqueo solo mientras este, ya desbloqueado, se funde; la tapa, encima de todo.
    public static func zIndex(of layer: Layer) -> Double {
        switch layer {
        case .home: 0
        case .launch, .lock: 1
        case .exit: 2
        case .cover: 3
        }
    }

    /// La capa de arriba del todo es opaca (bloqueo o tapa): debajo no se ve nada.
    public var isCoveredOpaquely: Bool { showsLock || showsCover }

    /// Cómo entra y sale cada capa. Solo se anima UNA cosa: el bloqueo al quitarse (un fundido, y solo si se desbloquea
    /// en primer plano: ver `lockExitOnUnlock`). Todo lo demás aparece y
    /// desaparece de golpe: el bloqueo y la tapa al ponerse (la captura del selector de apps nunca pilla nada a medias),
    /// la tapa al quitarse (sin destello) y las capas del arranque (ya son transparentes cuando se quitan).
    public static func animatesInsertion(of layer: Layer) -> Bool { false }
    public static func animatesRemoval(of layer: Layer) -> Bool { layer == .lock }

    // MARK: Lo que pasa

    public mutating func apply(_ event: Event) {
        switch event {
        case .unlockSucceeded:
            // En segundo plano no se desbloquea: ya no habría otro paso por segundo plano que volviera a bloquear.
            guard acceptsUnlock else { return }
            let lockWasShowing = showsLock
            let cold = coldStart
            locked = false
            launching = false
            if let setting = settingAfterUnlock {
                lockApplies = setting.lockApplies
                relocksOnBackground = setting.relocksOnBackground
                settingAfterUnlock = nil
            }
            guard lockWasShowing else { return }
            coldStart = false
            // Inicio se monta YA, esté o no la escena en primer plano (si no lo está, debajo de la tapa).
            revealToken += 1
            if scene == .active {
                // El bloqueo se funde sobre Inicio y la marca echa a volar en este instante.
                lockFading = true
                fadeCount += 1
                startExit(cold: cold)
            } else {
                // La tapa releva al bloqueo de golpe (no hay fundido); la marca volará al volver a primer plano.
                pendingFlight = cold
            }

        case .scene(let new):
            scene = new
            switch new {
            case .active:
                // Se desbloqueó con la escena inactiva: ahora sí vuela la marca. Inicio NO se vuelve a montar.
                if let cold = pendingFlight, !showsLock {
                    pendingFlight = nil
                    startExit(cold: cold)
                }
            case .inactive:
                leaveForeground()
            case .background:
                leaveForeground()
                // Tras pasar por segundo plano ya no hay vuelo pendiente (con bloqueo, además, la app se bloquea).
                pendingFlight = nil
                if relocksOnBackground { locked = true }
                // El bloqueo vuelve a estar delante, entero: del que se fundía no queda nada.
                if showsLock { lockFading = false }
            }

        case .launchAssembled:
            assembleHomeOnce()

        case .launchFinished, .safetyFired:
            guard showsLaunch else { return }
            finishLaunch()

        case .exitFinished(let id):
            if exit?.id == id { exit = nil }

        case .lockSettingChanged(let applies, let relocks):
            // Con el bloqueo delante el ajuste no puede quitarlo: se guarda y se aplica al desbloquear.
            guard !showsLock else {
                settingAfterUnlock = Setting(lockApplies: applies, relocksOnBackground: relocks)
                return
            }
            lockApplies = applies
            relocksOnBackground = relocks
            // Cambiar el ajuste solo es posible con la app ya desbloqueada: no se vuelve a pedir Face ID.
            locked = false
            launching = false
            // Salvo en segundo plano (no se puede provocar desde la interfaz): ahí manda la regla de siempre, y con el
            // bloqueo activado la app queda bloqueada.
            if scene == .background, relocksOnBackground {
                locked = true
                if showsLock { lockFading = false }
            }

        case .lockFadeFinished(let id):
            if id == fadeCount { lockFading = false }
        }
    }

    /// Fuera de primer plano no sigue ni la marca volando ni el arranque sin bloqueo.
    private mutating func leaveForeground() {
        exit = nil
        if showsLaunch { finishLaunch() }
    }

    private mutating func assembleHomeOnce() {
        guard coldStart, showsLaunch else { return }
        coldStart = false
        revealToken += 1
    }

    private mutating func finishLaunch() {
        assembleHomeOnce()
        launching = false
    }

    private mutating func startExit(cold: Bool) {
        exitCount += 1
        exit = Exit(id: exitCount, cold: cold)
    }
}
