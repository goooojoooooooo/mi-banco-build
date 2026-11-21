import Foundation
import Observation
import MiBancoCore

extension Notification.Name {
    /// La tarea en segundo plano actualizó los precios de la cartera en disco.
    static let portfolioDidChange = Notification.Name("com.mibanco.portfolioDidChange")
}

enum PortfolioImportError: Error, Sendable {
    case tooLarge
    case unreadable
}

/// Estado observable de la cartera de inversiones (Plan 4b, tareas 6–7).
/// En modo demo todo vive en memoria y nunca se toca la red ni el disco.
@MainActor @Observable
final class PortfolioModel {
    nonisolated static let maxImportBytes = 10 * 1024 * 1024
    nonisolated static let safetyCopyName = "portfolio-antes-de-restaurar.json"

    private(set) var portfolio: Portfolio
    private(set) var summary: PortfolioSummary?
    private(set) var lastImport: ImportSummary?
    private(set) var lastImportError: String?
    /// Sube en cada resultado o fallo de importación para que la háptica se dispare aunque el texto coincida.
    private(set) var importFeedbackToken = 0
    private(set) var isRefreshingPrices = false

    @ObservationIgnored private let store: PortfolioStore
    @ObservationIgnored private let priceService: PriceService
    @ObservationIgnored private var lastPriceAttempt: Date?
    @ObservationIgnored private var summaryDay: Date
    @ObservationIgnored private var observer: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var demoSafetyCopy: Portfolio?
    #endif

    var hasPositions: Bool { summary != nil }

    /// nil cuando la cartera está vacía (la copia de seguridad no escribe la clave).
    var portfolioForBackup: Portfolio? {
        if portfolio.transactions.isEmpty && portfolio.quotes.isEmpty
            && portfolio.manualPrices.isEmpty && portfolio.symbols.isEmpty && portfolio.lastImport == nil {
            return nil
        }
        return portfolio
    }

