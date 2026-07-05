// RedesignRootView.swift
// New root: three destinations — Today · Plans · Settings — via a native TabView,
// which renders as Liquid Glass automatically on iOS 26 (and a normal bar below it).
// The "+" create action lives top-right on the Today and Plans roots.

import SwiftUI

struct RedesignRootView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "figure.run") }

            NavigationStack { PlansView() }
                .tabItem { Label("Plans", systemImage: "square.stack.3d.up") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}

// MARK: - Plans (library) — minimal for now; real reuse/library next

struct PlansView: View {
    @EnvironmentObject var appState: AppState
    var unit: DistanceUnit = .kilometers

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                if let plan = appState.planStore.current {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeader(text: "Active")
                        ProgressCard(plan: plan, unit: unit)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeader(text: "My plans")
                        Text("Saved plans and reuse — coming next")
                            .font(.psCallout).foregroundStyle(Theme.ink3)
                    }
                } else {
                    EmptyPlanState().padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s2)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.large)
        .planChrome()
    }
}

// MARK: - Settings (minimal shell)

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("calendarSyncEnabled") private var calendarSync = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $calendarSync) {
                    Label("Add plan to Calendar", systemImage: "calendar")
                }
                .onChange(of: calendarSync) { _, on in
                    if on {
                        Task {
                            await appState.syncCalendar()
                            if appState.errorMessage != nil { calendarSync = false }
                        }
                    } else {
                        appState.clearCalendar()
                    }
                }
            } header: { Text("Sync") } footer: {
                Text("Adds your workouts to a dedicated “PaceSync” calendar on your phone.")
            }
            Section("Completion") {
                LabeledContent("Auto-match from Apple Watch") { Text("On").foregroundStyle(Theme.ink3) }
            }
            Section("Units") {
                LabeledContent("Distance") { Text("Kilometres").foregroundStyle(Theme.ink3) }
            }
            Section {
                LabeledContent("Version") { Text("PaceSync 2.0").foregroundStyle(Theme.ink3) }
            }
        }
        .navigationTitle("Settings")
    }
}
