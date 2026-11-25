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
            .lockFadeFinished(id: state.fadeCount), .lockFadeFinished(id: state.fadeCount - 1),
            .motionStyle(fadesOnly: true), .motionStyle(fadesOnly: false),
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
        copy.fadeCount = 0
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
            // (En segundo plano el desbloqueo se ignora: D-10.)
            #expect(step.after.revealToken == step.before.revealToken + (step.before.acceptsUnlock ? 1 : 0))
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
            } else if state.acceptsUnlock {
                #expect(unlocked.exit == nil && unlocked.pendingFlight != nil)
            } else {
                // En segundo plano no se desbloquea: ni vuelo ni vuelo pendiente.
                #expect(unlocked == state)
            }
        }
        for state in Self.states where !state.showsLock {
            #expect(!state.fliesOnUnlock)
        }
    }

    // MARK: N-1 · Desbloquear con la escena aún inactiva: el bloqueo no se funde, lo releva la tapa

    /// En primer plano el bloqueo se funde sobre Inicio. Fuera de primer plano (Face ID aún tiene la escena inactiva)
    /// se quita de golpe, porque la tapa se pone encima en esa misma actualización: debajo no queda un bloqueo a medio
    /// fundir que pueda asomar si la escena vuelve a activa antes de que el fundido hubiera terminado.
    @Test func unlockOutsideTheForegroundIsCoveredAndNeverFades() {
        #expect(Self.states.contains { $0.showsLock && $0.scene == .active })
        #expect(Self.states.contains { $0.showsLock && $0.scene == .inactive })
        for state in Self.states where state.showsLock {
            var unlocked = state
            unlocked.apply(.unlockSucceeded)
            if state.scene == .active {
                #expect(state.lockExitOnUnlock == .fades)
                #expect(unlocked.lockFading)
                #expect(!unlocked.showsCover)
            } else if state.scene == .background {
                // D-10: en segundo plano el bloqueo no se va de ninguna manera.
                #expect(state.lockExitOnUnlock == nil)
                #expect(unlocked == state)
            } else {
                #expect(state.lockExitOnUnlock == .covered, "fuera de primer plano el bloqueo se fundiría: \(state)")
                #expect(!unlocked.lockFading, "queda un bloqueo fundiéndose debajo de la tapa: \(state)")
                #expect(unlocked.showsCover)
            }
        }
        for state in Self.states where !state.showsLock {
            #expect(state.lockExitOnUnlock == nil)
        }
    }

    /// El vuelo que esperaba a primer plano nunca arranca con un bloqueo aún fundiéndose debajo (serían dos marcas: la
    /// del bloqueo a medio apagar y la que vuela).
    @Test func aDeferredFlightNeverStartsOverAFadingLock() {
        #expect(Self.states.contains { $0.lockFading })
        for state in Self.states where state.pendingFlight != nil {
            #expect(!state.lockFading, "vuelo pendiente con un bloqueo fundiéndose: \(state)")
        }
        var deferredFlights = 0
        for step in Self.steps where step.before.pendingFlight != nil && step.after.exit != nil {
            deferredFlights += 1
            #expect(step.event == .scene(.active))
            #expect(!step.after.lockFading, "la marca echó a volar sobre un bloqueo a medio fundir")
        }
        #expect(deferredFlights > 0)
        // La secuencia de la revisión: éxito de Face ID con la escena inactiva y, un instante después (menos de lo que
        // dura un fundido), la escena vuelve a activa.
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.scene(.inactive))
        #expect(state.lockExitOnUnlock == .covered)
        state.apply(.unlockSucceeded)
        #expect(state.showsCover && !state.lockFading && state.pendingFlight == true)
        state.apply(.scene(.active))
        #expect(state.shownExit?.cold == true)
        #expect(!state.lockFading && !state.showsCover)
        #expect(state.revealToken == 1)
        #expect(state.homeTakesTouches)
    }

    // MARK: Toque tardío · mientras el bloqueo se funde, Inicio no recibe toques

    @Test func homeTakesNoTouchesUntilTheLockIsGone() throws {
        for state in Self.states {
            #expect(state.homeTakesTouches == (!state.showsLock && !state.lockFading), "\(state)")
            guard state.lockFading else { continue }
            // Un bloqueo que se funde ya no es el bloqueo: está desbloqueado.
            #expect(!state.showsLock)
            // Y siempre tiene salida: al acabar el fundido, Inicio se puede tocar.
            var done = state
            done.apply(.lockFadeFinished(id: state.fadeCount))
            #expect(!done.lockFading && done.homeTakesTouches)
            // El aviso de un fundido anterior no lo da por acabado.
            var stale = state
            stale.apply(.lockFadeFinished(id: state.fadeCount - 1))
            #expect(stale.lockFading && !stale.homeTakesTouches)
        }
        for step in Self.steps {
            if !step.before.lockFading && step.after.lockFading {
                #expect(step.event == .unlockSucceeded && step.before.showsLock && step.before.scene == .active,
                        "un bloqueo empezó a fundirse con \(step.event)")
            }
            if step.before.lockFading && !step.after.lockFading {
                // Solo deja de fundirse porque el fundido acabó o porque el bloqueo vuelve a estar delante, entero.
                #expect(step.event == .lockFadeFinished(id: step.before.fadeCount) || step.after.showsLock,
                        "el fundido se dio por acabado con \(step.event)")
            }
        }
        // La secuencia del toque tardío: desbloqueo en primer plano; mientras dura el fundido nada devuelve los toques a
        // Inicio (ni que la marca termine de volar ni un cambio de fase); cuando acaba, sí.
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        #expect(!state.homeTakesTouches)
        state.apply(.unlockSucceeded)
        #expect(!state.showsLock && state.lockFading)
        #expect(!state.homeTakesTouches, "con el bloqueo fundiéndose, un toque llegaría a Inicio")
        let flight = try #require(state.exit?.id)
        state.apply(.exitFinished(id: flight))
        #expect(!state.homeTakesTouches)
        state.apply(.scene(.inactive))
        state.apply(.scene(.active))
        #expect(!state.homeTakesTouches)
        state.apply(.lockFadeFinished(id: state.fadeCount))
        #expect(state.homeTakesTouches)
        // Sin bloqueo nunca hay fundido: Inicio se toca en cuanto el arranque lo deja (eso lo mide la capa del arranque).
        var open = ShellState(lockApplies: false, relocksOnBackground: false)
        #expect(open.homeTakesTouches && !open.lockFading)
        open.apply(.lockFadeFinished(id: open.fadeCount))
        #expect(open.homeTakesTouches)
    }

    /// m-1 de la segunda re-revisión: desbloqueo, re-bloqueo y otro desbloqueo dentro de lo que dura un fundido. El
    /// aviso de fin del primer fundido llega durante el segundo y NO le devuelve los toques a Inicio antes de tiempo.
    @Test func aStaleFadeEndNeverEndsALaterFade() {
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.unlockSucceeded)
        let first = state.fadeCount
        #expect(state.lockFading)
        state.apply(.scene(.background))
        #expect(state.showsLock && !state.lockFading)
        state.apply(.scene(.active))
        state.apply(.unlockSucceeded)
        let second = state.fadeCount
        #expect(second == first + 1 && state.lockFading)
        state.apply(.lockFadeFinished(id: first))
        #expect(state.lockFading && !state.homeTakesTouches, "el fin del primer fundido acabó el segundo")
        state.apply(.lockFadeFinished(id: second))
        #expect(!state.lockFading && state.homeTakesTouches)
        // En todo el recorrido: solo el número del fundido en curso lo acaba, y cada fundido nuevo estrena número.
        for step in Self.steps {
            if !step.before.lockFading && step.after.lockFading { #expect(step.after.fadeCount == step.before.fadeCount + 1) }
            if case .lockFadeFinished(let id) = step.event, step.before.lockFading, id != step.before.fadeCount {
                #expect(step.after.lockFading)
            }
        }
    }

    // MARK: Lote 3 (0) · Con solo fundidos, desbloquear no enseña dos marcas

    /// En Sutil o con Reducir movimiento nada vuela: el bloqueo se funde con su marca grande sobre Inicio. Mientras se
    /// funde, la ranura de la marca de la barra de Inicio no se dibuja (si no, se verían dos marcas a medias); aparece
    /// en cuanto el fundido termina, y nunca se queda escondida.
    @Test func aFadingUnlockNeverShowsTwoMarks() {
        #expect(Self.states.contains { $0.hidesBrandSlot }, "el recorrido no llega a un desbloqueo con solo fundidos")
        for state in Self.states {
            // Con solo fundidos y el bloqueo fundiéndose (ya quitado), la ranura no se dibuja.
            if state.fadesOnly, state.lockFading, !state.showsLock {
                #expect(state.hidesBrandSlot, "dos marcas: el bloqueo se funde con la suya y la ranura dibuja otra: \(state)")
            }
            // Y solo entonces: ni con piezas (ahí la esconde la marca que vuela), ni sin fundido (se quedaría sin marca).
            if state.hidesBrandSlot {
                #expect(state.fadesOnly && state.lockFading && !state.showsLock, "\(state)")
                #expect(!state.homeTakesTouches, "la ranura escondida con Inicio ya tocable: \(state)")
            }
        }
        for step in Self.steps where step.event == .unlockSucceeded && step.before.showsLock && step.before.fadesOnly {
            if step.after.lockFading { #expect(step.after.hidesBrandSlot, "\(step.before)") }
        }
        // Nunca se queda escondida: el aviso de fin del fundido en curso la devuelve, y también ir a segundo plano.
        for step in Self.steps where step.before.hidesBrandSlot {
            if step.event == .lockFadeFinished(id: step.before.fadeCount) { #expect(!step.after.hidesBrandSlot) }
            if step.event == .scene(.background) { #expect(!step.after.hidesBrandSlot || !step.after.showsLock) }
        }
        // La secuencia: Sutil, desbloqueo en primer plano, fundido, fin.
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.motionStyle(fadesOnly: true))
        #expect(!state.hidesBrandSlot)
        state.apply(.unlockSucceeded)
        #expect(state.lockFading && state.hidesBrandSlot)
        state.apply(.lockFadeFinished(id: state.fadeCount))
        #expect(!state.hidesBrandSlot)
        // Con piezas, esto no esconde nada (la ranura la esconde la marca que vuela).
        var pieces = ShellState(lockApplies: true, relocksOnBackground: true)
        pieces.apply(.unlockSucceeded)
        #expect(pieces.lockFading && !pieces.hidesBrandSlot)
        // El estilo no toca el bloqueo: ni lo quita ni lo pone.
        for step in Self.steps {
            if case .motionStyle = step.event {
                #expect(step.after.locked == step.before.locked && step.after.lockFading == step.before.lockFading)
            }
        }
    }

    // MARK: D-10 · Con el bloqueo activado, la app nunca está desbloqueada en segundo plano

    @Test func theAppIsNeverUnlockedInTheBackgroundWithTheLockEnabled() {
        #expect(Self.states.contains { $0.scene == .background && $0.relocksOnBackground })
        #expect(Self.states.contains { $0.scene == .background && !$0.relocksOnBackground && !$0.locked })
        for state in Self.states where state.scene == .background && state.relocksOnBackground {
            #expect(state.locked, "desbloqueada en segundo plano con el bloqueo activado: \(state)")
            if state.lockApplies { #expect(state.showsLock && state.hidesHome && !state.homeTakesTouches) }
        }
        // Ningún suceso desbloquea en segundo plano, con ningún ajuste: el éxito de la autenticación se ignora entero.
        for step in Self.steps where step.before.scene == .background && step.event == .unlockSucceeded {
            #expect(step.after == step.before, "un desbloqueo en segundo plano cambió algo: \(step.before)")
        }
        for state in Self.states {
            #expect(state.acceptsUnlock == (state.scene != .background))
        }
        // La secuencia de la revisión: Face ID está comprobando (escena inactiva), el usuario sale de la app (segundo
        // plano) y el éxito llega entonces. La app sigue bloqueada; al volver, el bloqueo está delante y un éxito nuevo
        // (ya en primer plano) sí desbloquea, y el siguiente paso por segundo plano vuelve a bloquear.
        var state = ShellState(lockApplies: true, relocksOnBackground: true)
        state.apply(.scene(.inactive))
        state.apply(.scene(.background))
        #expect(!state.acceptsUnlock)
        state.apply(.unlockSucceeded)
        #expect(state.showsLock && state.revealToken == 0 && state.exit == nil && state.pendingFlight == nil && !state.lockFading)
        #expect(state.lockPlaysLaunch, "sigue siendo el arranque en frío: Inicio no se ha enseñado")
        state.apply(.scene(.inactive))
        state.apply(.scene(.active))
        #expect(state.showsLock && state.acceptsUnlock)
        state.apply(.unlockSucceeded)
        #expect(!state.showsLock && state.revealToken == 1)
        state.apply(.scene(.background))
        #expect(state.showsLock)
        // Lo mismo tras un re-bloqueo: desbloqueada, a segundo plano (se bloquea) y un éxito tardío del intento anterior.
        state.apply(.unlockSucceeded)
        #expect(state.showsLock && state.revealToken == 1)
    }

    // MARK: La vista pinta lo que dice el reductor

    @Test func theViewDrawsTheLayersInThisOrder() {
        // La altura crece con el orden de las capas y la tapa es la más alta: nada puede quedar encima de ella.
        for state in Self.states {
            for scene in ShellState.Scene.allCases {
                let layers = state.layers(liveScene: scene)
                let heights = layers.map(ShellState.zIndex(of:))
                #expect(heights == heights.sorted(), "capas fuera de orden: \(layers)")
                #expect(Set(heights).count == heights.count, "dos capas a la misma altura: \(layers)")
                #expect(layers.first == .home)
                #expect(layers.contains(.cover) == ShellState.showsCover(scene: scene, showsLock: state.showsLock))
                #expect(!(layers.contains(.lock) && layers.contains(.launch)))
                if scene != .active { #expect(layers.last == .lock || layers.last == .cover) }
            }
            #expect(state.layers == state.layers(liveScene: state.scene))
        }
        for layer in ShellState.Layer.allCases where layer != .cover {
            #expect(ShellState.zIndex(of: layer) < ShellState.zIndex(of: .cover))
        }
        #expect(ShellState.zIndex(of: .exit) > ShellState.zIndex(of: .lock))
    }

    @Test func voiceOverDoesNotReadHomeUnderTheBlackLaunch() {
        for state in Self.states {
            #expect(state.hidesHomeFromVoiceOver == (state.showsLock || (state.showsLaunch && state.coldStart)))
            if state.hidesHome { #expect(state.hidesHomeFromVoiceOver) }
        }
        var state = ShellState(lockApplies: false, relocksOnBackground: false)
        #expect(state.hidesHomeFromVoiceOver && !state.hidesHome)
        state.apply(.launchAssembled)
        #expect(!state.hidesHomeFromVoiceOver, "Inicio ya se está montando a la vista: VoiceOver puede leerlo")
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
