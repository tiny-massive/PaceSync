// ContentView.swift
// Root TabView for PaceSync.

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        RedesignRootView()
            .tint(Theme.accent)
            .environmentObject(appState)
            .task {
                #if !targetEnvironment(simulator)
                await WorkoutKitService.shared.requestAuthorization()
                #endif
            }
    }
}
