import Testing
@testable import MiBancoCore

/// Las decisiones de la carcasa (bloqueo, tapa del selector de apps, arranque, marca que vuela) recorridas en TODOS
/// los estados alcanzables y con todos los sucesos, en Linux. En la app, la demo de las pruebas de toque no tiene fase
/// de escena de verdad: esto es lo que la cubre.
@Suite struct ShellStateTests {
    typealias Event = ShellState.Event

    /// Bloqueo que se enseña / app que se bloquea al ir a segundo plano. En la app real los dos valen lo mismo (el
    /// ajuste); en la demo pueden diferir. Se recorren las cuatro combinaciones.
    private static let settings: [(applies: Bool, relocks: Bool)] = [(true, true), (false, false), (true, false), (false, true)]

    private static func events(from state: ShellState) -> [Event] {
        var events: [Event] = [
            .unlockSucceeded, .scene(.active), .scene(.inactive), .scene(.background),
            .launchAssembled, .launchFinished, .safetyFired,
            .exitFinished(id: state.exitCount), .exitFinished(id: state.exitCount - 1),
        ]
        for setting in settings {
            events.append(.lockSettingChanged(lockApplies: setting.applies, relocksOnBackground: setting.relocks))
        }
        return events
    }

    /// El mismo estado sin los contadores (que solo crecen): para saber si ya se visitó.
    private static func shape(_ state: ShellState) -> ShellState {
        var copy = state
        copy.revealToken = 0
        copy.exitCount = 0
        if let exit = copy.exit { copy.exit = ShellState.Exit(id: 0, cold: exit.cold) }
        return copy
    }

    private struct Step: Sendable {
        let before: ShellState
        let event: Event
        let after: ShellState
    }

    /// Todas las transiciones alcanzables desde el arranque, con cualquier ajuste del bloqueo.
    private static let steps: [Step] = {
        var seen = Set<ShellState>()
        var queue: [ShellState] = []
        for setting in settings {
            let start = ShellState(lockApplies: setting.applies, relocksOnBackground: setting.relocks)
            if seen.insert(shape(start)).inserted { queue.append(start) }
        }
        var steps: [Step] = []
        var index = 0
        while index < queue.count {
            let before = queue[index]
            index += 1
            for event in events(from: before) {
                var after = before
                after.apply(event)
                steps.append(Step(before: before, event: event, after: after))
                if seen.insert(shape(after)).inserted { queue.append(after) }
            }
        }
        return steps
    }()

    private static var states: [ShellState] {
        var seen = Set<ShellState>()
        var out: [ShellState] = []
        for step in steps {
            for state in [step.before, step.after] where seen.insert(shape(state)).inserted { out.append(state) }
        }
        return out
    }

    @Test func theSearchReallyCoversTheShell() {
        // Si el recorrido se quedara en nada, las demás pruebas pasarían en vacío.
        #expect(Self.steps.count > 500)
        #expect(Self.states.count > 40)
        #expect(Self.states.contains { $0.showsLock && $0.scene == .inactive })
        #expect(Self.states.contains { $0.showsCover && !$0.lockApplies })
        #expect(Self.states.contains { $0.shownExit != nil })
        #expect(Self.states.contains { $0.pendingFlight != nil })
        #expect(Self.states.contains { $0.showsLaunch })
        #expect(Self.states.contains { !$0.showsLock && !$0.showsLaunch && $0.scene == .active && $0.exit == nil })
    }

    // MARK: (a) Fuera de primer plano, arriba hay siempre algo opaco

    @Test func outsideTheForegroundTheLockOrTheCoverIsOnTop() {
        for state in Self.states where state.scene != .active {
            #expect(state.isCoveredOpaquely, "sin tapa ni bloqueo fuera de primer plano: \(state)")
            #expect(state.showsLock != state.showsCover, "tapa y bloqueo a la vez, o ninguno: \(state)")
            #expect(state.layers.last == .lock || state.layers.last == .cover, "arriba no hay nada opaco: \(state)")
            // Y debajo no queda nada del arranque dibujándose.
            #expect(!state.showsLaunch)
            #expect(state.shownExit == nil)
        }
        // En primer plano la tapa no está nunca.
        for state in Self.states where state.scene == .active {
            #expect(!state.showsCover)
        }
    }

