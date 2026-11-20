import Foundation
import Testing
@testable import MiBancoCore

private let madrid: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return c
}()

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    madrid.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private let now = at(2026, 11, 20, 12)

private func status(_ l: BankLinkInfo?, estimated: Bool? = false, canConnect: Bool = true) -> BankStatusLines {
    bankStatusLines(bank: .rev, link: l, estimated: estimated, canConnect: canConnect, now: now, calendar: madrid)
}

private func link(validUntil: Date) -> BankLinkInfo {
    BankLinkInfo(connectedAt: at(2026, 11, 1), consentValidUntil: validUntil)
}

@Suite struct BankStatusTextTests {
    @Test func expiredConsentStatus() {
        #expect(status(link(validUntil: at(2026, 11, 19)))
            == BankStatusLines(primary: "La conexión caducó el 19 nov",
                               secondary: "Renuévala para ver el saldo exacto", action: .renew))
    }

    @Test func okStatus() {
        var l = link(validUntil: at(2027, 5, 19))
        l.lastSuccessAt = at(2026, 11, 20, 11, 55)
        #expect(status(l) == BankStatusLines(primary: "Actualizado hace 5 min · exacto",
                                             secondary: "Caduca el 19 may 2027", action: .refresh))
        #expect(status(l, estimated: true).primary == "Actualizado hace 5 min · estimado")
    }

    @Test func soonStatus() {
        var l = link(validUntil: at(2026, 11, 29, 12))
        l.lastSuccessAt = at(2026, 11, 20, 11, 55)
        let s = status(l)
        #expect(s.secondary == "Caduca en 9 días")
        #expect(s.action == .renew)
        l.consentValidUntil = at(2026, 11, 21, 9)
        #expect(status(l).secondary == "Caduca mañana")
        l.consentValidUntil = at(2026, 11, 20, 20)
        #expect(status(l).secondary == "Caduca hoy")
    }

    @Test func rateLimitedStatus() {
        var m = link(validUntil: at(2027, 5, 19)).recordingFailure(.rateLimited, at: now)
        m.backoffUntil = at(2026, 11, 20, 18, 30)
        let s = status(m)
        #expect(s.primary == "El banco ha pedido esperar · vuelve a las 18:30")
        #expect(s.action == nil)
    }

    @Test func otherProblemsAndConnecting() {
        var l = link(validUntil: at(2027, 5, 19))
        #expect(status(l) == BankStatusLines(primary: "Conectado · actualizando…",
                                             secondary: "Caduca el 19 may 2027", action: nil))
        l.problem = .offline
        #expect(status(l).primary == "No se pudo actualizar · lo intentamos al abrir la app")
        #expect(status(l).action == .refresh)
        l.problem = .keyRejected
        #expect(status(l) == BankStatusLines(primary: "Enable Banking no acepta la clave",
                                             secondary: "Revisa la conexión en Ajustes", action: .renew))
    }

    @Test func notConnectedStatus() {
        #expect(status(nil) == BankStatusLines(primary: "Sin conectar", secondary: nil, action: .connect))
    }

    @Test func trStatus() {
        #expect(status(nil, canConnect: false)
            == BankStatusLines(primary: "Importa su extracto", secondary: nil, action: .importStatement))
    }

    @Test func relative() {
        func r(_ d: Date) -> String { relativeUpdated(d, now: now, calendar: madrid) }
        #expect(r(now.addingTimeInterval(-30)) == "hace un momento")
        #expect(r(now.addingTimeInterval(-7_200)) == "hace 2 h")
        #expect(r(at(2026, 11, 19, 18, 30)) == "ayer a las 18:30")
        #expect(r(at(2026, 11, 12)) == "el 12 nov")
    }

    @Test func shortDate() {
        #expect(shortSpanishDate(at(2026, 9, 3), calendar: madrid, withYear: false) == "3 sept")
        #expect(shortSpanishDate(at(2027, 1, 3), calendar: madrid, withYear: true) == "3 ene 2027")
    }
}

@Suite struct BankStatusRound1Tests {
    @Test func revokedEarlyShowsToday() {
        var l = link(validUntil: at(2027, 5, 19))
        l.problem = .consentExpired
        let s = status(l)
        #expect(s.primary == "La conexión caducó el 20 nov")
        #expect(s.action == .renew)
    }

    @Test func expiredInEarlierYearShowsYear() {
        #expect(status(link(validUntil: at(2025, 12, 31))).primary == "La conexión caducó el 31 dic 2025")
    }

    @Test func unknownWithWaitSaysLater() {
        var l = link(validUntil: at(2027, 5, 19))
        l = l.recordingFailure(.unknown, at: now)
        #expect(status(l).primary == "No se pudo actualizar · lo intentamos más tarde")
    }

    @Test func relativeBoundaries() {
        func r(_ s: TimeInterval) -> String { relativeUpdated(now.addingTimeInterval(-s), now: now, calendar: madrid) }
        #expect(r(59) == "hace un momento")
        #expect(r(60) == "hace 1 min")
        #expect(r(3_599) == "hace 59 min")
        #expect(r(3_600) == "hace 1 h")
        #expect(r(86_400) == "ayer a las 12:00")
    }
}
