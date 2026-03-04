import SwiftUI

struct SymbolDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm: SymbolDetailViewModel

    init(symbolID: UUID) {
        _vm = StateObject(wrappedValue: SymbolDetailViewModel(symbolID: symbolID))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(vm.state.symbol).font(.largeTitle).bold()
            Text(String(format: "$%.2f", vm.state.currentPrice)).font(.title)
            if vm.state.direction == .up {
                Text("↑").font(.title).foregroundColor(.green)
            } else if vm.state.direction == .down {
                Text("↓").font(.title).foregroundColor(.red)
            }
            Text("This is a static description of the company. Replace with real data later.")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(
            Group {
                if vm.state.flashDirection == .up {
                    Color.green.opacity(0.2)
                } else if vm.state.flashDirection == .down {
                    Color.red.opacity(0.2)
                } else {
                    Color.clear
                }
            }
        )
        .navigationTitle(vm.state.symbol)
        .onAppear {
            vm.appStateDidAppear(appState: appState)
        }
    }
}