    init(store: PortfolioStore = SharedStore.makePortfolioStore(), priceService: PriceService = PriceService()) {
        self.store = store
        self.priceService = priceService
        let now = Date()
        self.summaryDay = DateText.madridCalendar.startOfDay(for: now)
        #if DEBUG
        if DemoMode.isActive {
            let initial = DemoMode.includesPortfolio ? DemoMode.portfolio(now: now) : Portfolio()
            self.portfolio = initial
            self.summary = portfolioSummary(initial, now: now, calendar: DateText.madridCalendar)
            return
        }
        #endif
        let loaded = (try? store.load()) ?? Portfolio()
        self.portfolio = loaded
        self.summary = portfolioSummary(loaded, now: now, calendar: DateText.madridCalendar)
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .portfolioDidChange) {
                guard let self else { break }
                self.reload()
            }
        }
    }

    /// Relee la cartera de disco o recalcula el resumen si ha cambiado el día de Madrid.
    func reload() {
        let now = Date()
        let today = DateText.madridCalendar.startOfDay(for: now)
        #if DEBUG
        if DemoMode.isActive {
            if today != summaryDay {
                summaryDay = today
                summary = portfolioSummary(portfolio, now: now, calendar: DateText.madridCalendar)
            }
            return
        }
        #endif
        guard let loaded = try? store.load() else { return }
        if loaded != portfolio || loaded.droppedEntries != portfolio.droppedEntries || today != summaryDay {
            portfolio = loaded
            summaryDay = today
            summary = portfolioSummary(loaded, now: now, calendar: DateText.madridCalendar)
        }
    }

    /// Lee y valida el fichero CSV de Trade Republic fuera del actor principal (≤ 10 MB, acceso con ámbito de seguridad).
    nonisolated static func readTradeRepublicRows(from url: URL) throws -> [TradeRepublicRow] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maxImportBytes else {
            throw PortfolioImportError.tooLarge
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maxImportBytes else { throw PortfolioImportError.tooLarge }
        let table = try CSVTable.parse(data)
        return try parseTradeRepublicExport(table)
    }

    /// Incorpora filas ya leídas de Trade Republic (llamado también desde el importador de extractos del Plan 2).
    @discardableResult
    func mergeRows(_ rows: [TradeRepublicRow]) throws -> ImportSummary {
        let extract = investmentTransactions(from: rows)
        let now = Date()
        #if DEBUG
        if DemoMode.isActive {
            var next = portfolio
            let result = next.merge(extract, now: now)
            portfolio = next
            summaryDay = DateText.madridCalendar.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: DateText.madridCalendar)
            lastImport = result
            lastImportError = nil
            importFeedbackToken += 1
            return result
        }
        #endif
        let (result, updated) = try store.update { current -> (ImportSummary, Portfolio) in
            let summary = current.merge(extract, now: now)
            return (summary, current)
        }
        portfolio = updated
        summaryDay = DateText.madridCalendar.startOfDay(for: now)
        summary = portfolioSummary(updated, now: now, calendar: DateText.madridCalendar)
        lastImport = result
        lastImportError = nil
        importFeedbackToken += 1
        return result
    }

    /// Versión síncrona de importación directa desde URL.
    @discardableResult
    func importCSV(from url: URL) throws -> ImportSummary {
        let rows = try Self.readTradeRepublicRows(from: url)
        return try mergeRows(rows)
    }

    /// Lectura y análisis CSV fuera del actor principal; la fusión y el refresco de vistas ocurren en `@MainActor`.
    @discardableResult
    func importCSVAsync(from url: URL) async throws -> ImportSummary {
        let rows = try await Task.detached(priority: .userInitiated) {
            try Self.readTradeRepublicRows(from: url)
        }.value
        return try mergeRows(rows)
    }

    func recordImportError(_ message: String) {
        lastImport = nil
        lastImportError = message
        importFeedbackToken += 1
    }

    func clearImportFeedback() {
        lastImport = nil
        lastImportError = nil
    }

    /// Actualiza los precios en serie si el usuario dio permiso y toca refrescar (o si `force` es true). Nunca en demo.
    func refreshPrices(force: Bool) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        guard !isRefreshingPrices else { return }
        guard UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { return }
        let now = Date()
        let lastFetch = [lastPriceAttempt, portfolio.quotes.values.map(\.fetchedAt).max()].compactMap { $0 }.max()
        guard force || shouldRefreshPrices(lastFetch: lastFetch, now: now) else { return }

        let openPositions = positions(from: portfolio.transactions)
        guard !openPositions.isEmpty else { return }
        let knownSymbols = portfolio.symbols

        isRefreshingPrices = true
        lastPriceAttempt = now
        defer { isRefreshingPrices = false }

        var fetchedQuotes: [String: Quote] = [:]
        var fetchedSymbols: [String: String] = [:]
        for position in openPositions {
            guard !Task.isCancelled,
                  UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { break }
            if let found = await priceService.quote(
                for: position.instrument,
                assetClass: position.assetClass,
                knownSymbol: knownSymbols[position.instrument]
            ) {
                fetchedQuotes[position.instrument] = found.quote
                fetchedSymbols[position.instrument] = found.symbol
            }
        }
        guard !fetchedQuotes.isEmpty || !fetchedSymbols.isEmpty,
              UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { return }

        guard let updated = try? store.update({ current -> Portfolio in
            for (instrument, quote) in fetchedQuotes { current.quotes[instrument] = quote }
            for (instrument, symbol) in fetchedSymbols { current.symbols[instrument] = symbol }
            return current
        }) else { return }
        let updatedNow = Date()
        portfolio = updated
        summaryDay = DateText.madridCalendar.startOfDay(for: updatedNow)
        summary = portfolioSummary(updated, now: updatedNow, calendar: DateText.madridCalendar)
    }

    /// Ruta de segundo plano para `BackgroundRefresh.run()`: respeta cancelación, permiso y cadencia de 15 minutos.
    nonisolated static func refreshPricesInBackground(
        store: PortfolioStore = SharedStore.makePortfolioStore(),
        priceService: PriceService = PriceService()
    ) async {
        #if DEBUG
        if DemoMode.isActive { return }
        #endif
        guard !Task.isCancelled else { return }
        guard UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { return }
        guard let current = try? store.load() else { return }
        let openPositions = positions(from: current.transactions)
        guard !openPositions.isEmpty else { return }
        let lastFetch = current.quotes.values.map(\.fetchedAt).max()
        guard shouldRefreshPrices(lastFetch: lastFetch, now: Date()) else { return }

        var fetchedQuotes: [String: Quote] = [:]
        var fetchedSymbols: [String: String] = [:]
        for position in openPositions {
            guard !Task.isCancelled,
                  UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { break }
            if let found = await priceService.quote(
                for: position.instrument,
                assetClass: position.assetClass,
                knownSymbol: current.symbols[position.instrument]
            ) {
                fetchedQuotes[position.instrument] = found.quote
                fetchedSymbols[position.instrument] = found.symbol
            }
        }
        guard !fetchedQuotes.isEmpty || !fetchedSymbols.isEmpty,
              UserDefaults.standard.bool(forKey: AppPreferences.pricesEnabledKey) else { return }
        _ = try? store.update { portfolio in
            for (instrument, quote) in fetchedQuotes { portfolio.quotes[instrument] = quote }
            for (instrument, symbol) in fetchedSymbols { portfolio.symbols[instrument] = symbol }
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .portfolioDidChange, object: nil)
        }
    }

    /// Fija un precio manual en euros para un instrumento, o lo quita si `price` es nil.
    func setManualPrice(_ price: Decimal?, for instrument: String) throws {
        if let price {
            guard price.isFinite, price > 0, price <= 1_000_000_000 else {
                throw PortfolioImportError.unreadable
            }
            if let open = positionValue(for: instrument)?.position {
                let totalCents = open.shares * price * 100
                guard totalCents.isFinite, totalCents.magnitude < Decimal(1_000_000_000_000) else {
                    throw PortfolioImportError.unreadable
                }
            }
        }
        let now = Date()
        // Si el mercado trae una hora ligeramente por delante del reloj local, el precio manual explícito manda igual.
        let quoteDate = portfolio.quotes[instrument].map { $0.marketTime ?? $0.fetchedAt }
        let effectiveSetAt = quoteDate.map { max(now, $0.addingTimeInterval(1)) } ?? now
        #if DEBUG
        if DemoMode.isActive {
            var next = portfolio
            if let price {
                next.manualPrices[instrument] = ManualPrice(priceEUR: price, setAt: effectiveSetAt)
            } else {
                next.manualPrices.removeValue(forKey: instrument)
            }
            portfolio = next
            summaryDay = DateText.madridCalendar.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: DateText.madridCalendar)
            return
        }
        #endif
        let updated = try store.update { current -> Portfolio in
            if let price {
                current.manualPrices[instrument] = ManualPrice(priceEUR: price, setAt: effectiveSetAt)
            } else {
                current.manualPrices.removeValue(forKey: instrument)
            }
            return current
        }
        portfolio = updated
        summaryDay = DateText.madridCalendar.startOfDay(for: now)
        summary = portfolioSummary(updated, now: now, calendar: DateText.madridCalendar)
    }

    /// Guarda una copia de seguridad de la cartera actual antes de restaurar una copia (para «Volver a lo de antes»).
    func saveSafetyCopy() throws {
        #if DEBUG
        if DemoMode.isActive {
            demoSafetyCopy = portfolio
            return
        }
        #endif
        try store.saveCopy(portfolio, named: Self.safetyCopyName)
    }

    /// Cartera guardada antes de la última restauración (incluida una vacía si antes no había inversiones).
    func loadSafetyCopy() -> Portfolio? {
        #if DEBUG
        if DemoMode.isActive { return demoSafetyCopy }
        #endif
        return store.loadCopy(named: Self.safetyCopyName)
    }

    /// Sustituye la cartera entera (restauración de copia de seguridad).
    func replace(with next: Portfolio) throws {
        let now = Date()
        #if DEBUG
        if DemoMode.isActive {
            portfolio = next
            summaryDay = DateText.madridCalendar.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: DateText.madridCalendar)
            lastImport = nil
            lastImportError = nil
            return
        }
        #endif
        try store.save(next)
        portfolio = next
        summaryDay = DateText.madridCalendar.startOfDay(for: now)
        summary = portfolioSummary(next, now: now, calendar: DateText.madridCalendar)
        lastImport = nil
        lastImportError = nil
    }

    func positionValue(for instrument: String) -> PositionValue? {
        summary?.positions.first { $0.position.instrument == instrument }
    }

    /// Últimas operaciones de un instrumento, de la más reciente a la más antigua.
    func recentTransactions(for instrument: String, limit: Int = 5) -> [InvestmentTransaction] {
        Array(
            portfolio.transactions
                .filter { $0.instrument == instrument }
                .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
                .prefix(limit)
        )
    }
}
