import Foundation
import Testing
@testable import MiBancoCore

/// La traducción «fase REAL del conector → paso, porcentaje, texto y final» de la pantalla de un banco. Se mueve con la
/// máquina de verdad (`ConnectFlow`) y sus eventos, como lo hace el conector: nada de etapas escritas a mano.
@Suite struct BankConnectProgressTests {
    /// Una pantalla de banco con su conector: cada evento pasa por `ConnectFlow` y la pantalla aplica la etapa que sale,
    /// como hace `BankLinkView` (también cuando no cambia: aplicar dos veces la misma etapa no hace nada).
    private struct Screen {
        var flow = ConnectFlow()
        var progress = BankConnectProgress()
        let bank: BankID
        var syncing = false
        /// Segundos del paso en curso (ya divididos por la cámara lenta).
        var stepElapsed = 0.0
        /// Todo lo que se ha dibujado como porcentaje, en orden.
        var drawnLog: [Int] = []

        init(bank: BankID = .ima) { self.bank = bank }

        var stage: BankConnectStage { progress.stage(of: flow.phase, bank: bank, syncing: syncing) }
        var drawn: Int? { progress.shown(for: stage)?.value(elapsed: stepElapsed) }

        @discardableResult
        mutating func send(_ event: ConnectEvent) -> [ConnectAction] {
            let actions = flow.handle(event)
            update()
            return actions
        }

        mutating func setSyncing(_ value: Bool) {
            syncing = value
            update()
        }

        mutating func update() {
            if progress.apply(stage, elapsed: stepElapsed) == .stepStarted { stepElapsed = 0 }
            sample()
        }

        /// Pasa el tiempo en trocitos, dibujando en cada uno.
        mutating func wait(_ seconds: Double) {
            var left = seconds
            while left > 0 {
                let dt = min(0.05, left)
                stepElapsed += dt
                left -= dt
                sample()
            }
        }

        mutating func sample() {
            if let drawn { drawnLog.append(drawn) }
        }
    }

    private static let list = [EBASPSP(name: "Revolut", country: "ES"), EBASPSP(name: "imaginBank", country: "ES")]

    /// Las ocho fases, para un banco dado.
    private static func allPhases(_ bank: BankID) -> [ConnectPhase] {
        [.idle, .opening(bank), .waitingForBank(bank), .finishing(bank), .connected(bank), .needsResume(bank),
         .failed(bank, ConnectMessage.tooSlow), .chooseASPSP(bank, list)]
    }

    private static func isNonDecreasing(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }

    // MARK: El mapeo, fase a fase

    @Test func cadaFaseDeEsteBancoTieneSuEtapa() {
        for bank in BankID.allCases {
            for syncing in [false, true] {
                for tracking in [false, true] {
                    for phase in Self.allPhases(bank) {
                        let stage = BankConnectStage.of(phase, bank: bank, syncing: syncing, tracking: tracking)
                        let expected: BankConnectStage
                        switch phase {
                        case .idle: expected = .none
                        case .opening: expected = .step(0)
                        case .waitingForBank: expected = .step(1)
                        case .finishing: expected = .step(2)
                        // «Conectado mientras carga»: sigue en el tercer paso solo si se seguía el trámite.
                        case .connected: expected = syncing && tracking ? .step(2) : .connected
                        case .needsResume: expected = .needsResume
                        case .failed(_, let message): expected = .failed(message)
                        case .chooseASPSP(_, let list): expected = .chooseASPSP(list)
                        }
                        #expect(stage == expected, "\(phase) · syncing \(syncing) · tracking \(tracking): \(stage)")
                    }
                }
            }
        }
    }

