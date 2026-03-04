import Foundation
import Combine

/// Immutable view state for a row in the feed.
public struct StockRowState: Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let previousPrice: Double
    public let direction: PriceDirection
    public let flashDirection: PriceDirection // .none when no flash

    init(symbol: StockSymbol, flashDirection: PriceDirection = .none) {
        self.id = symbol.id
        self.symbol = symbol.symbol
        self.name = symbol.name
        self.currentPrice = symbol.currentPrice
        self.previousPrice = symbol.previousPrice
        self.direction = symbol.direction
        self.flashDirection = flashDirection
    }

    func updatingFlash(_ flash: PriceDirection) -> StockRowState {
        return StockRowState(
            id: id,
            symbol: symbol,
            name: name,
            currentPrice: currentPrice,
            previousPrice: previousPrice,
            direction: direction,
            flashDirection: flash
        )
    }

    // Custom initializer for copying with different flash
    init(id: UUID, symbol: String, name: String, currentPrice: Double, previousPrice: Double, direction: PriceDirection, flashDirection: PriceDirection) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.currentPrice = currentPrice
        self.previousPrice = previousPrice
        self.direction = direction
        self.flashDirection = flashDirection
    }
}

/// FeedViewModel: observes AppState and handles flash timing and start/stop control for price generation.
final class FeedViewModel: ObservableObject {
    @Published private(set) var rows: [StockRowState] = []
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var isRunning: Bool = false

    private let appState: AppState
    private let priceGenerator: PriceGenerator
    private var cancellables = Set<AnyCancellable>()

    /// Map of scheduled cancellation tokens for clearing flashes per symbol
    private var flashTokens: [UUID: AnyCancellable] = [:]

    init(appState: AppState, priceGenerator: PriceGenerator? = nil) {
        self.appState = appState
        // Ensure PriceGenerator writes to the same WebSocket that AppState listens to.
        self.priceGenerator = priceGenerator ?? PriceGenerator(webSocket: appState.webSocket, priceProvider: { appState.symbols })

        // Initial state from appState
        self.rows = appState.symbols.map { StockRowState(symbol: $0) }
        self.isConnected = appState.isConnected

        // Observe symbols updates coming from AppState
        appState.$symbols
            .receive(on: DispatchQueue.main)
            .sink { [weak self] symbols in
                self?.apply(symbols: symbols)
            }
            .store(in: &cancellables)

        // Observe connection status
        appState.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
            }
            .store(in: &cancellables)
    }

    // Apply new symbols from the AppState, detect changes and trigger flash animations.
    private func apply(symbols: [StockSymbol]) {
        var newRows: [StockRowState] = []

        for sym in symbols {
            let existing = rows.first(where: { $0.id == sym.id })
            let row = StockRowState(symbol: sym)

            // Detect direction change relative to previous row (if any)
            if let ex = existing {
                if sym.currentPrice > ex.currentPrice {
                    // Price increased
                    let flashed = row.updatingFlash(.up)
                    newRows.append(flashed)
                    scheduleClearFlash(id: row.id)
                    continue
                } else if sym.currentPrice < ex.currentPrice {
                    // Price decreased
                    let flashed = row.updatingFlash(.down)
                    newRows.append(flashed)
                    scheduleClearFlash(id: row.id)
                    continue
                }
            }

            // No change or first appearance
            newRows.append(row)
        }

        // Sort is already enforced by AppState, but ensure here as well
        newRows.sort { $0.currentPrice > $1.currentPrice }
        self.rows = newRows
    }

    private func scheduleClearFlash(id: UUID) {
        // Cancel existing token if any
        flashTokens[id]?.cancel()

        // After 1 second clear the flash for that row
        let token = Just(())
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if let idx = self.rows.firstIndex(where: { $0.id == id }) {
                    let current = self.rows[idx]
                    let cleared = StockRowState(id: current.id, symbol: current.symbol, name: current.name, currentPrice: current.currentPrice, previousPrice: current.previousPrice, direction: current.direction, flashDirection: .none)
                    var copy = self.rows
                    copy[idx] = cleared
                    self.rows = copy
                }
                self.flashTokens[id] = nil
            }
        flashTokens[id] = token
    }

    // MARK: - Control
    func start() {
        guard !isRunning else { return }
        // Ensure websocket connected
        appState.connect()
        priceGenerator.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        priceGenerator.stop()
        appState.disconnect()
        isRunning = false
    }
}
