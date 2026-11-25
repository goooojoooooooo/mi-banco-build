import Foundation
import Testing
@testable import MiBancoCore

/// El guion del arranque «logo en piezas»: tiempos puros, sin pantalla.
@Suite struct LaunchTimelineTests {
    private let expressive = LaunchTimeline(level: .expressive, reduceMotion: false)
    private let balanced = LaunchTimeline(level: .balanced, reduceMotion: false)
    private let subtle = LaunchTimeline(level: .subtle, reduceMotion: false)
    private let reduced = LaunchTimeline(level: .expressive, reduceMotion: true)

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

    /// Muestras de tiempo de 0 a un poco más allá del final.
    private func samples(_ timeline: LaunchTimeline, step: Double = 0.005) -> [Double] {
        Array(stride(from: 0.0, through: timeline.duration + 0.2, by: step))
    }

    // MARK: Duración

    @Test func expressiveEndsWithinOnePointThreeFive() {
        #expect(expressive.style == .pieces)
        #expect(expressive.duration <= 1.35)
        #expect(near(expressive.duration, 1.20 * 1.12))
        #expect(balanced.style == .pieces)
        #expect(near(balanced.duration, 1.20))
    }

    @Test func marksAreInOrder() throws {
        for timeline in [expressive, balanced] {
            let flight = try #require(timeline.flightAt)
            #expect(timeline.assembleAt > 0)
            #expect(timeline.assembleAt < flight)
            #expect(flight < timeline.duration)
            // La capa deja de recibir toques justo cuando la marca echa a volar.
            #expect(timeline.interactiveAt == flight)
            #expect(near(timeline.assembleAt, 0.78 * timeline.level.timeScale))
            #expect(near(flight, 0.86 * timeline.level.timeScale))
        }
    }

    // MARK: Sutil y Reducir movimiento: solo un fundido

    @Test func subtleAndReduceMotionOnlyFade() {
        #expect(subtle.style == .fade)
        #expect(reduced.style == .fade)
        #expect(LaunchTimeline(level: .subtle, reduceMotion: true).style == .fade)
        // Sutil: fundido de 0,28 s. Reducir movimiento: la marca aparece en 0,24 s e Inicio se funde en 0,28 s.
        #expect(near(subtle.duration, 0.28))
        #expect(near(reduced.duration, 0.24 + 0.28))
        #expect(subtle.assembleAt == 0)
        #expect(near(reduced.assembleAt, 0.24))
        #expect(subtle.flightAt == nil)
        #expect(reduced.flightAt == nil)
        #expect(subtle.exitDuration == nil)
        #expect(reduced.exitDuration == nil)
        for timeline in [subtle, reduced] {
            for t in samples(timeline) {
                let frame = timeline.frame(at: t)
                // Nada viaja: sin piezas en el aire, sin líneas, sin bandas, sin brillo y sin vuelo.
                #expect(frame.piece == 1)
                #expect(frame.joined)
                #expect(frame.pieceSpeed == 0)
                #expect(frame.lines == nil)
                #expect(frame.sheen == nil)
                #expect(frame.bandDraw.isEmpty)
                #expect(frame.bandWiden.isEmpty)
                #expect(frame.flight == 0)
                #expect(frame.edge == 1)
                #expect(frame.body == 1)
                #expect(frame.name == 1)
                #expect(frame.mark >= 0 && frame.mark <= 1)
                #expect(frame.black >= 0 && frame.black <= 1)
            }
            #expect(timeline.frame(at: timeline.duration).black == 0)
            #expect(timeline.frame(at: timeline.duration).mark == 0)
        }
        // Sutil: la marca está entera desde el primer fotograma. Reducir movimiento: aparece con un fundido.
        #expect(subtle.frame(at: 0).mark == 1)
        #expect(reduced.frame(at: 0).mark == 0)
        #expect(near(reduced.frame(at: 0.12).mark, 0.5))
        #expect(reduced.frame(at: 0.24).mark == 1)
        #expect(reduced.frame(at: 0.2).black == 1)
    }

