import Foundation
import Testing
@testable import MiBancoCore

/// El porcentaje de los pasos (conectar un banco, importar un extracto): sigue el paso real y nunca miente.
@Suite struct StepPercentTests {
    private let times: [Double] = [0, 0.01, 0.05, 0.1, 0.2, 0.35, 0.5, 0.92, 1.5, 3, 10, 60, 600, 86_400]

    @Test func empiezaEnCero() {
        let percent = StepPercent()
        #expect(percent.step == 0)
        #expect(percent.value(elapsed: 0) == 0)
        #expect(percent.caps == [34, 67, 99])
    }

    @Test func nuncaBajaDentroDeUnPaso() {
        for step in 0..<3 {
            var percent = StepPercent()
            percent.enter(step: step)
            var last = -1
            for t in times {
                let now = percent.value(elapsed: t)
                #expect(now >= last, "paso \(step), t=\(t): \(now) < \(last)")
                last = now
            }
        }
    }

    /// Mientras el paso sigue en marcha nunca llega a su tope, por mucho que tarde (el banco puede tardar minutos).
    @Test func nuncaAlcanzaElTopeAntesDeQueElPasoTermine() {
        for (step, cap) in [(0, 34), (1, 67), (2, 99)] {
            var percent = StepPercent()
            percent.enter(step: step)
            for t in times + [.infinity, .greatestFiniteMagnitude] {
                #expect(percent.value(elapsed: t) < cap, "paso \(step), t=\(t)")
            }
            #expect(percent.value(elapsed: 86_400) == cap - 1)
            #expect(percent.value(elapsed: .infinity) == cap - 1)
        }
    }

    /// Avanza rápido y luego frena (como en la maqueta): al cabo de un segundo ya ha hecho casi todo el recorrido.
    @Test func avanzaRapidoYFrena() {
        let percent = StepPercent()
        #expect(percent.value(elapsed: 0.2) >= 10)
        #expect(percent.value(elapsed: 0.92) >= 28)
        #expect(percent.value(elapsed: 0.92) <= 33)
    }

    /// Entrar en el paso siguiente arranca exactamente en el tope del anterior (ese paso SÍ terminó).
    @Test func elPasoSiguienteArrancaEnElTopeDelAnterior() {
        var percent = StepPercent()
        #expect(percent.value(elapsed: 5) == 33)
        percent.enter(step: 1)
        #expect(percent.value(elapsed: 0) == 34)
        #expect(percent.value(elapsed: 5) == 66)
        percent.enter(step: 2)
        #expect(percent.value(elapsed: 0) == 67)
        #expect(percent.value(elapsed: 5) == 98)
    }

    /// Nunca baja al cambiar de paso, se llegue cuando se llegue.
    @Test func nuncaBajaAlCambiarDePaso() {
        for t in times {
            var percent = StepPercent()
            let before = percent.value(elapsed: t)
            percent.enter(step: 1)
            #expect(percent.value(elapsed: 0) >= before)
            let middle = percent.value(elapsed: t)
            percent.enter(step: 2)
            #expect(percent.value(elapsed: 0) >= middle)
        }
    }

    @Test func cienSoloConExito() {
        var percent = StepPercent()
        for step in 0..<3 {
            percent.enter(step: step)
            for t in times { #expect(percent.value(elapsed: t) != 100) }
        }
        percent.succeed()
        #expect(percent.outcome == .succeeded)
        #expect(percent.value(elapsed: 0) == 100)
        #expect(percent.value(elapsed: 99) == 100)
        #expect(!percent.isRunning)
    }

    /// Un fallo deja la cifra congelada donde estaba: ni sube con el tiempo ni llega a 100 después.
    @Test func elFalloCongela() {
        var percent = StepPercent()
        percent.enter(step: 1)
        let shown = percent.value(elapsed: 0.3)
        percent.fail(shown: shown)
        #expect(percent.outcome == .failed(shown))
        for t in times { #expect(percent.value(elapsed: t) == shown) }
        percent.succeed()
        #expect(percent.value(elapsed: 1) == shown)
        percent.enter(step: 2)
        #expect(percent.step == 1)
        #expect(percent.value(elapsed: 1) == shown)
    }

    /// La cifra congelada se acota a lo que el paso podía enseñar.
    @Test func elFalloSeAcotaAlPaso() {
        var low = StepPercent()
        low.enter(step: 1)
        low.fail(shown: 3)
        #expect(low.value(elapsed: 0) == 34)
        var high = StepPercent()
        high.fail(shown: 250)
        #expect(high.value(elapsed: 0) == 33)
    }

    @Test func unPasoNoVuelveAtras() {
        var percent = StepPercent()
        percent.enter(step: 2)
        percent.enter(step: 0)
        #expect(percent.step == 2)
        percent.enter(step: 1)
        #expect(percent.step == 2)
    }

    @Test func indicesFueraDeRango() {
        var percent = StepPercent()
        percent.enter(step: 99)
        #expect(percent.step == 2)
        #expect(percent.value(elapsed: 100) == 98)
        var negative = StepPercent()
        negative.enter(step: -4)
        #expect(negative.step == 0)
    }

    @Test func tiemposRaros() {
        var percent = StepPercent()
        percent.enter(step: 1)
        #expect(percent.value(elapsed: -5) == 34)
        #expect(percent.value(elapsed: .nan) == 34)
        #expect(percent.value(elapsed: -.infinity) == 34)
    }

    @Test func topesPropiosYTopesInvalidos() {
        var two = StepPercent(caps: [50, 99])
        #expect(two.value(elapsed: 100) == 49)
        two.enter(step: 1)
        #expect(two.value(elapsed: 0) == 50)
        #expect(two.value(elapsed: 100) == 98)
        #expect(StepPercent(caps: []).caps == StepPercent.defaultCaps)
        #expect(StepPercent(caps: [67, 34]).caps == StepPercent.defaultCaps)
        #expect(StepPercent(caps: [34, 34, 99]).caps == StepPercent.defaultCaps)
        #expect(StepPercent(caps: [34, 100]).caps == StepPercent.defaultCaps)
        #expect(StepPercent(caps: [0, 50]).caps == StepPercent.defaultCaps)
    }

    /// Topes pegados (1 y 2): el paso no tiene sitio para contar y se queda en su suelo, sin tocar el tope.
    @Test func topesSinSitio() {
        var tight = StepPercent(caps: [1, 2])
        #expect(tight.value(elapsed: 100) == 0)
        tight.enter(step: 1)
        #expect(tight.value(elapsed: 100) == 1)
    }
}
