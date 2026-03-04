//
//  SymbolDetailViewModel.swift
//  SymbolDetailViewModel
//
//  Created by ISHAN LADANI on 28/02/26.
//

import Foundation
import Combine

final class SymbolDetailViewModel: ObservableObject {
    @Published private(set) var state: StockRowState
    @Published private(set) var isConnected: Bool = false

    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var flashToken: AnyCancellable?
    private let symbolID: UUID

    /// Initialize without an `AppState`; use `appStateDidAppear(appState:)` to inject the shared AppState later.
    init(symbolID: UUID) {
        self.symbolID = symbolID
        // Placeholder state until real AppState is injected
        self.state = StockRowState(symbol: StockSymbol(symbol: "N/A", name: "Unknown", currentPrice: 0.0))
    }

    /// Convenience initializer that accepts an AppState immediately (used in tests or direct creation).
    init(appState: AppState, symbolID: UUID) {
        self.symbolID = symbolID
        self.appState = appState

        if let sym = appState.symbols.first(where: { $0.id == symbolID }) {
            self.state = StockRowState(symbol: sym)
        } else if let sym = appState.symbols.first {
            self.state = StockRowState(symbol: sym)
        } else {
            self.state = StockRowState(symbol: StockSymbol(symbol: "N/A", name: "Unknown", currentPrice: 0.0))
        }

        bindToAppState()
    }

    /// Inject the real AppState when the view appears (called from the view's onAppear).
    func appStateDidAppear(appState: AppState) {
        // Avoid re-binding
        guard self.appState == nil else { return }
        self.appState = appState

        // Initialize state if possible
        if let sym = appState.symbols.first(where: { $0.id == symbolID }) {
            self.state = StockRowState(symbol: sym)
        }

        bindToAppState()
    }

    private func bindToAppState() {
        guard let appState = appState else { return }

        // Observe appState symbols and update when our symbol changes
        appState.$symbols
            .receive(on: DispatchQueue.main)
            .sink { [weak self] symbols in
                guard let self = self else { return }
                if let updated = symbols.first(where: { $0.id == self.symbolID }) {
                    let newState = StockRowState(symbol: updated)
                    // Detect flash
                    if newState.currentPrice > self.state.currentPrice {
                        self.state = newState.updatingFlash(.up)
                        self.scheduleClearFlash()
                    } else if newState.currentPrice < self.state.currentPrice {
                        self.state = newState.updatingFlash(.down)
                        self.scheduleClearFlash()
                    } else {
                        self.state = newState
                    }
                }
            }
            .store(in: &cancellables)

        appState.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connected in
                self?.isConnected = connected
            }
            .store(in: &cancellables)
    }

    private func scheduleClearFlash() {
        flashToken?.cancel()
        flashToken = Just(())
            .delay(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.state = StockRowState(symbol: StockSymbol(id: self.state.id, symbol: self.state.symbol, name: self.state.name, currentPrice: self.state.currentPrice, previousPrice: self.state.previousPrice))
                self.flashToken = nil
            }
    }
}
