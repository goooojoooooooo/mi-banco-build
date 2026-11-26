import Testing
@testable import MiBancoCore

/// La bienvenida y su marca según lo que las tapa (arranque, bloqueo).
@Suite struct WelcomeRevealTests {
    /// Sin bloqueo: empieza cuando el arranque deja ver lo de debajo; la marca, cuando el arranque ha terminado.
    @Test func sinBloqueo() {
        var reveal = WelcomeReveal()
        #expect(!reveal.welcomed && !reveal.markShown)
        reveal.handle(.launchRevealsBelow(locked: false))
        #expect(reveal.welcomed)
        #expect(!reveal.markShown, "la marca propia no puede salir con la del arranque aún volando")
        reveal.handle(.launchFinished(locked: false))
        #expect(reveal.markShown)
    }

    /// Con el bloqueo delante desde el principio: nada hasta que se abre; la marca, tras el vuelo de la del bloqueo.
    @Test func conBloqueoDesdeElPrincipio() {
        var reveal = WelcomeReveal()
        reveal.handle(.launchRevealsBelow(locked: true))
        reveal.handle(.launchFinished(locked: true))
        #expect(!reveal.welcomed && !reveal.markShown)
        #expect(reveal.handle(.unlocked) == .waitForUnlockFlight)
        #expect(reveal.welcomed)
        #expect(!reveal.markShown)
        reveal.handle(.unlockFlightLanded)
        #expect(reveal.markShown)
    }

    /// El fallo de antes (menor m-3 del lote 3): el bloqueo entra mientras se espera al final del arranque. Al abrirse,
    /// la marca tiene que salir igual; antes se quedaba escondida para siempre.
    @Test func elBloqueoEnLaEsperaNoEscondeLaMarcaParaSiempre() {
        var reveal = WelcomeReveal()
        reveal.handle(.launchRevealsBelow(locked: false))
        #expect(reveal.welcomed)
        reveal.handle(.launchFinished(locked: true))
        #expect(!reveal.markShown, "con el bloqueo delante la marca espera")
        #expect(reveal.handle(.unlocked) == .waitForUnlockFlight, "al abrirse hay que programar la marca")
        reveal.handle(.unlockFlightLanded)
        #expect(reveal.markShown)
    }

    /// Abrir el bloqueo con la marca ya puesta no pide nada; un vuelo que aterriza sin bienvenida no pone la marca.
    @Test func casosSinEfecto() {
        var shown = WelcomeReveal()
        shown.handle(.launchRevealsBelow(locked: false))
        shown.handle(.launchFinished(locked: false))
        #expect(shown.handle(.unlocked) == .none)
        #expect(shown.markShown)

        var early = WelcomeReveal()
        early.handle(.unlockFlightLanded)
        #expect(!early.markShown)
        early.handle(.launchFinished(locked: false))
        #expect(!early.markShown, "sin bienvenida a la vista no hay marca")
    }

    /// El bloqueo se abre antes de que termine el arranque: la marca propia espera al vuelo de la del bloqueo (nunca dos
    /// marcas a la vez), aunque el arranque termine antes de que aterrice.
    @Test func laMarcaEsperaAlVueloDelBloqueo() {
        var reveal = WelcomeReveal()
        reveal.handle(.launchRevealsBelow(locked: true))
        #expect(reveal.handle(.unlocked) == .waitForUnlockFlight)
        reveal.handle(.launchFinished(locked: false))
        #expect(!reveal.markShown, "la marca propia salió con la del bloqueo aún volando")
        reveal.handle(.unlockFlightLanded)
        #expect(reveal.markShown)
    }
}
