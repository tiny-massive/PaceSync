// ContentView.swift
// Root TabView for PaceSync.

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RedesignRootView()
            .tint(Theme.accent)
            .environmentObject(appState)
            .task {
                #if !targetEnvironment(simulator)
                await WorkoutKitService.shared.requestAuthorization()
                await appState.autoMatchCompletions()
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                #if !targetEnvironment(simulator)
                if phase == .active {
                    Task { await appState.autoMatchCompletions() }
                }
                #endif
            }
    }
}
