//
//  AppState.swift
//  AppState
//
//  Created by ISHAN LADANI on 27/02/26.
//



import Foundation
import Combine

public protocol WebSocketManaging {
    var messagePublisher: AnyPublisher<String, Never> { get }
    var isConnected: Bool { get }
    func connect()
    func disconnect()
    func send(_ text: String)
}

final class InMemoryWebSocketManager: WebSocketManaging {
    private let subject = PassthroughSubject<String, Never>()
    public private(set) var isConnected: Bool = false
    public var messagePublisher: AnyPublisher<String, Never> { subject.eraseToAnyPublisher() }

    func connect() {
        guard !isConnected else { return }
        isConnected = true
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
    }

    func send(_ text: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.subject.send(text)
        }
    }
}


private struct PriceUpdate: Codable {
    let symbol: String
    let price: Double
}


final class AppState: ObservableObject {
    @Published private(set) var symbols: [StockSymbol]
    @Published private(set) var isConnected: Bool = false

    public let webSocket: WebSocketManaging

    private var cancellables = Set<AnyCancellable>()

    private static let predefinedSymbols: [String] = [
        "AAPL", "GOOG", "TSLA", "AMZN", "MSFT", "NVDA", "META", "NFLX", "BABA",
        "INTC", "AMD", "UBER", "LYFT", "ORCL", "IBM", "ADBE", "CRM", "SHOP",
        "SQ", "PYPL", "DIS", "SONY", "TATA", "INFY", "RELIANCE"
    ]

    init(webSocket: WebSocketManaging = InMemoryWebSocketManager()) {
        self.webSocket = webSocket
        self.symbols = Self.makeInitialSymbols()

        // Subscribe to incoming messages from the web socket.
        webSocket.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingMessage(message)
            }
            .store(in: &cancellables)

        // Reflect connection status if the manager is already connected.
        self.isConnected = webSocket.isConnected
    }

    // MARK: - Manage Connections

    func connect() {
        webSocket.connect()
        isConnected = webSocket.isConnected
    }

    func disconnect() {
        webSocket.disconnect()
        isConnected = webSocket.isConnected
    }

    func toggleConnection() {
        if webSocket.isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func send(_ text: String) {
        webSocket.send(text)
    }

    // MARK: - Message handling

    private func handleIncomingMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        do {
            let update = try JSONDecoder().decode(PriceUpdate.self, from: data)
            applyPriceUpdate(symbol: update.symbol, price: update.price)
        } catch {
        }
    }

    private func applyPriceUpdate(symbol: String, price: Double) {
        
        guard let index = symbols.firstIndex(where: { $0.symbol == symbol }) else { return }
        let target = symbols[index]
        let updated = target.updatingPrice(to: price)

        var newSymbols = symbols
        newSymbols[index] = updated
        newSymbols.sort(by: StockSymbol.sortByPriceDescending)

        self.symbols = newSymbols
    }

    // MARK: - Helpers

    private static func makeInitialSymbols() -> [StockSymbol] {
        var rng = SeededGenerator(seed: 42)
        let list = predefinedSymbols.map { symbol in
            let price = Double.random(in: 50...2000, using: &rng)
            return StockSymbol(symbol: symbol, name: symbol + " Inc.", currentPrice: price)
        }
        return list.sorted(by: StockSymbol.sortByPriceDescending)
    }
}

// MARK: - Seeded RNG for deterministic sample data
private struct SeededGenerator: RandomNumberGenerator {
    // Xorshift64* implementation
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x4d595df4d0f33173 : seed }
    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }
}
