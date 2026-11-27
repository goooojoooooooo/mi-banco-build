import Testing
@testable import MiBancoCore

/// La barra de pestañas en la pantalla de un banco: histéresis 5 % / 2 % (lote de cierre, ronda 1, m-3).
@Suite struct BankTabBarRuleTests {
    @Test func seEscondeAlPasarDel5() {
        #expect(!BankTabBarRule.hides(progress: 0, hiddenNow: false))
        #expect(!BankTabBarRule.hides(progress: 0.03, hiddenNow: false))
        #expect(!BankTabBarRule.hides(progress: 0.05, hiddenNow: false))
        #expect(BankTabBarRule.hides(progress: 0.051, hiddenNow: false))
        #expect(BankTabBarRule.hides(progress: 1, hiddenNow: false))
    }

    @Test func noVuelveHastaBajarDel2() {
        #expect(BankTabBarRule.hides(progress: 0.03, hiddenNow: true), "entre el 2 % y el 5 % se queda escondida")
        #expect(BankTabBarRule.hides(progress: 0.021, hiddenNow: true))
        #expect(!BankTabBarRule.hides(progress: 0.02, hiddenNow: true))
        #expect(!BankTabBarRule.hides(progress: 0.019, hiddenNow: true))
        #expect(!BankTabBarRule.hides(progress: 0, hiddenNow: true))
    }

    /// Un dedo que tiembla alrededor del 5 % no la hace parpadear: una vez escondida, sigue escondida.
    @Test func unDedoQuietoEnElUmbralNoParpadea() {
        var hidden = false
        var changes = 0
        for p in [0.049, 0.051, 0.049, 0.052, 0.048, 0.051, 0.047] {
            let now = BankTabBarRule.hides(progress: p, hiddenNow: hidden)
            if now != hidden { changes += 1 }
            hidden = now
        }
        #expect(changes == 1)
        #expect(hidden)
    }

    @Test func valoresRaros() {
        #expect(!BankTabBarRule.hides(progress: .nan, hiddenNow: true))
        #expect(!BankTabBarRule.hides(progress: -.infinity, hiddenNow: false))
        #expect(BankTabBarRule.hides(progress: 7, hiddenNow: false))
    }
}
