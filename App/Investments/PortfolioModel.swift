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
    static let maxImportBytes = 10 * 1024 * 1024

    private(set) var portfolio: Portfolio
    private(set) var summary: PortfolioSummary?
    private(set) var lastImport: ImportSummary?
    private(set) var lastImportError: String?
    private(set) var isRefreshingPrices = false

    @ObservationIgnored private let store: PortfolioStore
    @ObservationIgnored private let priceService: PriceService
    @ObservationIgnored private var lastPriceAttempt: Date?
    @ObservationIgnored private var summaryDay: Date
    @ObservationIgnored private var observer: Task<Void, Never>?

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
        self.summaryDay = Calendar.current.startOfDay(for: now)
        #if DEBUG
        if DemoMode.isActive {
            let initial = DemoMode.includesPortfolio ? DemoMode.portfolio(now: now) : Portfolio()
            self.portfolio = initial
            self.summary = portfolioSummary(initial, now: now, calendar: madridCalendar)
            return
        }
        #endif
        let loaded = (try? store.load()) ?? Portfolio()
        self.portfolio = loaded
        self.summary = portfolioSummary(loaded, now: now, calendar: madridCalendar)
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .portfolioDidChange) {
                guard let self else { break }
                self.reload()
            }
        }
    }

    /// Relee la cartera de disco o recalcula el resumen si ha cambiado el día.
    func reload() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        #if DEBUG
        if DemoMode.isActive {
            if today != summaryDay {
                summaryDay = today
                summary = portfolioSummary(portfolio, now: now, calendar: madridCalendar)
            }
            return
        }
        #endif
        guard let loaded = try? store.load() else { return }
        if loaded != portfolio || loaded.droppedEntries != portfolio.droppedEntries || today != summaryDay {
            portfolio = loaded
            summaryDay = today
            summary = portfolioSummary(loaded, now: now, calendar: madridCalendar)
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
        let result: ImportSummary
        #if DEBUG
        if DemoMode.isActive {
            var next = portfolio
            result = next.merge(extract, now: now)
            portfolio = next
            summaryDay = Calendar.current.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: madridCalendar)
            lastImport = result
            lastImportError = nil
            return result
        }
        #endif
        result = try store.update { $0.merge(extract, now: now) }
        let reloaded = (try? store.load()) ?? portfolio
        portfolio = reloaded
        summaryDay = Calendar.current.startOfDay(for: now)
        summary = portfolioSummary(reloaded, now: now, calendar: madridCalendar)
        lastImport = result
        lastImportError = nil
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
        let lastFetch = lastPriceAttempt ?? portfolio.quotes.values.map(\.fetchedAt).max()
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
            guard !Task.isCancelled else { break }
            if let found = await priceService.quote(
                for: position.instrument,
                assetClass: position.assetClass,
                knownSymbol: knownSymbols[position.instrument]
            ) {
                fetchedQuotes[position.instrument] = found.quote
                fetchedSymbols[position.instrument] = found.symbol
            }
        }
        guard !fetchedQuotes.isEmpty || !fetchedSymbols.isEmpty else { return }

        _ = try? store.update { current in
            for (instrument, quote) in fetchedQuotes { current.quotes[instrument] = quote }
            for (instrument, symbol) in fetchedSymbols { current.symbols[instrument] = symbol }
        }
        let updatedNow = Date()
        let reloaded = (try? store.load()) ?? portfolio
        portfolio = reloaded
        summaryDay = Calendar.current.startOfDay(for: updatedNow)
        summary = portfolioSummary(reloaded, now: updatedNow, calendar: madridCalendar)
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
            guard !Task.isCancelled else { break }
            if let found = await priceService.quote(
                for: position.instrument,
                assetClass: position.assetClass,
                knownSymbol: current.symbols[position.instrument]
            ) {
                fetchedQuotes[position.instrument] = found.quote
                fetchedSymbols[position.instrument] = found.symbol
            }
        }
        guard !fetchedQuotes.isEmpty || !fetchedSymbols.isEmpty else { return }
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
        }
        let now = Date()
        #if DEBUG
        if DemoMode.isActive {
            var next = portfolio
            if let price {
                next.manualPrices[instrument] = ManualPrice(priceEUR: price, setAt: now)
            } else {
                next.manualPrices.removeValue(forKey: instrument)
            }
            portfolio = next
            summaryDay = Calendar.current.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: madridCalendar)
            return
        }
        #endif
        try store.update { current in
            if let price {
                current.manualPrices[instrument] = ManualPrice(priceEUR: price, setAt: now)
            } else {
                current.manualPrices.removeValue(forKey: instrument)
            }
        }
        let reloaded = (try? store.load()) ?? portfolio
        portfolio = reloaded
        summaryDay = Calendar.current.startOfDay(for: now)
        summary = portfolioSummary(reloaded, now: now, calendar: madridCalendar)
    }

    /// Sustituye la cartera entera (restauración de copia de seguridad).
    func replace(with next: Portfolio) throws {
        let now = Date()
        #if DEBUG
        if DemoMode.isActive {
            portfolio = next
            summaryDay = Calendar.current.startOfDay(for: now)
            summary = portfolioSummary(next, now: now, calendar: madridCalendar)
            lastImport = nil
            lastImportError = nil
            return
        }
        #endif
        try store.save(next)
        portfolio = next
        summaryDay = Calendar.current.startOfDay(for: now)
        summary = portfolioSummary(next, now: now, calendar: madridCalendar)
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
