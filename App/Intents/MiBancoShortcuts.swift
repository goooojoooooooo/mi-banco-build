import AppIntents

struct MiBancoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PassNoticeIntent(), phrases: ["Pasar aviso a \(.applicationName)"],
                    shortTitle: "Pasar aviso a Onyx", systemImageName: "bell.badge")
        AppShortcut(intent: RegisterNoticeIntent(), phrases: ["Registrar aviso en \(.applicationName)"],
                    shortTitle: "Registrar aviso", systemImageName: "bell")
        AppShortcut(intent: RegisterWalletIntent(), phrases: ["Registrar pago con Cartera en \(.applicationName)"],
                    shortTitle: "Registrar pago con Cartera", systemImageName: "creditcard")
    }
}
