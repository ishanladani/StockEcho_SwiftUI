import XCTest
import Combine
@testable import StockEchoApp

final class PriceGeneratorTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testPriceGeneratorPublishesUpdates() throws {
        let inMemoryWS = InMemoryWebSocketManager()
        let appState = AppState(webSocket: inMemoryWS)
        // Use faster interval for tests
        let gen = PriceGenerator(interval: 0.1, webSocket: inMemoryWS, priceProvider: { appState.symbols }, seed: 1)

        let expect = expectation(description: "Price updates should be published")
        var received = 0

        gen.updatesPublisher
            .sink { _ in
                received += 1
                if received >= 3 {
                    expect.fulfill()
                }
            }
            .store(in: &cancellables)

        gen.start()

        wait(for: [expect], timeout: 2.0)
        gen.stop()
    }

    func testAppStateReceivesEchoedUpdatesAndAppliesThem() throws {
        let inMemoryWS = InMemoryWebSocketManager()
        let appState = AppState(webSocket: inMemoryWS)

        // PriceGenerator will send messages to the same in-memory WS which immediately echoes them back
        let gen = PriceGenerator(interval: 0.1, webSocket: inMemoryWS, priceProvider: { appState.symbols }, seed: 2)

        // Capture initial snapshot
        let initial = appState.symbols.map { ($0.symbol, $0.currentPrice) }

        let expect = expectation(description: "AppState should apply at least one price update from echoed websocket messages")

        appState.$symbols
            .dropFirst()
            .sink { symbols in
                // Check if any symbol price changed from initial
                for s in symbols {
                    if let old = initial.first(where: { $0.0 == s.symbol }) {
                        if s.currentPrice != old.1 {
                            expect.fulfill()
                            return
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Start connection and generator
        appState.connect()
        gen.start()

        wait(for: [expect], timeout: 3.0)

        gen.stop()
        appState.disconnect()
    }
}
