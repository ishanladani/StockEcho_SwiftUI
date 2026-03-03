//
//  StockSymbol.swift
//  StockSymbol
//
//  Created by ISHAN LADANI on 27/02/26.
//

import Foundation

/// Represents a stock symbol with immutable state.
/// This is a value-type model: updates produce new instances (see `updatingPrice(to:)`).
public enum PriceDirection: String, Codable {
    case up
    case down
    case none
}

public struct StockSymbol: Identifiable, Codable, Equatable {
    public let id: UUID
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let previousPrice: Double
    public let direction: PriceDirection

    /// Designated initializer. `previousPrice` defaults to 0 which yields a `.none` direction.
    public init(
        id: UUID = UUID(),
        symbol: String,
        name: String,
        currentPrice: Double,
        previousPrice: Double = 0.0
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.currentPrice = currentPrice
        self.previousPrice = previousPrice

        if previousPrice == 0.0 {
            self.direction = .none
        } else if currentPrice > previousPrice {
            self.direction = .up
        } else if currentPrice < previousPrice {
            self.direction = .down
        } else {
            self.direction = .none
        }
    }

    /// Return a new `StockSymbol` with an updated price. Keeps the same `id`, `symbol`, and `name`.
    /// The `previousPrice` in the returned instance will be the current price of this instance.
    public func updatingPrice(to newPrice: Double) -> StockSymbol {
        return StockSymbol(
            id: id,
            symbol: symbol,
            name: name,
            currentPrice: newPrice,
            previousPrice: currentPrice
        )
    }

    /// Absolute change from previous to current.
    public var priceChange: Double { currentPrice - previousPrice }

    /// Percent change from previous to current. Returns 0 when previousPrice is 0.
    public var priceChangePercent: Double {
        guard previousPrice != 0 else { return 0 }
        return (currentPrice - previousPrice) / previousPrice * 100
    }

    /// Helper for sorting: higher price comes first (descending).
    public static func sortByPriceDescending(lhs: StockSymbol, rhs: StockSymbol) -> Bool {
        return lhs.currentPrice > rhs.currentPrice
    }
}
