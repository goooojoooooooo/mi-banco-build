import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0,
                calendar: Calendar = cal) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func nov(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    at(2026, 11, day, hour, minute, second)
}

@Suite struct MorningReminderTests {
    @Test func fechasDelRecordatorioSegunHoraYSiYaSalioHoy() {
        // Antes de las 08:30 y sin haber salido hoy -> hoy, mañana y pasado.
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 510, shownToday: false, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])

        // Un segundo antes (08:29:59) -> incluye las 08:30:00 de hoy.
        #expect(morningReminderDates(now: nov(20, 8, 29, 59), minutes: 510, shownToday: false, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])

        // Después de las 08:30 -> empieza mañana.
        #expect(morningReminderDates(now: nov(20, 9, 0), minutes: 510, shownToday: false, calendar: cal)
            == [nov(21, 8, 30), nov(22, 8, 30), nov(23, 8, 30)])

        // Justo a la hora exacta (08:30:00) -> no programa en el pasado/presente, empieza mañana.
        #expect(morningReminderDates(now: nov(20, 8, 30), minutes: 510, shownToday: false, calendar: cal)
            == [nov(21, 8, 30), nov(22, 8, 30), nov(23, 8, 30)])

        // Antes de las 08:30 pero ya salió hoy -> empieza mañana.
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 510, shownToday: true, calendar: cal)
            == [nov(21, 8, 30), nov(22, 8, 30), nov(23, 8, 30)])
    }

    @Test func fronterasDeLasCincoYMadrugada() {
        // 01:30 y 04:59 del 20 nov todavía son día de resumen 19 nov: las 08:30 del 20 sí tocan aunque el del 19 ya saliera.
        #expect(morningReminderDates(now: nov(20, 1, 30), minutes: 510, shownToday: true, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])
        #expect(morningReminderDates(now: nov(20, 4, 59), minutes: 510, shownToday: true, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])

        // A las 05:00 ya empezó el día de resumen del 20: con `shownToday: true`, las 08:30 del 20 se saltan.
        #expect(morningReminderDates(now: nov(20, 5, 0), minutes: 510, shownToday: true, calendar: cal)
            == [nov(21, 8, 30), nov(22, 8, 30), nov(23, 8, 30)])

        // Hora de recordatorio de madrugada (02:00):
        // - A las 01:30 con shownToday -> 02:00 del 20 pertenece al día 19 (ya mostrado), empieza el 21.
        #expect(morningReminderDates(now: nov(20, 1, 30), minutes: 120, shownToday: true, calendar: cal)
            == [nov(21, 2, 0), nov(22, 2, 0), nov(23, 2, 0)])
        // - A las 07:00 del 20 (día 20): 02:00 del 21 sigue siendo día de resumen 20.
        //   Con shownToday == true se salta y empieza el 22; con shownToday == false empieza el 21.
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 120, shownToday: true, calendar: cal)
            == [nov(22, 2, 0), nov(23, 2, 0), nov(24, 2, 0)])
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 120, shownToday: false, calendar: cal)
            == [nov(21, 2, 0), nov(22, 2, 0), nov(23, 2, 0)])
    }

    @Test func cambioDeAnioBisiestoCambioDeHoraYOtrasZonas() {
        // Salto de año: 30 dic -> 31 dic, 1 ene, 2 ene.
        #expect(morningReminderDates(now: at(2026, 12, 30, 10, 0), minutes: 510, shownToday: false, calendar: cal)
            == [at(2026, 12, 31, 8, 30), at(2027, 1, 1, 8, 30), at(2027, 1, 2, 8, 30)])

        // Año bisiesto (2028): incluye 29 feb.
        #expect(morningReminderDates(now: at(2028, 2, 28, 10, 0), minutes: 510, shownToday: false, calendar: cal)
            == [at(2028, 2, 29, 8, 30), at(2028, 3, 1, 8, 30), at(2028, 3, 2, 8, 30)])

        // Cambio de hora de primavera en Madrid (29 mar 2026: 02:00 salta a 03:00).
        let spring = morningReminderDates(now: at(2026, 3, 28, 10, 0), minutes: 510, shownToday: false, calendar: cal)
        #expect(spring == [at(2026, 3, 29, 8, 30), at(2026, 3, 30, 8, 30), at(2026, 3, 31, 8, 30)])

        // Hora inexistente (02:30 el 29 mar 2026): desde 01:30 CET y desde 03:05 CEST produce 3 fechas crecientes > now.
        let fromEarly = at(2026, 3, 29, 1, 30)
        let springFromEarly = morningReminderDates(now: fromEarly, minutes: 150, shownToday: false, calendar: cal)
        #expect(springFromEarly.count == 3 && springFromEarly[0] > fromEarly)
        #expect(springFromEarly[0] < springFromEarly[1] && springFromEarly[1] < springFromEarly[2])

        let fromAfterJump = at(2026, 3, 29, 3, 5)
        let springFromAfter = morningReminderDates(now: fromAfterJump, minutes: 150, shownToday: false, calendar: cal)
        #expect(springFromAfter.count == 3 && springFromAfter[0] > fromAfterJump)
        #expect(springFromAfter[0] < springFromAfter[1] && springFromAfter[1] < springFromAfter[2])

        // Cambio de hora de otoño (25 oct 2026: 02:00-03:00 repetida; 02:30 primera +0200 = 00:30Z, segunda +0100 = 01:30Z).
        let autumn = morningReminderDates(now: at(2026, 10, 24, 10, 0), minutes: 510, shownToday: false, calendar: cal)
        #expect(autumn == [at(2026, 10, 25, 8, 30), at(2026, 10, 26, 8, 30), at(2026, 10, 27, 8, 30)])

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let first0215 = at(2026, 10, 25, 0, 15, calendar: utcCal)   // 02:15 +0200 Madrid
        let first0230 = at(2026, 10, 25, 0, 30, calendar: utcCal)   // 02:30 +0200 Madrid
        let second0215 = at(2026, 10, 25, 1, 15, calendar: utcCal)  // 02:15 +0100 Madrid
        let fromFirst0215 = morningReminderDates(now: first0215, minutes: 150, shownToday: false, calendar: cal)
        #expect(fromFirst0215 == [first0230, at(2026, 10, 26, 2, 30), at(2026, 10, 27, 2, 30)])
        // Ya pasada la primera 02:30 (a las 02:30 +0200 o en la segunda 02:15 +0100) no dispara dos veces el 25 oct.
        #expect(morningReminderDates(now: first0230, minutes: 150, shownToday: false, calendar: cal)
            == [at(2026, 10, 26, 2, 30), at(2026, 10, 27, 2, 30), at(2026, 10, 28, 2, 30)])
        #expect(morningReminderDates(now: second0215, minutes: 150, shownToday: false, calendar: cal)
            == [at(2026, 10, 26, 2, 30), at(2026, 10, 27, 2, 30), at(2026, 10, 28, 2, 30)])

        // Zonas distintas de Madrid (respeta el calendario recibido, nunca Calendar.current).
        for tzID in ["UTC", "America/New_York", "Asia/Tokyo"] {
            var tzCal = Calendar(identifier: .gregorian)
            tzCal.timeZone = TimeZone(identifier: tzID)!
            let localNow = at(2026, 11, 20, 7, 0, calendar: tzCal)
            let localDates = morningReminderDates(now: localNow, minutes: 510, shownToday: false, calendar: tzCal)
            #expect(localDates == [
                at(2026, 11, 20, 8, 30, calendar: tzCal),
                at(2026, 11, 21, 8, 30, calendar: tzCal),
                at(2026, 11, 22, 8, 30, calendar: tzCal),
            ], "\(tzID)")
        }
    }

    @Test func minutosFueraDeRangoCaenAOchoYMedia() {
        for invalid in [Int.min, -10, -1, 1_440, Int.max] {
            #expect(morningReminderDates(now: nov(20, 7, 0), minutes: invalid, shownToday: false, calendar: cal)
                == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)], "\(invalid)")
        }
        #expect(formatMinutesOfDay(0) == "00:00")
        #expect(formatMinutesOfDay(510) == "08:30")
        #expect(formatMinutesOfDay(1_439) == "23:59")
        #expect(formatMinutesOfDay(-5) == "08:30")
        #expect(morningReminderSubtitle(minutes: 510) == "A las 08:30, con lo que ha pasado.")
    }

    @Test func avisoDeLaMananaSinCifras() {
        #expect(morningReminderText.title == "Tu resumen de hoy")
        #expect(morningReminderText.body == "Mira qué ha pasado desde ayer.")
        for part in [morningReminderText.title, morningReminderText.body] {
            #expect(!part.contains { $0.isNumber }, "\(part)")
            #expect(!part.contains("€") && !part.contains("%"), "\(part)")
            #expect(!containsNumber(part), "\(part)")
            #expect(!containsAdvice(part), "\(part)")
        }
    }

    @Test func ajustesAntiguos() throws {
        // JSON antiguo sin las dos claves nuevas -> true y 510 (08:30).
        let legacyJSON = #"{"everyMovement":false,"lowBalance":true}"#
        let legacy = try JSONDecoder().decode(AlertSettings.self, from: Data(legacyJSON.utf8))
        #expect(!legacy.everyMovement)
        #expect(legacy.morningBriefing)
        #expect(legacy.morningBriefingMinutes == defaultMorningBriefingMinutes)

        // Valores corruptos, null, decimales o fuera de rango -> caen a los valores por defecto sin romper la carga.
        for badJSON in [
            #"{"morningBriefing":"si","morningBriefingMinutes":9999}"#,
            #"{"morningBriefing":null,"morningBriefingMinutes":null}"#,
            #"{"morningBriefingMinutes":510.5}"#,
            #"{"morningBriefingMinutes":-1}"#,
            #"{"morningBriefingMinutes":1440}"#,
        ] {
            let decoded = try JSONDecoder().decode(AlertSettings.self, from: Data(badJSON.utf8))
            #expect(decoded.morningBriefing, "\(badJSON)")
            #expect(decoded.morningBriefingMinutes == defaultMorningBriefingMinutes, "\(badJSON)")
        }

        // Mutación directa fuera de rango (como en `Ledger.updateAlertSettings`) mantiene el invariante 0..<1440 y la igualdad Codable.
        var mutated = AlertSettings(morningBriefing: false, morningBriefingMinutes: 465)
        mutated.morningBriefingMinutes = 1_440
        #expect(mutated.morningBriefingMinutes == defaultMorningBriefingMinutes)
        mutated.morningBriefingMinutes = -1
        #expect(mutated.morningBriefingMinutes == defaultMorningBriefingMinutes)
        mutated.morningBriefingMinutes = 465

        let roundTrip = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(mutated))
        #expect(roundTrip == mutated)
        #expect(AlertSettings(morningBriefingMinutes: -1).morningBriefingMinutes == defaultMorningBriefingMinutes)

        // Ida y vuelta a través de `encodeBackup`/`decodeBackup` conserva los ajustes del aviso de la mañana.
        var state = LedgerState()
        state.alertSettings = mutated
        let backupData = try encodeBackup(state, portfolio: nil, exportedAt: nov(20, 10))
        let restored = try decodeBackup(backupData)
        #expect(restored.ledger.alertSettings == mutated)
    }
}