    /// I-1 (revisión del lote 2): con solo fundido nunca hay dos marcas. Inicio (con la marca pequeña de su barra) solo
    /// se ve donde el negro se aclara, así que la marca grande nunca es más visible que el negro que tiene debajo, y
    /// mientras quede algo de ella el negro está entero: Inicio y su marca no asoman hasta que la grande se ha ido.
    /// También tras un toque que salta el fundido, y en Sutil con Reducir movimiento.
    @Test func aFadeNeverShowsTwoMarks() {
        let both = LaunchTimeline(level: .subtle, reduceMotion: true)
        let balancedReduced = LaunchTimeline(level: .balanced, reduceMotion: true)
        for timeline in [subtle, reduced, both, balancedReduced] {
            for skippedAt in [nil, 0.0, 0.1, 0.3] as [Double?] {
                var brighter: [Double] = []
                var doubled: [String] = []
                for elapsed in stride(from: 0.0, through: timeline.duration + 0.2, by: 0.001) {
                    let frame = timeline.frame(
                        at: timeline.time(elapsed: elapsed, skippedAt: skippedAt), skipped: skippedAt != nil)
                    if frame.mark > frame.black + 1e-9 { brighter.append(elapsed) }
                    // Lo que se ve de Inicio (1 − negro) por lo que se ve de la marca grande: cero en todo instante.
                    if frame.mark * (1 - frame.black) > 1e-9 {
                        doubled.append(String(format: "%.3f s: grande %.2f, Inicio %.2f", elapsed, frame.mark, 1 - frame.black))
                    }
                }
                let name = "\(timeline.level) reducir=\(timeline.reduceMotion) salto=\(skippedAt.map { "\($0)" } ?? "no")"
                #expect(brighter.isEmpty, "\(name): la marca se ve más que el negro en \(brighter.count) instantes")
                #expect(doubled.isEmpty, "\(name): dos marcas a la vez en \(doubled.count) instantes, p. ej. \(doubled.prefix(2))")
            }
            // Sin «fotograma en negro»: en ningún instante están a la vez casi apagadas la marca grande y Inicio (en
            // Sutil, con la curva suave, la cola de la marca dejaba ~40 ms de negro casi total; run7, launch-sutil 5).
            let fadeOutFrom = timeline.reduceMotion ? 0.24 : 0
            var blank: [Double] = []
            for t in stride(from: fadeOutFrom, through: timeline.duration, by: 0.001) {
                let frame = timeline.frame(at: t)
                if max(frame.mark, 1 - frame.black) < 0.1 { blank.append(t) }
            }
            // Como mucho un fotograma de 60 Hz (16,7 ms) en el que no se ve casi nada.
            #expect(blank.count <= 18, "\(timeline.level) reducir=\(timeline.reduceMotion): \(blank.count) ms casi en negro")
            // Y el fundido sigue acabando: sin negro ni marca al final.
            #expect(timeline.frame(at: timeline.duration).black == 0)
            #expect(timeline.frame(at: timeline.duration).mark == 0)
        }
    }

    // MARK: Saltar con un toque

    @Test func skipJumpsToTheFlightAtThirtyPercent() throws {
        for timeline in [expressive, balanced] {
            let flight = try #require(timeline.flightAt)
            for skippedAt in [0.0, 0.05, 0.3, 0.6, flight - 0.01] {
                // En el instante del toque, el guion ya está en el vuelo.
                #expect(near(timeline.time(elapsed: skippedAt, skippedAt: skippedAt), flight))
                // Lo que queda corre a ×0,3: 0,03 s reales son 0,1 s del guion.
                #expect(near(timeline.time(elapsed: skippedAt + 0.03, skippedAt: skippedAt), flight + 0.1))
                let end = timeline.finishesAt(skippedAt: skippedAt)
                #expect(near(end, skippedAt + (timeline.duration - flight) * 0.3))
                #expect(near(timeline.time(elapsed: end, skippedAt: skippedAt), timeline.duration, 1e-6))
                // Saltar nunca alarga: como mucho 0,12 s más.
                #expect(end - skippedAt <= 0.12)
                #expect(end < timeline.duration)
            }
            // Sin salto, el guion es el tiempo real.
            #expect(timeline.time(elapsed: 0.4, skippedAt: nil) == 0.4)
            #expect(timeline.finishesAt(skippedAt: nil) == timeline.duration)
            // Antes del toque, un salto futuro no cambia nada.
            #expect(timeline.time(elapsed: 0.1, skippedAt: 0.5) == 0.1)
        }
    }

