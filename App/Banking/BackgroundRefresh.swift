import BackgroundTasks
import Foundation

/// Actualización en segundo plano (mejor esfuerzo): iOS decide si la lanza y cuándo; en una app instalada sin la App
/// Store puede tardar mucho o no llegar nunca. La vía segura es la consulta al abrir la app.
enum BackgroundRefresh {
    static let identifier = "com.mibanco.app.refresh"

    /// Pide la próxima ejecución para dentro de 4 h como pronto. Los errores se ignoran.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Siempre termina y siempre deja la siguiente pedida: se pide antes (por si el sistema corta la tarea) y después.
    /// Si la tarea caduca, la cancelación llega a la consulta, que se detiene sin dejar nada a medias ni anotar un fallo.
    /// El Plan 4 añade aquí su tarea de precios.
    static func run() async {
        schedule()
        // Segundo plano: nunca envía cabeceras PSU (cupo de 4 cada 24 h).
        _ = await BankSync.shared.refresh(trigger: .background, isUnlocked: false)
        if !Task.isCancelled {
            await PortfolioModel.refreshPricesInBackground()
        }
        if !Task.isCancelled, let state = try? SharedStore.make().load() {
            await MorningBriefingNotifier.reschedule(
                settings: state.alertSettings,
                shownToday: BriefingModel.storedShownToday()
            )
        }
        schedule()
    }
}
