//
//  PriceUpdate.swift
//  PriceUpdate
//
//  Created by ISHAN LADANI on 27/02/26.
//


import Foundation
import Combine

public struct PriceUpdate: Codable {
    public let symbol: String
    public let price: Double
}


public final class PriceGenerator {
    public let interval: TimeInterval
    public private(set) var isRunning: Bool = false

    private let webSocket: WebSocketManaging
    private let priceProvider: () -> [StockSymbol]
    private let jsonEncoder: JSONEncoder
    private var timerCancellable: AnyCancellable?
    private let subject = PassthroughSubject<PriceUpdate, Never>()
    public var updatesPublisher: AnyPublisher<PriceUpdate, Never> { subject.eraseToAnyPublisher() }

    private var rng: SeededGenerator?


    public init(
        interval: TimeInterval = 2.0,
        webSocket: WebSocketManaging = WebSocketManager.shared,
        priceProvider: @escaping () -> [StockSymbol],
        seed: UInt64? = nil
    ) {
        self.interval = interval
        self.webSocket = webSocket
        self.priceProvider = priceProvider
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        if let s = seed {
            self.rng = SeededGenerator(seed: s)
        } else {
            self.rng = nil
        }
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    public func stop() {
        guard isRunning else { return }
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
    }

    private func tick() {
        #if DEBUG
        print("PriceGenerator -> tick")
        #endif

        // Ensure websocket is connected; if not, attempt to connect so messages will be echoed back.
        if !webSocket.isConnected {
            #if DEBUG
            print("PriceGenerator -> websocket not connected, requesting connect()")
            #endif
            webSocket.connect()
        }
        let symbols = priceProvider()
        for s in symbols {
            let newPrice = generateNextPrice(basedOn: s.currentPrice)
            let update = PriceUpdate(symbol: s.symbol, price: newPrice)

            subject.send(update)

            do {
                let data = try jsonEncoder.encode(update)
                if let jsonString = String(data: data, encoding: .utf8) {
                    // Debug log for outgoing message
                    #if DEBUG
                    print("PriceGenerator -> sending: \(jsonString)")
                    #endif
                    webSocket.send(jsonString)
                }
            } catch {
                continue
            }
        }
    }


    private func generateNextPrice(basedOn current: Double) -> Double {
        // Percentage delta between -2% and +2%
        let delta: Double
        if var rng = rng {
            let raw = Double(rng.next()) / Double(UInt64.max)
            delta = (raw * 4.0) - 2.0 // map [0,1) to [-2, +2)
            self.rng = rng
        } else {
            delta = Double.random(in: -2.0...2.0)
        }
        let factor = 1.0 + (delta / 100.0)
        let next = current * factor
        return max(next, 0.01)
    }
}


private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }
}