    @Test func skippedFramesAreAssembledAndQuiet() throws {
        let flight = try #require(expressive.flightAt)
        let frame = expressive.frame(at: flight, skipped: true)
        #expect(frame.piece == 1)
        #expect(frame.joined)
        #expect(frame.edge == 1)
        #expect(frame.body == 1)
        #expect(frame.name == 1)
        #expect(frame.lines == nil)
        #expect(frame.sheen == nil)
        #expect(frame.bandDraw.isEmpty)
        #expect(frame.flight < 1e-6)
        #expect(near(frame.black, 1, 1e-6))
        #expect(frame.mark == 1)
    }

    @Test func skipOnAFadeJumpsToTheReveal() {
        // Con Reducir movimiento no hay vuelo: el salto va al momento en que Inicio empieza a verse.
        #expect(near(reduced.time(elapsed: 0.1, skippedAt: 0.1), reduced.assembleAt))
        #expect(reduced.finishesAt(skippedAt: 0.1) < reduced.duration)
    }

    @Test func scriptTimeNeverGoesBackwards() {
        for skippedAt in [nil, 0.0, 0.2, 0.7, 1.0, 1.3] as [Double?] {
            var last = -1.0
            for elapsed in stride(from: 0.0, through: 1.6, by: 0.004) {
                let t = expressive.time(elapsed: elapsed, skippedAt: skippedAt)
                #expect(t >= last)
                last = t
            }
        }
    }

    // MARK: Las piezas

    @Test func piecesArriveExactlyAndStay() {
        for timeline in [expressive, balanced] {
            let scale = timeline.level.timeScale
            let start = timeline.frame(at: 0)
            #expect(start.piece == 0)
            #expect(start.pieceOpacity == 0)
            #expect(!start.joined)
            #expect(start.body == 0)
            #expect(start.edge == 0)
            #expect(start.name == 0)
            #expect(start.black == 1)
            #expect(start.mark == 1)
            #expect(start.flight == 0)
            // A mitad de camino siguen en el aire y se mueven (se ve la estela).
            let mid = timeline.frame(at: 0.12 * scale)
            #expect(mid.piece > 0.2 && mid.piece < 0.95)
            #expect(mid.pieceSpeed > 1)
            #expect(mid.pieceOpacity == 1)
            // Encajan exactamente a los 0,56 s del guion y ya no se mueven.
            for t in stride(from: 0.56 * scale + 1e-9, through: timeline.duration, by: 0.01) {
                let frame = timeline.frame(at: t)
                #expect(frame.piece == 1)
                #expect(frame.joined)
                #expect(frame.pieceSpeed == 0)
            }
            // Sin salto brusco al encajar: el fotograma anterior ya está casi en su sitio.
            #expect(abs(timeline.frame(at: 0.559 * scale).piece - 1) < 0.01)
        }
    }

    @Test func piecesNeverJumpBetweenFrames() {
        // A 120 fotogramas por segundo ninguna pieza recorre más del 12 % de su camino entre dos fotogramas.
        for timeline in [expressive, balanced] {
            var last = timeline.frame(at: 0).piece
            for t in stride(from: 1.0 / 120, through: timeline.duration, by: 1.0 / 120) {
                let piece = timeline.frame(at: t).piece
                #expect(abs(piece - last) < 0.12)
                last = piece
            }
        }
    }

    @Test func everythingIsBuiltBeforeTheFlight() throws {
        for timeline in [expressive, balanced] {
            let flight = try #require(timeline.flightAt)
            let frame = timeline.frame(at: flight)
            #expect(frame.joined)
            #expect(frame.edge == 1)
            #expect(frame.body == 1)
            #expect(frame.name == 1)
            #expect(frame.lines == nil)
            #expect(near(frame.black, 1, 1e-6))
            #expect(frame.flight < 1e-6)
        }
    }