    @Test func theCoverNeverSitsAboveTheLock() {
        for state in Self.states {
            #expect(!(state.showsCover && state.showsLock))
        }
        for scene in ShellState.Scene.allCases {
            #expect(ShellState.showsCover(scene: scene, showsLock: true) == false)
            #expect(ShellState.showsCover(scene: scene, showsLock: false) == (scene != .active))
        }
    }

    @Test func onlyTheLockLeavingIsAnimated() {
        // La tapa entra y sale de golpe: nunca se funde con el bloqueo ni deja un destello al volver.
        #expect(ShellState.animatesInsertion(of: .cover) == false)
        #expect(ShellState.animatesRemoval(of: .cover) == false)
        // El bloqueo entra de golpe (la captura del selector de apps no lo pilla a medias) y solo se funde al quitarse.
        #expect(ShellState.animatesInsertion(of: .lock) == false)
        #expect(ShellState.animatesRemoval(of: .lock) == true)
        for layer in [ShellState.Layer.launch, .exit] {
            #expect(ShellState.animatesInsertion(of: layer) == false)
            #expect(ShellState.animatesRemoval(of: layer) == false)
        }
    }

    // MARK: (f) Sin bloqueo, la tapa también

    @Test func theCoverDoesNotDependOnTheLockSetting() {
        for scene in [ShellState.Scene.inactive, .background] {
            // Bloqueo desactivado, arranque ya terminado, la app sale de primer plano: tapa.
            var state = ShellState(lockApplies: false, relocksOnBackground: false)
            state.apply(.launchAssembled)
            state.apply(.launchFinished)
            #expect(!state.showsCover)
            state.apply(.scene(scene))
            #expect(state.showsCover, "sin bloqueo y en \(scene) no hay tapa")
            #expect(!state.showsLock)
            state.apply(.scene(.active))
            #expect(!state.showsCover)
            // Y si sale a mitad del arranque, también (el arranque se corta y queda la tapa).
            var launching = ShellState(lockApplies: false, relocksOnBackground: false)
            launching.apply(.scene(scene))
            #expect(launching.showsCover)
            #expect(!launching.showsLaunch)
        }
    }

    // MARK: (b) Nada del arranque con el bloqueo puesto

