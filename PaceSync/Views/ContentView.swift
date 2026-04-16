// ContentView.swift
// Root TabView for PaceSync.

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "figure.run")
                }

            ScheduledView()
                .tabItem {
                    Label("Scheduled", systemImage: "checkmark.circle.fill")
                }
        }
        .tint(.green)
        .environmentObject(appState)
        .task {
            await WorkoutKitService.shared.requestAuthorization()
        }
    }
}