    @Test func linesSheenAndBandsHaveTheirWindows() {
        let scale = expressive.level.timeScale
        #expect(expressive.frame(at: 0.3 * scale).lines != nil)
        #expect(expressive.frame(at: 0.63 * scale).lines == nil)
        #expect(expressive.frame(at: 0.6 * scale).sheen == nil)
        #expect(expressive.frame(at: 0.8 * scale).sheen != nil)
        #expect(expressive.frame(at: 0.99 * scale).sheen == nil)
        // Las bandas: nada antes de 0,82; a 0,90 la primera se está trazando; a 1,10 las dos se han ensanchado del todo.
        #expect(expressive.frame(at: 0.81 * scale).bandDraw.allSatisfy { $0 == 0 })
        let drawing = expressive.frame(at: 0.90 * scale)
        #expect(drawing.bandDraw.count == 2)
        #expect(drawing.bandDraw[0] > 0 && drawing.bandDraw[0] < 1)
        #expect(drawing.bandDraw[0] > drawing.bandDraw[1])
        let wide = expressive.frame(at: 1.10 * scale)
        #expect(wide.bandDraw == [1, 1])
        #expect(wide.bandWiden == [1, 1])
    }

    // MARK: El vuelo y el final

    @Test func flightLandsAndTheLayerEndsEmpty() throws {
        for timeline in [expressive, balanced] {
            let flight = try #require(timeline.flightAt)
            var last = 1.0
            for t in stride(from: flight, through: timeline.duration, by: 0.005) {
                let frame = timeline.frame(at: t)
                // El negro solo se aclara.
                #expect(frame.black <= last + 1e-9)
                last = frame.black
            }
            let mid = timeline.frame(at: flight + (timeline.duration - flight) * 0.4)
            #expect(mid.flight > 0.3 && mid.flight < 1.05)
            #expect(mid.mark == 1)
            let end = timeline.frame(at: timeline.duration)
            // Al final la marca está EXACTAMENTE en su ranura y la capa ya no pinta nada.
            #expect(end.flight == 1)
            #expect(end.black == 0)
            #expect(end.mark == 0)
            let after = timeline.frame(at: timeline.duration + 5)
            #expect(after.black == 0)
            #expect(after.mark == 0)
            #expect(after.flight == 1)
        }
    }

    /// La marca que vuela aterriza en la ranura de la barra de Inicio, que aparece en ese mismo instante: el último
    /// fotograma del vuelo es exactamente 1 (ni un punto antes ni después), llega sin salto y sin pasarse más de un 6 %.
    @Test func theFlightEndsExactlyOnTheSlot() throws {
        for timeline in [expressive, balanced] {
            let flight = try #require(timeline.flightAt)
            var previous = 0.0
            var highest = 0.0
            for t in stride(from: flight, through: timeline.duration, by: 0.001) {
                let now = timeline.frame(at: t).flight
                #expect(abs(now - previous) < 0.02, "el vuelo salta en \(t)")
                previous = now
                highest = max(highest, now)
            }
            #expect(highest < 1.06)
            #expect(abs(previous - 1) < 0.02)
            #expect(timeline.frame(at: timeline.duration).flight == 1)
            // Lo mismo tras un toque que lo salta, y en la salida del bloqueo.
            #expect(timeline.frame(at: timeline.duration, skipped: true).flight == 1)
            let exit = try #require(timeline.exitDuration)
            #expect(timeline.exitFrame(at: exit, bands: true).flight == 1)
            #expect(timeline.exitFrame(at: exit + 3, bands: false).flight == 1)
            var before = 0.0
            for t in stride(from: 0.0, through: exit, by: 0.001) {
                let now = timeline.exitFrame(at: t, bands: false).flight
                #expect(abs(now - before) < 0.02, "la salida salta en \(t)")
                before = now
            }
        }
    }

    @Test func lowPowerKeepsThePiecesButDropsLinesBandsAndSheen() {
        let lowPower = LaunchTimeline(level: .expressive, reduceMotion: false, lowPower: true)
        #expect(lowPower.style == .pieces)
        #expect(lowPower.duration == expressive.duration)
        for t in samples(lowPower) {
            let frame = lowPower.frame(at: t)
            #expect(frame.lines == nil)
            #expect(frame.sheen == nil)
            #expect(frame.bandDraw.isEmpty)
            #expect(frame.bandWiden.isEmpty)
        }
        #expect(lowPower.frame(at: 0.15).piece > 0)
        #expect(lowPower.frame(at: 0.15).piece < 1)
    }