    @Test func nothingOfTheLaunchExistsWithTheLock() {
        for state in Self.states where state.showsLock {
            #expect(!state.showsLaunch)
            #expect(state.shownExit == nil)
            #expect(state.exit == nil, "queda una marca volando guardada con el bloqueo puesto: \(state)")
            #expect(state.pendingFlight == nil, "queda un vuelo pendiente con el bloqueo puesto: \(state)")
            #expect(state.hidesHome)
            #expect(state.layers.last == .lock)
        }
        for state in Self.states {
            #expect(state.hidesHome == state.showsLock)
            // La marca solo vuela en primer plano y sin bloqueo; un vuelo pendiente solo existe fuera de primer plano.
            if state.exit != nil { #expect(state.scene == .active && !state.showsLock) }
            if state.pendingFlight != nil { #expect(state.scene != .active && !state.showsLock) }
        }
    }

    // MARK: (c) El arranque no se repite

    @Test func theLaunchNeverComesBack() {
        for step in Self.steps {
            if !step.before.launching { #expect(!step.after.launching, "el arranque volvió con \(step.event)") }
            if !step.before.coldStart { #expect(!step.after.coldStart, "volvió a ser arranque en frío con \(step.event)") }
            // Nada del arranque sobrevive a salir de primer plano.
            if case .scene(let scene) = step.event, scene != .active {
                #expect(!step.after.showsLaunch)
                #expect(step.after.exit == nil)
            }
        }
        // Ida y vuelta a segundo plano desde cualquier estado: la capa del arranque no aparece.
        for state in Self.states {
            var cycled = state
            cycled.apply(.scene(.background))
            cycled.apply(.scene(.active))
            #expect(!cycled.showsLaunch, "arranque tras volver de segundo plano desde \(state)")
            if !state.lockPlaysLaunch { #expect(!cycled.lockPlaysLaunch) }
        }
    }

    // MARK: (d) Inicio se monta una vez, en el desbloqueo, nunca después de verse montado

    @Test func homeAssemblesOncePerUnlockAndNeverAfterItWasShown() {
        for step in Self.steps {
            let bump = step.after.revealToken - step.before.revealToken
            #expect(bump == 0 || bump == 1)
            guard bump == 1 else { continue }
            // Solo desde un estado en que Inicio aún no se ha visto: tapado por el bloqueo o por el arranque.
            #expect(step.before.showsLock || step.before.showsLaunch, "Inicio se volvió a montar estando a la vista: \(step.event)")
            switch step.event {
            case .unlockSucceeded:
                #expect(step.before.showsLock)
            case .launchAssembled, .launchFinished, .safetyFired, .scene(.inactive), .scene(.background):
                #expect(step.before.showsLaunch && step.before.coldStart)
            default:
                Issue.record("Inicio se montó con \(step.event)")
            }
        }
        // Volver a primer plano nunca monta Inicio.
        for step in Self.steps where step.event == .scene(.active) {
            #expect(step.after.revealToken == step.before.revealToken)
        }
        // Todo desbloqueo con el bloqueo delante monta Inicio exactamente una vez, en ese instante.
        for step in Self.steps where step.event == .unlockSucceeded && step.before.showsLock {
            #expect(step.after.revealToken == step.before.revealToken + 1)
        }
    }

    /// La secuencia de Face ID en el iPhone: la escena está inactiva mientras comprueba, el éxito llega con la escena
    /// aún inactiva y solo después vuelve a activa.
    @Test func unlockWhileInactiveBuildsHomeUnderTheCoverAndFliesWhenActive() throws {
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        #expect(state.showsLock && state.lockPlaysLaunch)
        state.apply(.scene(.inactive))
        // Con el bloqueo delante no hay tapa: las piezas se ven mientras Face ID comprueba.
        #expect(state.showsLock && !state.showsCover)
        #expect(!state.fliesOnUnlock)
        state.apply(.unlockSucceeded)
        #expect(!state.showsLock)
        #expect(state.showsCover, "tras desbloquear con la escena inactiva tiene que estar la tapa")
        #expect(state.revealToken == 1, "Inicio se monta en el desbloqueo, debajo de la tapa")
        #expect(state.exit == nil)
        #expect(state.pendingFlight == true)
        #expect(!state.showsLaunch)
        state.apply(.scene(.active))
        #expect(!state.showsCover)
        #expect(state.revealToken == 1, "al volver a primer plano Inicio NO se vuelve a montar")
        #expect(state.shownExit?.cold == true)
        #expect(state.pendingFlight == nil)
        let id = try #require(state.exit?.id)
        state.apply(.exitFinished(id: id))
        #expect(state.exit == nil)
        #expect(state.revealToken == 1)
    }

    @Test func unlockWhileActiveBuildsHomeAndFliesAtOnce() {
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        #expect(state.fliesOnUnlock)
        state.apply(.unlockSucceeded)
        #expect(!state.showsLock && !state.showsCover && !state.showsLaunch)
        #expect(state.revealToken == 1)
        #expect(state.shownExit?.cold == true)
        // Un aviso de llegada de un vuelo viejo no quita el vuelo de ahora.
        state.apply(.exitFinished(id: 0))
        #expect(state.exit != nil)
    }

    @Test func fliesOnUnlockTellsTheTruth() {
        for state in Self.states where state.showsLock {
            var unlocked = state
            unlocked.apply(.unlockSucceeded)
            if state.fliesOnUnlock {
                #expect(unlocked.exit != nil && unlocked.pendingFlight == nil)
            } else {
                #expect(unlocked.exit == nil && unlocked.pendingFlight != nil)
            }
        }
        for state in Self.states where !state.showsLock {
            #expect(!state.fliesOnUnlock)
        }
    }

    // MARK: (e) El bloqueo solo lo quita el desbloqueo

    @Test func onlyUnlockDismissesTheLock() {
        for step in Self.steps where step.before.showsLock && !step.after.showsLock {
            #expect(step.event == .unlockSucceeded, "el bloqueo se quitó con \(step.event)")
        }
        // En particular: cambiar el ajuste con el bloqueo delante no lo quita; se aplica al desbloquear.
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.lockSettingChanged(lockApplies: false, relocksOnBackground: false))
        #expect(state.showsLock)
        state.apply(.unlockSucceeded)
        #expect(!state.showsLock)
        #expect(state.lockApplies == false && state.relocksOnBackground == false)
        state.apply(.scene(.background))
        #expect(!state.showsLock && state.showsCover)
    }

    @Test func theAppRelocksInTheBackgroundWhenTheSettingSaysSo() {
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.unlockSucceeded)
        state.apply(.scene(.inactive))
        #expect(!state.showsLock && state.showsCover)
        state.apply(.scene(.background))
        #expect(state.showsLock && !state.showsCover)
        #expect(!state.lockPlaysLaunch, "un re-bloqueo sale con la marca quieta")
        state.apply(.scene(.active))
        #expect(state.showsLock)
        state.apply(.unlockSucceeded)
        #expect(state.revealToken == 2)
        #expect(state.shownExit?.cold == false, "el vuelo de un re-bloqueo no lleva bandas")
        // Sin bloqueo en el ajuste, segundo plano no bloquea.
        var open = ShellState(lockApplies: false, relocksOnBackground: false)
        open.apply(.scene(.background))
        open.apply(.scene(.active))
        #expect(!open.showsLock)
    }

    // MARK: El arranque sin bloqueo

    @Test func launchWithoutLockAssemblesOnceAndEnds() {
        var state = ShellState(lockApplies: false, relocksOnBackground: false)
        #expect(state.showsLaunch && !state.showsLock)
        #expect(state.layers == [.home, .launch])
        state.apply(.launchAssembled)
        #expect(state.revealToken == 1 && state.showsLaunch)
        state.apply(.launchAssembled)
        #expect(state.revealToken == 1)
        state.apply(.launchFinished)
        #expect(!state.showsLaunch && state.revealToken == 1)
        #expect(state.layers == [.home])
        // El respaldo, después, no hace nada.
        state.apply(.safetyFired)
        #expect(state.revealToken == 1 && !state.showsLaunch)
    }

    @Test func theSafetyEndsALaunchThatNeverAssembled() {
        var state = ShellState(lockApplies: false, relocksOnBackground: false)
        state.apply(.safetyFired)
        #expect(!state.showsLaunch)
        #expect(state.revealToken == 1, "si el arranque se corta antes de montar Inicio, Inicio se monta entonces")
        // Con bloqueo delante el respaldo no toca nada.
        var locked = ShellState(lockApplies: true, relocksOnBackground: true)
        locked.apply(.safetyFired)
        locked.apply(.launchFinished)
        locked.apply(.launchAssembled)
        #expect(locked.showsLock && locked.revealToken == 0 && locked.lockPlaysLaunch)
    }

    @Test func changingTheSettingWhileUnlockedNeverAsksAgain() {
        var state = ShellState(lockApplies: false, relocksOnBackground: false)
        state.apply(.launchAssembled)
        state.apply(.launchFinished)
        // Activar el bloqueo en Ajustes (la app está desbloqueada): no aparece el bloqueo en ese momento.
        state.apply(.lockSettingChanged(lockApplies: true, relocksOnBackground: true))
        #expect(!state.showsLock)
        // Pero la próxima vez que vaya a segundo plano, sí.
        state.apply(.scene(.background))
        #expect(state.showsLock)
    }
}
