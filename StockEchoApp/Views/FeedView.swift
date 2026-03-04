//
//  FeedView.swift
//  FeedView
//
//  Created by ISHAN LADANI on 28/02/26.
//


import SwiftUI

struct FeedView: View {
    @StateObject private var vm: FeedViewModel

    init(appState: AppState) {
        _vm = StateObject(wrappedValue: FeedViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Label(vm.isConnected ? "Connected" : "Disconnected", systemImage: vm.isConnected ? "circle.fill" : "circle")
                        .foregroundColor(vm.isConnected ? .green : .red)
                    Spacer()
                    Button(action: {
                        if vm.isRunning { vm.stop() } else { vm.start() }
                    }) {
                        Text(vm.isRunning ? "Stop" : "Start")
                    }
                }
                .padding([.leading, .trailing, .top])

                List(vm.rows) { row in
                    NavigationLink(value: row.id) {
                        FeedRowView(row: row)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("StockLiveTracker")
            .navigationDestination(for: UUID.self) { id in
                SymbolDetailView(symbolID: id)
            }
        }
    }
}

struct FeedRowView: View {
    let row: StockRowState

    private var priceChangePercentText: String {
        let prev = row.previousPrice
        guard prev != 0 else { return "0.00%" }
        let pct = (row.currentPrice - prev) / prev * 100
        return String(format: "%.2f%%", pct)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.symbol).font(.headline)
                Text(row.name).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(String(format: "$%.2f", row.currentPrice)).font(.body).bold()
                HStack(spacing: 6) {
                    if row.direction == .up {
                        Text("↑").foregroundColor(.green)
                    } else if row.direction == .down {
                        Text("↓").foregroundColor(.red)
                    }
                    Text(priceChangePercentText).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            Group {
                if row.flashDirection == .up {
                    Color.green.opacity(0.2)
                } else if row.flashDirection == .down {
                    Color.red.opacity(0.2)
                } else {
                    Color.clear
                }
            }
        )
    }
}
