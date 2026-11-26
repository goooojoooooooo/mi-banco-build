import Testing
@testable import MiBancoCore

/// 377475 = 3.774,75 € y 376995 = 3.769,95 € (un pago de 4,80 €).
@Suite struct AmountRevealTests {
    static let before = 377_475
    static let after = 376_995

    /// El ojo se abre, llega un pago dentro del barajado y el barajado acaba: se rueda al importe de ahora.
    @Test func changeInsideOpeningScrambleRollsToTheLatest() {
        var r = AmountReveal(cents: Self.before, hidden: true)
        guard case .startScramble(let gen) = r.apply(.eyeChanged(hidden: false), reduceMotion: false) else {
            Issue.record("Abrir el ojo debe empezar el barajado")
            return
        }
        #expect(r.apply(.valueChanged(Self.after), reduceMotion: false) == .none)
        #expect(r.drawn == .scramble)
        #expect(r.apply(.scrambleEnded(generation: gen), reduceMotion: false) == .rollTo(Self.after))
        #expect(r.drawn == .real)
        #expect(r.target == Self.after)
    }

    /// Cierra el ojo, llega el pago con el ojo cerrado (dentro del barajado o ya con puntos), lo abre: sale el pago.
    @Test(arguments: [false, true])
    func changeWhileHiddenShowsTheLatestOnOpening(settleDotsFirst: Bool) {
        var r = AmountReveal(cents: Self.before, hidden: false)
        // Ronda 1 (m-4): cerrar el ojo no baraja: puntos en el acto.
        #expect(r.apply(.eyeChanged(hidden: true), reduceMotion: false) == .showDots)
        #expect(r.drawn == .dots)
        if settleDotsFirst {
            // Un «barajado terminado» tardío (de una apertura anterior) no cambia nada.
            #expect(r.apply(.scrambleEnded(generation: r.generation), reduceMotion: false) == .none)
            #expect(r.drawn == .dots)
        }
        #expect(r.apply(.valueChanged(Self.after), reduceMotion: false) == .none)
        #expect(r.drawn != .real)
        guard case .startScramble(let opening) = r.apply(.eyeChanged(hidden: false), reduceMotion: false) else {
            Issue.record("Abrir el ojo debe empezar el barajado")
            return
        }
        #expect(r.apply(.scrambleEnded(generation: opening), reduceMotion: false) == .rollTo(Self.after))
        #expect(r.drawn == .real)
    }

    /// Dos cambios de ojo dentro de un mismo barajado: manda el último.
    @Test func twoTogglesInsideOneScramble() {
        // Abrir, cerrar, abrir (empezando cerrado): acaba en `real` con el importe.
        var a = AmountReveal(cents: Self.before, hidden: true)
        a.apply(.eyeChanged(hidden: false), reduceMotion: false)
        a.apply(.eyeChanged(hidden: true), reduceMotion: false)
        let last = a.apply(.eyeChanged(hidden: false), reduceMotion: false)
        guard case .startScramble(let genA) = last else {
            Issue.record("El último cambio debe empezar el barajado")
            return
        }
        #expect(a.apply(.scrambleEnded(generation: genA), reduceMotion: false) == .rollTo(Self.before))
        #expect(a.drawn == .real)
        #expect(a.target == Self.before)

        // Cerrado, abrir, cerrar: acaba en puntos y en ningún momento se dibujó la cifra real.
        var b = AmountReveal(cents: Self.before, hidden: true)
        var seen: [AmountReveal.Drawn] = [b.drawn]
        b.apply(.eyeChanged(hidden: false), reduceMotion: false); seen.append(b.drawn)
        let closed = b.apply(.eyeChanged(hidden: true), reduceMotion: false); seen.append(b.drawn)
        #expect(closed == .showDots, "Cerrar el ojo debe poner los puntos en el acto")
        #expect(b.drawn == .dots)
        #expect(!seen.contains(.real))
    }

