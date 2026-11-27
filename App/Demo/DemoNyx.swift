#if DEBUG
import Foundation
import MiBancoCore

/// Banderas y escenarios de demo para Nyx Fase 2 (solo DEBUG, no existen en Release).
extension DemoMode {
    enum NyxScenario: String {
        case shortfall
        case shortfallBg = "shortfall-bg"
        case seenList = "seen-list"
        case dailyFocus = "daily-focus"
        case banner
    }

    /// `-MiBancoDemoNyx <shortfall|shortfall-bg|seen-list|daily-focus|banner>`: activa un escenario de Nyx en modo demo.
    static var nyxScenario: NyxScenario? {
        guard isActive else { return nil }
        return value(after: "-MiBancoDemoNyx").flatMap(NyxScenario.init(rawValue:))
    }

    /// `-MiBancoDemoPersistNyx`: guarda `nyx-memory.json` en una carpeta propia de la demo para probar reinicios.
    static var persistsNyxMemory: Bool { isActive && arguments.contains("-MiBancoDemoPersistNyx") }

    /// `-MiBancoDemoNyxReset`: borra la memoria persistente de la demo al arrancar.
    static var resetsNyxMemory: Bool { isActive && arguments.contains("-MiBancoDemoNyxReset") }

    /// `-MiBancoDemoNyxNoNotifications`: simula permiso de notificaciones del sistema denegado (`false`).
    static var nyxNotificationsDenied: Bool { isActive && arguments.contains("-MiBancoDemoNyxNoNotifications") }

    /// `-MiBancoDemoNyxNoSpeech`: simula que la transcripción local de voz no está disponible en este iPhone.
    static var nyxSpeechUnavailable: Bool { isActive && arguments.contains("-MiBancoDemoNyxNoSpeech") }

    /// Carpeta aislada para la persistencia de Nyx en pruebas de reinicio (nunca toca `SharedStore`).
    static var nyxDemoDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("NyxDemoMemory", isDirectory: true)
    }

    static var nyxHealth: NyxAppHealth {
        NyxAppHealth(
            notificationsAllowed: nyxNotificationsDenied ? false : true,
            appExpiresAt: nil
        )
    }

    /// Libro mínimo con un cobro de Netflix mañana (13,99 € en Revolut) y saldo de 9,20 € en Revolut (imagin: 1.284,55 €).
    /// Produce exactamente 1 observación real (`shortfall`, prioridad urgente, traspaso sugerido de 10,00 € desde imagin).
    static func nyxShortfallLedger(now: Date = DemoMode.now, calendar: Calendar = DateText.madridCalendar) -> LedgerState {
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)?.addingTimeInterval(10 * 3_600) ?? now
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: tomorrow) ?? now.addingTimeInterval(-30 * 86_400)
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: tomorrow) ?? now.addingTimeInterval(-60 * 86_400)

        let balances: [BankID: ManualBalance] = [
            .rev: ManualBalance(cents: 920, setAt: now, fromBank: true),
            .ima: ManualBalance(cents: 128_455, setAt: now, fromBank: false),
            .tr: ManualBalance(cents: 215_000, setAt: now, fromBank: false),
        ]
        let movements = [
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank, date: oneMonthAgo, isShop: true),
            Movement(bank: .rev, amountCents: -1_399, merchant: "Netflix", kind: .payment, source: .bank, date: twoMonthsAgo, isShop: true),
        ]
        return LedgerState(balances: balances, movements: movements, unread: [], budgets: Budgets(), links: [:])
    }
}
#endif