    /// El trámite de OTRO banco no se enseña en esta pantalla, sea cual sea su fase.
    @Test func elTramiteDeOtroBancoNoSeVe() {
        for bank in BankID.allCases {
            for other in BankID.allCases where other != bank {
                for phase in Self.allPhases(other) {
                    for syncing in [false, true] {
                        for tracking in [false, true] {
                            #expect(BankConnectStage.of(phase, bank: bank, syncing: syncing, tracking: tracking) == .none,
                                    "\(phase) de \(other) se ve en \(bank)")
                        }
                    }
                }
            }
        }
        // Y con la máquina de verdad: el trámite entero de Revolut, mirado desde imagin.
        var screen = Screen(bank: .ima)
        screen.send(.start(.rev))
        screen.send(.webOpened(.rev))
        screen.send(.callback(.valid(.rev)))
        screen.send(.succeeded(.rev))
        #expect(screen.drawnLog.isEmpty)
        #expect(screen.progress.success == false)
        #expect(screen.progress.showsStartActions(for: screen.stage))
    }

    @Test func textosDeLosPasos() {
        #expect(BankConnectStage.step(0).caption(bankName: "imagin") == "Esperando a imagin…")
        #expect(BankConnectStage.step(1).caption(bankName: "imagin") == "Esperando a imagin…")
        #expect(BankConnectStage.step(2).caption(bankName: "imagin") == "Terminando con imagin…")
        for stage: BankConnectStage in [.none, .connected, .failed("x"), .needsResume, .chooseASPSP(Self.list)] {
            #expect(stage.caption(bankName: "imagin") == nil, "\(stage)")
        }
        #expect(BankConnectStage.steps == ["Verificar", "Conectar", "Importar"])
        #expect(BankConnectStage.step(0).canCancel)
        #expect(BankConnectStage.step(1).canCancel)
        #expect(!BankConnectStage.step(2).canCancel)
        #expect(!BankConnectStage.failed("x").canCancel)
    }

    // MARK: El trámite entero

    /// Verificar › Conectar › Importar › conectado: el porcentaje nunca baja, nunca toca el tope de un paso en marcha
    /// y solo llega a 100 cuando el banco está conectado de verdad.
    @Test func caminoFelizSoloLlegaA100AlConectar() {
        var screen = Screen()
        screen.send(.start(.ima))
        #expect(screen.stage == .step(0))
        #expect(screen.drawn == 0)
        screen.wait(1.2)
        #expect(screen.drawn! < 34)
        screen.send(.webOpened(.ima))
        #expect(screen.stage == .step(1))
        #expect(screen.drawn == 34)
        screen.wait(90)
        #expect(screen.drawn == 66, "esperando al banco minutos: nunca 67")
        screen.send(.callback(.valid(.ima)))
        #expect(screen.stage == .step(2))
        screen.wait(30)
        #expect(screen.drawn == 98)
        #expect(!screen.drawnLog.contains(100))
        #expect(screen.progress.success == false)
        screen.send(.succeeded(.ima))
        #expect(screen.stage == .connected)
        #expect(screen.drawn == 100)
        #expect(screen.progress.success)
        #expect(Self.isNonDecreasing(screen.drawnLog), "\(screen.drawnLog)")
        #expect(screen.drawnLog.filter { $0 == 100 }.count == 1, "100 antes de conectar")
        // «Listo»: se va todo y vuelven las acciones.
        screen.progress.dismissSuccess()
        #expect(screen.drawn == nil)
        #expect(screen.progress.showsStartActions(for: screen.stage))
    }

    /// Conectado mientras la primera carga sigue: el tercer paso sigue en marcha y el éxito espera a que termine.
    @Test func conectadoMientrasCargaNoAdelantaElExito() {
        var screen = Screen()
        screen.send(.start(.ima))
        screen.send(.webOpened(.ima))
        screen.send(.callback(.valid(.ima)))
        screen.setSyncing(true)
        screen.wait(0.6)
        screen.send(.succeeded(.ima))
        #expect(screen.flow.phase == .connected(.ima))
        #expect(screen.stage == .step(2))
        #expect(screen.progress.success == false)
        screen.wait(20)
        #expect(screen.drawn == 98)
        #expect(!screen.drawnLog.contains(100))
        screen.setSyncing(false)
        #expect(screen.stage == .connected)
        #expect(screen.drawn == 100)
        #expect(screen.progress.success)
        #expect(Self.isNonDecreasing(screen.drawnLog), "\(screen.drawnLog)")
    }

    /// Si la pantalla se abre con el banco ya conectado (nadie siguió el trámite aquí), no hay éxito ni 100.
    @Test func sinTramiteVistoNoHayExito() {
        var screen = Screen()
        screen.flow.handle(.start(.ima))
        screen.flow.handle(.webOpened(.ima))
        screen.flow.handle(.callback(.valid(.ima)))
        screen.flow.handle(.succeeded(.ima))
        for syncing in [true, false] {
            screen.setSyncing(syncing)
            #expect(screen.stage == .connected)
            #expect(screen.progress.success == false)
            #expect(screen.drawn == nil)
            #expect(screen.progress.showsStartActions(for: screen.stage))
        }
    }

    /// Si se vuelve a la pantalla a mitad del trámite, el paso en curso se retoma desde su suelo (nunca desde 0 si ya
    /// iba por el segundo) y sigue adelante.
    @Test func volverAMitadRetomaElPaso() {
        var screen = Screen()
        screen.flow.handle(.start(.ima))
        screen.flow.handle(.webOpened(.ima))
        #expect(screen.drawn == 34, "primer instante, antes de apuntar el paso")
        screen.update()
        #expect(screen.drawn == 34)
        screen.wait(2)
        screen.send(.callback(.valid(.ima)))
        #expect(screen.drawn == 67)
        #expect(Self.isNonDecreasing(screen.drawnLog))
    }

    // MARK: Fallos

    /// Un fallo en cualquier paso congela la cifra que se veía (no sigue subiendo, no salta a 100), enseña el mensaje
    /// de siempre con «Empezar de nuevo»; empezar de nuevo arranca un trámite nuevo desde 0.
    @Test func unFalloCongelaLaCifraEnCadaPaso() {
        for failingStep in 0..<3 {
            var screen = Screen()
            screen.send(.start(.ima))
            if failingStep >= 1 { screen.wait(2); screen.send(.webOpened(.ima)) }
            if failingStep >= 2 { screen.wait(2); screen.send(.callback(.valid(.ima))) }
            screen.wait(0.7)
            let before = screen.drawn!
            screen.send(.failed(.ima, ConnectMessage.offline))
            #expect(screen.stage == .failed(ConnectMessage.offline), "paso \(failingStep)")
            #expect(screen.drawn == before, "paso \(failingStep): la cifra cambió al fallar (\(before) -> \(screen.drawn ?? -1))")
            screen.wait(60)
            #expect(screen.drawn == before, "paso \(failingStep): la cifra siguió moviéndose tras el fallo")
            #expect(!screen.drawnLog.contains(100))
            #expect(screen.progress.success == false)
            #expect(screen.stage.caption(bankName: "imagin") == nil)
            #expect(!screen.stage.canCancel)
            #expect(!screen.progress.showsStartActions(for: screen.stage), "el fallo esconde «Conectar»")
            #expect(Self.isNonDecreasing(screen.drawnLog))

            // «Empezar de nuevo»: el mismo `start` que manda el conector.
            screen.send(.start(.ima))
            #expect(screen.stage == .step(0))
            #expect(screen.drawn == 0)
            #expect(screen.progress.isTracking)
            screen.wait(0.5)
            #expect(screen.drawn! > 0)
        }
    }

    /// Los fallos que llegan por otros caminos (la persona cierra la web del banco; la vuelta llega caducada) también
    /// congelan y enseñan su mensaje.
    @Test func otrosFallosRealesTambienCongelan() {
        var dismissed = Screen()
        dismissed.send(.start(.ima))
        dismissed.send(.webOpened(.ima))
        dismissed.wait(1)
        let shown = dismissed.drawn
        dismissed.send(.webDismissedByUser)
        #expect(dismissed.stage == .failed(ConnectMessage.cancelled))
        dismissed.wait(10)
        #expect(dismissed.drawn == shown)

        var expired = Screen()
        expired.send(.start(.ima))
        expired.send(.webOpened(.ima))
        expired.wait(3)
        let before = expired.drawn
        expired.send(.callback(.expired(.ima)))
        #expect(expired.stage == .failed(ConnectMessage.tooSlow))
        expired.wait(10)
        #expect(expired.drawn == before)
        #expect(!expired.drawnLog.contains(100))
    }

    /// Un fallo que ya estaba al abrir la pantalla enseña el mensaje sin porcentaje.
    @Test func falloSinTramiteVistoSinPorcentaje() {
        var screen = Screen()
        screen.flow.handle(.start(.ima))
        screen.flow.handle(.failed(.ima, ConnectMessage.tooSlow))
        screen.update()
        #expect(screen.stage == .failed(ConnectMessage.tooSlow))
        #expect(screen.drawn == nil)
        #expect(!screen.progress.showsStartActions(for: screen.stage))
    }

    // MARK: Cancelar, seguir y elegir banco

    /// Cancelar antes de abrir la web vuelve al principio: sin porcentaje y con «Conectar» otra vez.
    @Test func cancelarAlAbrirVuelveAlPrincipio() {
        var screen = Screen()
        screen.send(.start(.ima))
        screen.wait(1)
        screen.send(.cancel)
        #expect(screen.flow.phase == .idle)
        #expect(screen.stage == .none)
        #expect(screen.drawn == nil)
        #expect(screen.progress.percent == nil)
        #expect(screen.progress.showsStartActions(for: screen.stage))
    }

    /// Cancelar esperando al banco (o volver tras más de 5 min fuera) pide «¿Ya lo has aprobado…?» sin porcentaje;
    /// seguir arranca un trámite nuevo desde 0.
    @Test func esperaCortadaPideSeguirSinPorcentaje() {
        var cancelled = Screen()
        cancelled.send(.start(.ima))
        cancelled.send(.webOpened(.ima))
        cancelled.wait(2)
        cancelled.send(.cancel)
        #expect(cancelled.stage == .needsResume)
        #expect(cancelled.drawn == nil)
        #expect(cancelled.progress.percent == nil)
        #expect(!cancelled.progress.showsStartActions(for: cancelled.stage))
        // «Seguir» sin intento válido = empezar de nuevo (el conector manda `start`).
        #expect(cancelled.send(.resume(pending: .none, hasAuthURL: false)) == [.restart(.ima)])
        cancelled.send(.start(.ima))
        #expect(cancelled.stage == .step(0))
        #expect(cancelled.drawn == 0)

        var away = Screen()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        away.send(.start(.ima))
        away.send(.webOpened(.ima))
        away.wait(1)
        away.send(.sceneBackground(t0))
        away.send(.sceneActive(t0.addingTimeInterval(ConnectFlow.awayLimit + 1)))
        #expect(away.stage == .needsResume)
        #expect(away.drawn == nil)
        // «Seguir» con el intento aún válido vuelve a abrir la web: Verificar desde 0, un trámite nuevo.
        #expect(away.send(.resume(pending: .valid(.ima), hasAuthURL: true)) == [.openWeb(.ima)])
        #expect(away.stage == .step(0))
        #expect(away.drawn == 0)
    }

    /// Hay que elegir el banco en la lista: sin porcentaje, sin «Conectar», con la lista.
    @Test func elegirBancoEnLaLista() {
        var screen = Screen(bank: .rev)
        screen.send(.start(.rev))
        screen.wait(0.4)
        screen.send(.needsChoice(.rev, Self.list))
        #expect(screen.stage == .chooseASPSP(Self.list))
        #expect(screen.drawn == nil)
        #expect(screen.progress.percent == nil)
        #expect(!screen.progress.showsStartActions(for: screen.stage))
        // Elegido el banco, el conector vuelve a empezar.
        screen.send(.start(.rev))
        #expect(screen.stage == .step(0))
        #expect(screen.drawn == 0)
    }

    /// Desconectar u «Olvidar clave y conexiones» a mitad: no queda trámite que enseñar.
    @Test func desconectarUOlvidarAMitadLoQuita() {
        for event in [ConnectEvent.disconnected(.ima), .forgetAll] {
            var screen = Screen()
            screen.send(.start(.ima))
            screen.send(.webOpened(.ima))
            screen.wait(1)
            screen.send(event)
            #expect(screen.stage == .none, "\(event)")
            #expect(screen.drawn == nil, "\(event)")
            #expect(screen.progress.showsStartActions(for: screen.stage), "\(event)")
        }
    }

    // MARK: El remate (ojo de diseño 14.1): 100, tercer ✓, «Todo listo», pausa y entonces «conectado»

    /// El remate solo llega con el éxito REAL: mientras el tercer paso sigue (minutos si hace falta) no hay remate, ni
    /// 100, ni «Todo listo»; al conectar, el remate parte de la cifra que se veía y «conectado» espera a `revealSuccess`.
    @Test func elRemateSoloTrasElExitoReal() {
        var screen = Screen()
        screen.send(.start(.ima))
        screen.send(.webOpened(.ima))
        screen.send(.callback(.valid(.ima)))
        screen.wait(40)
        #expect(!screen.progress.finishing)
        #expect(screen.progress.caption(for: screen.stage, bankName: "imagin") == "Terminando con imagin…")
        let before = screen.drawn!
        screen.send(.succeeded(.ima))
        #expect(screen.progress.finishing)
        #expect(screen.progress.success)
        #expect(!screen.progress.showsSuccess, "«conectado» antes del remate")
        #expect(screen.progress.caption(for: screen.stage, bankName: "imagin") == BankConnectProgress.finishCaption)
        #expect(BankConnectProgress.finishCaption == "Todo listo")
        // El remate arranca en la cifra que se veía (no salta) y acaba en 100.
        let finish = screen.progress.shown(for: screen.stage)!
        #expect(finish.drawn(elapsed: 0, reduce: false) == before)
        #expect(finish.drawn(elapsed: StepPercent.finishSeconds, reduce: false) == 100)
        // Mientras dura el remate no hay acciones de inicio ni nada se puede cancelar.
        #expect(!screen.progress.showsStartActions(for: screen.stage))
        // Mirar la fase otra vez (o que se quite el trámite) no lo corta ni lo repite.
        screen.update()
        screen.send(.reset)
        #expect(screen.progress.finishing)
        screen.progress.revealSuccess()
        #expect(!screen.progress.finishing)
        #expect(screen.progress.showsSuccess)
        #expect(screen.progress.caption(for: screen.stage, bankName: "imagin") == nil)
        screen.progress.dismissSuccess()
        #expect(!screen.progress.finishing && !screen.progress.showsSuccess)
    }

    /// Un fallo (en cualquier paso), cancelar, la espera cortada o elegir banco NUNCA enseñan el remate, y
    /// `revealSuccess` sin éxito no hace nada: el error se ve en el mismo instante en que llega.
    @Test func sinExitoNoHayRemate() {
        for failingStep in 0..<3 {
            var screen = Screen()
            screen.send(.start(.ima))
            if failingStep >= 1 { screen.send(.webOpened(.ima)) }
            if failingStep >= 2 { screen.send(.callback(.valid(.ima))) }
            screen.wait(1)
            screen.send(.failed(.ima, ConnectMessage.offline))
            #expect(screen.stage == .failed(ConnectMessage.offline))
            #expect(!screen.progress.finishing)
            screen.progress.revealSuccess()
            #expect(!screen.progress.showsSuccess)
            #expect(screen.progress.caption(for: screen.stage, bankName: "imagin") == nil)
        }
        for (opened, event) in [(true, ConnectEvent.cancel), (false, .cancel), (false, .needsChoice(.ima, Self.list))] {
            var screen = Screen()
            screen.send(.start(.ima))
            if opened { screen.send(.webOpened(.ima)) }
            screen.send(event)
            #expect(!screen.progress.finishing, "\(event)")
            screen.progress.revealSuccess()
            #expect(!screen.progress.showsSuccess, "\(event)")
        }
        // Conectado sin trámite seguido en esta pantalla: tampoco.
        var opened = Screen()
        opened.flow.handle(.start(.ima))
        opened.flow.handle(.webOpened(.ima))
        opened.flow.handle(.callback(.valid(.ima)))
        opened.flow.handle(.succeeded(.ima))
        opened.update()
        #expect(!opened.progress.finishing)
        #expect(!opened.progress.showsSuccess)
    }

    /// Conectado mientras la primera carga sigue: el remate espera a que la carga termine (el trabajo real).
    @Test func elRemateEsperaALaPrimeraCarga() {
        var screen = Screen()
        screen.send(.start(.ima))
        screen.send(.webOpened(.ima))
        screen.send(.callback(.valid(.ima)))
        screen.setSyncing(true)
        screen.send(.succeeded(.ima))
        screen.wait(10)
        #expect(!screen.progress.finishing)
        screen.setSyncing(false)
        #expect(screen.progress.finishing)
    }

    /// Un trámite nuevo durante el remate (o tras él) lo quita: vuelve a empezar desde 0.
    @Test func unTramiteNuevoQuitaElRemate() {
        var progress = BankConnectProgress()
        progress.apply(.step(2), elapsed: 0)
        progress.apply(.connected, elapsed: 3)
        #expect(progress.finishing)
        #expect(progress.apply(.step(0), elapsed: 0) == .stepStarted)
        #expect(!progress.finishing && !progress.success)
        #expect(progress.isTracking)
    }

    /// Con Reducir movimiento la cifra no cuenta (se ve el suelo del paso): un fallo congela ESA cifra, no una mayor que
    /// nunca se vio (menor m-2), y el remate parte también de ella.
    @Test func conReducirSeCongelaLoQueSeVeia() {
        var failed = BankConnectProgress()
        failed.apply(.step(1), elapsed: 0, reduce: true)
        #expect(failed.apply(.failed("x"), elapsed: 2.5, reduce: true) == .failed)
        #expect(failed.percent?.value(elapsed: 0) == 34)
        var done = BankConnectProgress()
        done.apply(.step(2), elapsed: 0, reduce: true)
        done.apply(.connected, elapsed: 4, reduce: true)
        #expect(done.percent?.finishFrom == 67)
    }

    /// Aplicar dos veces la misma etapa no cambia nada (la pantalla puede volver a mirar la fase en cualquier momento).
    @Test func aplicarLaMismaEtapaNoCambiaNada() {
        for stage: BankConnectStage in [.step(0), .step(1), .step(2)] {
            var progress = BankConnectProgress()
            #expect(progress.apply(stage, elapsed: 0) == .stepStarted)
            let once = progress
            #expect(progress.apply(stage, elapsed: 5) == .none)
            #expect(progress == once)
        }
        var done = BankConnectProgress()
        done.apply(.step(2), elapsed: 0)
        #expect(done.apply(.connected, elapsed: 1) == .succeeded)
        #expect(done.apply(.connected, elapsed: 2) == .none)
        #expect(done.success)
        var failed = BankConnectProgress()
        failed.apply(.step(1), elapsed: 0)
        #expect(failed.apply(.failed("x"), elapsed: 1) == .failed)
        let frozen = failed
        #expect(failed.apply(.failed("x"), elapsed: 9) == .none)
        #expect(failed == frozen)
    }
}