    /// Reducir movimiento: el importe llega con el ojo cerrado, al abrir se funde a él y no hay barajado.
    @Test func reduceMotionCrossFadesAndNeverScrambles() {
        var r = AmountReveal(cents: Self.before, hidden: true)
        #expect(r.apply(.valueChanged(Self.after), reduceMotion: true) == .none)
        #expect(r.apply(.eyeChanged(hidden: false), reduceMotion: true) == .crossFadeTo(Self.after))
        #expect(r.drawn == .real)
        #expect(r.scramblePending == false)
        // Con el ojo abierto un cambio también se funde.
        #expect(r.apply(.valueChanged(Self.before), reduceMotion: true) == .crossFadeTo(Self.before))
        #expect(r.apply(.eyeChanged(hidden: true), reduceMotion: true) == .showDots)
        #expect(r.drawn == .dots)
    }

    /// Un «barajado terminado» de un temporizador cancelado no cambia nada.
    @Test func staleScrambleEndedChangesNothing() {
        var r = AmountReveal(cents: Self.before, hidden: true)
        guard case .startScramble(let old) = r.apply(.eyeChanged(hidden: false), reduceMotion: false) else {
            Issue.record("Abrir el ojo debe empezar un barajado")
            return
        }
        #expect(r.apply(.eyeChanged(hidden: true), reduceMotion: false) == .showDots)
        let snapshot = r
        #expect(r.apply(.scrambleEnded(generation: old), reduceMotion: false) == .none)
        #expect(r == snapshot)
        // Y repetido, tampoco.
        #expect(r.apply(.scrambleEnded(generation: r.generation), reduceMotion: false) == .none)
        #expect(r == snapshot)
    }

    /// El primer fotograma tras tocar el ojo (el valor ya es true, el evento aún no): nunca la cifra real.
    @Test func displayedNeverShowsRealWhileTheInputIsHidden() {
        let r = AmountReveal(cents: Self.before, hidden: false)
        #expect(r.displayed(hiddenInput: false, reduceMotion: false) == .real)
        // Ronda 1 (m-4): ni barajado: puntos.
        #expect(r.displayed(hiddenInput: true, reduceMotion: false) == .dots)
        #expect(r.displayed(hiddenInput: true, reduceMotion: true) == .dots)
    }

    /// Todas las secuencias de hasta 6 eventos, con Reducir movimiento puesto y quitado, desde cerrado y desde abierto.
    @Test func exhaustiveSequencesKeepThePrivacyAndValueInvariants() {
        enum E: CaseIterable { case valueBefore, valueAfter, hide, show, end }
        var checked = 0
        for reduce in [false, true] {
            for startHidden in [false, true] {
                func walk(_ state: AmountReveal, _ depth: Int, _ path: [E]) {
                    // Estado final de esta secuencia.
                    if state.hidden { #expect(state.drawn != .real, "Cifra real con el ojo cerrado: \(path)") }
                    // Ronda 1 (m-4): con el ojo cerrado, ni dígitos al azar.
                    if state.hidden { #expect(state.drawn == .dots, "Algo que no son puntos con el ojo cerrado: \(path)") }
                    if reduce { #expect(state.drawn != .scramble, "Barajado con Reducir movimiento: \(path)") }
                    if !state.hidden, !state.scramblePending {
                        #expect(state.drawn == .real, "Abierto sin barajado pendiente y sin cifra real: \(path)")
                        #expect(state.target == state.latest, "La cifra dibujada no es la última: \(path)")
                    }
                    checked += 1
                    guard depth < 6 else { return }
                    for e in E.allCases {
                        var next = state
                        let event: AmountReveal.Event = switch e {
                        case .valueBefore: .valueChanged(Self.before)
                        case .valueAfter: .valueChanged(Self.after)
                        case .hide: .eyeChanged(hidden: true)
                        case .show: .eyeChanged(hidden: false)
                        case .end: .scrambleEnded(generation: next.generation)
                        }
                        let action = next.apply(event, reduceMotion: reduce)
                        switch action {
                        case .rollTo(let c), .crossFadeTo(let c):
                            #expect(c == next.latest && !next.hidden, "Rueda a una cifra vieja o con el ojo cerrado: \(path + [e])")
                        case .showDots:
                            #expect(next.drawn == .dots, "showDots sin puntos: \(path + [e])")
                        default: break
                        }
                        walk(next, depth + 1, path + [e])
                    }
                }
                walk(AmountReveal(cents: Self.before, hidden: startHidden), 0, [])
            }
        }
        // 2 × 2 × (5^0 + … + 5^6) secuencias.
        #expect(checked == 4 * 19_531)
    }
}
