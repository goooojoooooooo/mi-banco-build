#if DEBUG
import Foundation
import MiBancoCore

/// Demo de la copia de seguridad (solo DEBUG). `-MiBancoDemoBackup`: Ajustes se desplaza hasta "Copia de seguridad".
/// `-MiBancoDemoRestorePreview`: abre la confirmación de restaurar con una copia inventada de 175 movimientos del 19 nov.
extension DemoMode {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    static var scrollsToBackup: Bool { args.contains("-MiBancoDemoBackup") }
    static var opensRestorePreview: Bool { args.contains("-MiBancoDemoRestorePreview") }

    /// Copia inventada: 175 pagos e ingresos repartidos por los tres bancos, exportada el 19 de noviembre de 2026.
    static func demoRestorePreview(currentCount: Int) -> RestorePreview {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid") ?? .current
        let exported = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9)) ?? Date()
        let shops = ["Mercadona", "Lidl", "Glovo", "Renfe", "Zara", "Carrefour", "Repsol", "Starbucks"]
        let banks: [BankID] = [.rev, .ima, .tr]
        var movements: [Movement] = []
        for i in 0..<175 {
            let date = exported.addingTimeInterval(-Double(i) * 86_400 * 0.8)
            let income = i % 11 == 0
            movements.append(Movement(
                bank: banks[i % 3], amountCents: income ? 145_000 : -(900 + (i * 137) % 6_000),
                merchant: income ? "Nómina" : shops[i % shops.count], kind: income ? .income : .payment,
                source: .notification, date: date, isShop: !income))
        }
        return RestorePreview(file: BackupFile(exportedAt: exported, ledger: LedgerState(movements: movements)),
                              currentCount: currentCount)
    }
}
#endif
