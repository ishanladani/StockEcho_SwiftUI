//
//  StockEchoAppApp.swift
//  StockEchoApp
//
//  Created by ISHAN LADANI on 27/02/26.
//

import SwiftUI

@main
struct StockEchoAppApp: App {
    // Create shared AppState for the app
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            FeedView(appState: appState)
                .environmentObject(appState)
        }
    }
}
