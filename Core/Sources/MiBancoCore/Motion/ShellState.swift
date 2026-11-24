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
/// - el bloqueo solo lo quita `unlockSucceeded`.
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

    /// Si se desbloqueara ahora mismo, la marca echaría a volar en ese instante (la escena está activa). El bloqueo
    /// lo pregunta para soltar su marca justo cuando la que vuela la releva.
    public var fliesOnUnlock: Bool { showsLock && scene == .active }

    /// Las capas que hay ahora, de abajo arriba. La última es la que se ve encima.
    public var layers: [Layer] {
        var layers: [Layer] = [.home]
        if showsLock { layers.append(.lock) } else if showsLaunch { layers.append(.launch) }
        if shownExit != nil { layers.append(.exit) }
        if showsCover { layers.append(.cover) }
        return layers
    }

    /// La capa de arriba del todo es opaca (bloqueo o tapa): debajo no se ve nada.
    public var isCoveredOpaquely: Bool { showsLock || showsCover }

    /// Cómo entra y sale cada capa. Solo se anima UNA cosa: el bloqueo al quitarse (un fundido). Todo lo demás aparece y
    /// desaparece de golpe: el bloqueo y la tapa al ponerse (la captura del selector de apps nunca pilla nada a medias),
    /// la tapa al quitarse (sin destello) y las capas del arranque (ya son transparentes cuando se quitan).
    public static func animatesInsertion(of layer: Layer) -> Bool { false }
    public static func animatesRemoval(of layer: Layer) -> Bool { layer == .lock }

    // MARK: Lo que pasa

    public mutating func apply(_ event: Event) {
        switch event {
        case .unlockSucceeded:
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
                startExit(cold: cold)
            } else {
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