    // MARK: En el bloqueo

    @Test func lockAssemblesButNeverFliesNorUncovers() {
        for timeline in [expressive, balanced] {
            #expect(near(timeline.lockDuration, 0.98 * timeline.level.timeScale))
            for t in stride(from: 0.0, through: 3.0, by: 0.01) {
                let frame = timeline.lockFrame(at: t)
                #expect(frame.flight == 0)
                #expect(frame.black == 1)
                #expect(frame.mark == 1)
                #expect(frame.bandDraw.isEmpty)
            }
            // Empieza con las piezas fuera y acaba con la marca entera, quieta.
            #expect(timeline.lockFrame(at: 0).piece == 0)
            let done = timeline.lockFrame(at: timeline.lockDuration)
            #expect(done.joined && done.edge == 1 && done.body == 1 && done.name == 1)
            #expect(done.sheen == nil)
            #expect(done.lines == nil)
            #expect(timeline.lockFrame(at: 60) == done)
        }
    }

    @Test func lockIsStaticWithReduceMotionAndFadesInAtSubtle() {
        #expect(reduced.lockDuration == 0)
        #expect(reduced.lockFrame(at: 0) == reduced.lockFrame(at: 10))
        #expect(reduced.lockFrame(at: 0).mark == 1)
        #expect(reduced.lockFrame(at: 0).joined)
        #expect(near(subtle.lockDuration, 0.28))
        #expect(subtle.lockFrame(at: 0).mark == 0)
        #expect(subtle.lockFrame(at: 0.28).mark == 1)
        #expect(subtle.lockFrame(at: 0.14).joined)
    }

    // MARK: La salida tras desbloquear

    @Test func exitFliesFromAnAssembledMark() throws {
        for timeline in [expressive, balanced] {
            let duration = try #require(timeline.exitDuration)
            #expect(near(duration, (1.20 - 0.82) * timeline.level.timeScale))
            let start = timeline.exitFrame(at: 0, bands: true)
            #expect(start.joined && start.edge == 1 && start.body == 1 && start.name == 1)
            #expect(start.flight == 0)
            #expect(start.mark == 1)
            #expect(start.sheen == nil)
            #expect(start.lines == nil)
            let end = timeline.exitFrame(at: duration, bands: true)
            #expect(end.flight == 1)
            #expect(end.mark == 0)
            #expect(end.black == 0)
            // Sin bandas (desbloqueo que no es el arranque en frío): solo vuela la marca.
            for t in stride(from: 0.0, through: duration, by: 0.01) {
                #expect(timeline.exitFrame(at: t, bands: false).bandDraw.isEmpty)
            }
            #expect(!timeline.exitFrame(at: duration * 0.5, bands: true).bandDraw.isEmpty)
        }
    }

    // MARK: El muelle

    @Test func springStepResponse() {
        #expect(LaunchTimeline.spring(0, response: 0.5, dampingFraction: 0.88) == 0)
        #expect(LaunchTimeline.spring(-1, response: 0.5, dampingFraction: 0.88) == 0)
        #expect(abs(LaunchTimeline.spring(3, response: 0.5, dampingFraction: 0.88) - 1) < 1e-6)
        #expect(abs(LaunchTimeline.spring(3, response: 0.5, dampingFraction: 1) - 1) < 1e-6)
        // Con rebote se pasa de 1 en algún momento; sin rebote, nunca.
        let bouncy = stride(from: 0.0, through: 1.5, by: 0.005).map { LaunchTimeline.spring($0, response: 0.5, dampingFraction: 0.6) }
        #expect((bouncy.max() ?? 0) > 1.01)
        let calm = stride(from: 0.0, through: 1.5, by: 0.005).map { LaunchTimeline.spring($0, response: 0.5, dampingFraction: 1) }
        #expect((calm.max() ?? 0) <= 1)
        // Una respuesta no válida no divide por cero.
        #expect(LaunchTimeline.spring(0.2, response: 0, dampingFraction: 0.8) == 1)
    }
}
