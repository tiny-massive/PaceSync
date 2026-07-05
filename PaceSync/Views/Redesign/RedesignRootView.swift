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

// MARK: - Shared "+" create action (top-right on Today and Plans)

struct AddToolbar: ToolbarContent {
    var onAdd: () -> Void = {}
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
            }
            .tint(Theme.accent)
            .accessibilityLabel("Add")
        }
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
                        PlanCard(plan: plan, unit: unit)
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
        .toolbar { AddToolbar() }
    }
}

// MARK: - Settings (minimal shell)

struct SettingsView: View {
    var body: some View {
        List {
            Section("Units") {
                LabeledContent("Distance", value: "Kilometres")
            }
            Section("Sync") {
                LabeledContent {
                    Text("On").foregroundStyle(Theme.ink3)
                } label: {
                    Label("Apple Watch", systemImage: "applewatch")
                }
                LabeledContent {
                    Text("Off").foregroundStyle(Theme.ink3)
                } label: {
                    Label("Calendar", systemImage: "calendar")
                }
            }
            Section("Completion") {
                LabeledContent("Auto-match from Apple Watch", value: "On")
            }
            Section {
                LabeledContent("Version", value: "PaceSync 2.0")
            }
        }
        .navigationTitle("Settings")
    }
}
