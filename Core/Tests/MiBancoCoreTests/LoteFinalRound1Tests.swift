import Foundation
import Testing
@testable import MiBancoCore

/// Lote final, parte 1 — ronda de arreglos 1 (kit, detalle y resumen).
@Suite struct LoteFinalRound1Tests {
    /// I-1: el importe del detalle se VE posado cuando la envolvente de su muelle baja del 5 %: antes que el final lógico
    /// de la animación (respuesta entera) y, a cualquier intensidad, hacia 0,22–0,35 s.
    @Test func theFlyingAmountLooksSettledEarly() {
        let fly = SpringSpec(response: 0.50, dampingFraction: 0.84)
        for level in MotionLevel.allCases {
            let scaled = MotionMath.scaled(fly, level: level)
            let settle = MotionMath.visibleSettle(scaled)
            #expect(settle > 0.2 && settle < 0.36, "\(level): \(settle)")
            #expect(settle < scaled.response, "\(level): se da por posado después de su respuesta")
        }
        let balanced = MotionMath.visibleSettle(MotionMath.scaled(fly, level: .balanced))
        #expect(abs(balanced - log(20) / (0.84 * 2 * Double.pi / 0.5)) < 1e-9)
        // Cuanto más se amortigua, antes se ve quieto; la cámara lenta lo alarga en proporción.
        #expect(MotionMath.visibleSettle(SpringSpec(response: 0.5, dampingFraction: 1))
                < MotionMath.visibleSettle(SpringSpec(response: 0.5, dampingFraction: 0.6)))
        let slow = MotionMath.scaled(fly, level: .balanced, timeMultiplier: 20)
        #expect(abs(MotionMath.visibleSettle(slow) - 20 * balanced) < 1e-9)
    }

    /// m-2: una duración de 0 (o negativa) deja la cifra puesta sin rodar.
    @Test func aZeroLengthDoesNotRoll() {
        for seconds in [0.0, -1.0] {
            let t = RollLength.seconds(seconds).timing(.count, digitCount: 6, level: .expressive)
            #expect(t.total(digitCount: 6) == 0, "\(seconds) s rueda \(t.total(digitCount: 6)) s")
        }
    }

    /// m-3: la duración por defecto: la protagonista, `.lead`; las demás, `.brief`.
    @Test func theDefaultLengthFollowsTheStyle() {
        #expect(RollLength.default(isHero: true) == .lead)
        #expect(RollLength.default(isHero: false) == .brief)
    }

    /// I-6: la voz se para cuando la salida pasa a ser menos privada, y solo entonces.
    @Test func lessPrivateRoutesStopTheVoice() {
        #expect(AudioRouteChange(rawReason: 2) == .oldDeviceUnavailable)
        #expect(AudioRouteChange(rawReason: 4) == .override)
        #expect(AudioRouteChange(rawReason: 99) == .unknown)
        let stops = (0...9).map { AudioRouteChange(rawReason: UInt($0)) }.filter(\.stopsSpeech)
        #expect(Set(stops.map { "\($0)" }) == ["oldDeviceUnavailable", "override", "noSuitableRouteForCategory"])
        #expect(!AudioRouteChange.newDeviceAvailable.stopsSpeech)
        #expect(!AudioRouteChange.routeConfigurationChange.stopsSpeech)
    }
}
