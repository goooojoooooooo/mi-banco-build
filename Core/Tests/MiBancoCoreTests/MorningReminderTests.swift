import Foundation
import Testing
@testable import MiBancoCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Madrid")!
    c.locale = Locale(identifier: "es_ES")
    return c
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    at(2026, 11, day, hour, minute)
}

@Suite struct MorningReminderTests {
    @Test func fechasDelRecordatorioSegunHoraYSiYaSalioHoy() {
        // Antes de las 08:30 y sin haber salido hoy -> hoy, mañana y pasado.
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 510, shownToday: false, calendar: cal)
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

    @Test func madrugadaPerteneceADiaDeResumenAnterior() {
        // 01:30 del 20 nov todavía es día de resumen 19 nov; aunque el del 19 ya saliera, las 08:30 del 20 sí tocan.
        #expect(morningReminderDates(now: nov(20, 1, 30), minutes: 510, shownToday: true, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])

        // Si el usuario eligió una hora de madrugada (02:00) y ya salió el resumen de ese día de resumen, las 02:00 del 20 se saltan.
        #expect(morningReminderDates(now: nov(20, 1, 30), minutes: 120, shownToday: true, calendar: cal)
            == [nov(21, 2, 0), nov(22, 2, 0), nov(23, 2, 0)])
    }

    @Test func cambioDeAnioYCambioDeHora() {
        // Salto de año: 30 dic -> 31 dic, 1 ene, 2 ene.
        #expect(morningReminderDates(now: at(2026, 12, 30, 10, 0), minutes: 510, shownToday: false, calendar: cal)
            == [at(2026, 12, 31, 8, 30), at(2027, 1, 1, 8, 30), at(2027, 1, 2, 8, 30)])

        // Cambio de hora de primavera en Madrid (29 mar 2026: 02:00 salta a 03:00) y de otoño (25 oct 2026).
        let spring = morningReminderDates(now: at(2026, 3, 28, 10, 0), minutes: 510, shownToday: false, calendar: cal)
        #expect(spring == [at(2026, 3, 29, 8, 30), at(2026, 3, 30, 8, 30), at(2026, 3, 31, 8, 30)])

        // Incluso eligiendo 02:30 el día en que no existe las 02:30, devuelve 3 fechas crecientes válidas.
        let springGap = morningReminderDates(now: at(2026, 3, 28, 10, 0), minutes: 150, shownToday: false, calendar: cal)
        #expect(springGap.count == 3)
        #expect(springGap[0] < springGap[1] && springGap[1] < springGap[2])

        let autumn = morningReminderDates(now: at(2026, 10, 24, 10, 0), minutes: 510, shownToday: false, calendar: cal)
        #expect(autumn == [at(2026, 10, 25, 8, 30), at(2026, 10, 26, 8, 30), at(2026, 10, 27, 8, 30)])
    }

    @Test func minutosFueraDeRangoCaenAOchoYMedia() {
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: -10, shownToday: false, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])
        #expect(morningReminderDates(now: nov(20, 7, 0), minutes: 1_440, shownToday: false, calendar: cal)
            == [nov(20, 8, 30), nov(21, 8, 30), nov(22, 8, 30)])
        #expect(formatMinutesOfDay(0) == "00:00")
        #expect(formatMinutesOfDay(510) == "08:30")
        #expect(formatMinutesOfDay(1_439) == "23:59")
        #expect(formatMinutesOfDay(-5) == "08:30")
        #expect(morningReminderSubtitle(minutes: 510) == "A las 08:30, con lo que ha pasado.")
    }

    @Test func avisoDeLaMananaSinCifrasNiConsejos() {
        #expect(morningReminderText.title == "Tu resumen de hoy")
        #expect(morningReminderText.body == "Mira qué ha pasado desde ayer.")
        for part in [morningReminderText.title, morningReminderText.body] {
            #expect(!part.contains { $0.isNumber }, "\(part)")
            #expect(!part.contains("€") && !part.contains("%"), "\(part)")
            #expect(!containsNumber(part), "\(part)")
            #expect(!containsAdvice(part), "\(part)")
        }
    }

    @Test func ajustesAntiguosYRotosDeAlertSettings() throws {
        // JSON antiguo sin las dos claves nuevas -> true y 510 (08:30).
        let legacyJSON = #"{"everyMovement":false,"lowBalance":true}"#
        let legacy = try JSONDecoder().decode(AlertSettings.self, from: Data(legacyJSON.utf8))
        #expect(!legacy.everyMovement)
        #expect(legacy.morningBriefing)
        #expect(legacy.morningBriefingMinutes == 510)

        // Valores corruptos o fuera de rango -> caen a los valores por defecto sin romper la carga del libro.
        let corruptJSON = #"{"morningBriefing":"si","morningBriefingMinutes":9999}"#
        let corrupt = try JSONDecoder().decode(AlertSettings.self, from: Data(corruptJSON.utf8))
        #expect(corrupt.morningBriefing)
        #expect(corrupt.morningBriefingMinutes == 510)

        // Ida y vuelta normal.
        let custom = AlertSettings(morningBriefing: false, morningBriefingMinutes: 465)
        let roundTrip = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(custom))
        #expect(roundTrip == custom)
        #expect(AlertSettings(morningBriefingMinutes: -1).morningBriefingMinutes == 510)
    }
}
