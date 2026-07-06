// RedesignRootView.swift
// New root: three destinations — Today · Plans · Settings — via a native TabView,
// which renders as Liquid Glass automatically on iOS 26 (and a normal bar below it).
// The "+" create action lives top-right on the Today and Plans roots.

import SwiftUI
import UniformTypeIdentifiers

struct RedesignRootView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometers
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { TodayView(unit: unit) }
                .tag(0)
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { PlansView(unit: unit) }
                .tag(1)
                .tabItem { Label("Plans", systemImage: "square.stack.3d.up") }

            NavigationStack { SettingsView() }
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.psCallout).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, Theme.s4).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    .padding(.top, Theme.s2)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: appState.toast)
        .onAppear {
            #if DEBUG
            // Test hook: launch straight to a tab via SIMCTL_CHILD_PACESYNC_TAB. Inert in normal use.
            if let t = ProcessInfo.processInfo.environment["PACESYNC_TAB"], let i = Int(t) { selection = i }
            #endif
        }
    }
}

// MARK: - Plans (library) — the active plan + every other saved plan you can switch to

struct PlansView: View {
    @EnvironmentObject var appState: AppState
    var unit: DistanceUnit = .kilometers
    @State private var pendingRemove: SavedPlan?

    private var store: PlanStore { appState.planStore }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                if let active = store.current {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeader(text: "Active")
                        ProgressCard(plan: active, unit: unit)
                    }
                }
                let others = store.plans.filter { $0.id != store.activePlanID }
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeader(text: store.current == nil ? "My plans" : "Switch plan")
                        PSCard(padded: false) {
                            ForEach(Array(others.enumerated()), id: \.element.id) { i, plan in
                                Button { appState.activatePlan(plan.id) } label: { planRow(plan) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { appState.activatePlan(plan.id) } label: {
                                            Label("Make active", systemImage: "checkmark.circle")
                                        }
                                        Button(role: .destructive) { pendingRemove = plan } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                if i < others.count - 1 {
                                    Rectangle().fill(Theme.hairline).frame(height: 1)
                                        .padding(.leading, Theme.s4)
                                }
                            }
                        }
                    }
                }
                oneOffSection
                if store.plans.isEmpty && store.standaloneWorkouts.isEmpty {
                    EmptyPlanState().padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s2)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)   // centered, matching Home
        .addPlanChrome()
        .alert("Remove this plan?", isPresented: Binding(
            get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })) {
            Button("Remove", role: .destructive) { if let p = pendingRemove { appState.removePlan(p.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the plan from PaceSync and clears its calendar events.")
        }
    }

    @ViewBuilder private var oneOffSection: some View {
        let oneOffs = store.standaloneWorkouts.sorted { $0.date < $1.date }
        if !oneOffs.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(text: "One-off workouts")
                PSCard(padded: false) {
                    ForEach(Array(oneOffs.enumerated()), id: \.element.id) { i, sw in
                        TodayWorkoutRow(day: sw.day, dateText: PlansView.oneOffFmt.string(from: sw.date),
                                        plannedDate: sw.date, unit: unit, standaloneID: sw.id)
                            .padding(.horizontal, Theme.s4).padding(.vertical, Theme.s3)
                        if i < oneOffs.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, Theme.s4)
                        }
                    }
                }
            }
        }
    }
    static let oneOffFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()

    private func planRow(_ plan: SavedPlan) -> some View {
        HStack(spacing: Theme.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle(plan)).font(.psCallout).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: Theme.s2)
            Text("Activate").font(.psCaption).foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s3)
        .contentShape(Rectangle())
    }

    private func subtitle(_ plan: SavedPlan) -> String {
        var parts = ["\(plan.plan.weeks.count)-week plan"]
        if let r = plan.raceDate { parts.append("Race \(PlansView.fmt.string(from: r))") }
        if plan.completedCount > 0 { parts.append("\(plan.completedCount) done") }
        return parts.joined(separator: " · ")
    }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f }()
}

// MARK: - Settings (minimal shell)

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("calendarSyncEnabled") private var calendarSync = false
    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometers
    @State private var cacheSize = PlanParseCache.shared.cacheSizeString
    @State private var showClearCache = false
    @State private var revertingSync = false   // programmatic toggle-off after a failed sync
    @State private var exportURL: URL?
    @State private var showRestore = false
    @State private var restoreResult: String?

    var body: some View {
        List {
            Section("Units") {
                Picker(selection: $unit) {
                    ForEach(DistanceUnit.allCases, id: \.self) { u in
                        Text(u.displayName).tag(u)
                    }
                } label: {
                    Label("Distance", systemImage: "ruler")
                }
                .pickerStyle(.menu)
            }

            Section {
                Toggle(isOn: $calendarSync) {
                    Label("Add plan to Calendar", systemImage: "calendar")
                }
                .onChange(of: calendarSync) { _, on in
                    // A failed sync flips the toggle back off; that revert must NOT run
                    // clearCalendar (there's nothing synced to clear, and access is denied).
                    if revertingSync { revertingSync = false; return }
                    if on {
                        Task {
                            appState.errorMessage = nil   // don't let a stale error revert a good sync
                            await appState.syncCalendar()
                            // Only flip the toggle back if it's still on. If the user already
                            // turned it off mid-sync, setting it false again would be a no-op that
                            // never re-fires onChange, leaving revertingSync stuck true.
                            if appState.errorMessage != nil, calendarSync {
                                revertingSync = true
                                calendarSync = false
                            }
                        }
                    } else {
                        appState.clearCalendar()
                    }
                }
            } header: { Text("Sync") } footer: {
                Text("Adds your workouts to a dedicated “PaceSync” calendar on your phone.")
            }

            Section {
                LabeledContent {
                    Text("On").foregroundStyle(Theme.ink3)
                } label: {
                    Label("Auto-match from Apple Watch", systemImage: "applewatch")
                }
            } header: { Text("Completion") } footer: {
                Text("Finished runs on your Watch tick off matching workouts automatically. You can always mark a workout done by hand.")
            }

            Section("Storage") {
                Button {
                    PlanParseCache.shared.clearAll()
                    cacheSize = PlanParseCache.shared.cacheSizeString
                    showClearCache = true
                } label: {
                    LabeledContent {
                        Text(cacheSize).foregroundStyle(Theme.ink3)
                    } label: {
                        Label("Clear parse cache", systemImage: "trash")
                    }
                }
                .tint(Theme.ink)
            }

            Section {
                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Export plans", systemImage: "square.and.arrow.up")
                    }
                }
                Button { showRestore = true } label: {
                    Label("Restore from file", systemImage: "square.and.arrow.down")
                }
                .tint(Theme.ink)
            } header: { Text("Backup") } footer: {
                Text("Export saves a backup file to keep in Files or iCloud Drive. Your plans are also backed up to iCloud automatically once iCloud is enabled for the app.")
            }

            Section {
                LabeledContent("Plans saved") {
                    Text("\(appState.planStore.plans.count)").foregroundStyle(Theme.ink3)
                }
                LabeledContent("Version") {
                    Text("PaceSync 2.0").foregroundStyle(Theme.ink3)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { cacheSize = PlanParseCache.shared.cacheSizeString; prepareExport() }
        .onChange(of: appState.planStore.plans.count) { _, _ in prepareExport() }
        .fileImporter(isPresented: $showRestore,
                      allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                let n = appState.planStore.importBackup(data)
                restoreResult = n > 0 ? "Restored \(n) plan\(n == 1 ? "" : "s")." : "That file isn't a PaceSync backup."
            } else {
                restoreResult = "Couldn't read that file."
            }
        }
        .alert("Cache cleared", isPresented: $showClearCache) {
            Button("OK") {}
        } message: { Text("Parsed-plan cache removed. Re-importing will parse fresh.") }
        .alert("Restore", isPresented: Binding(
            get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } })) {
            Button("OK") {}
        } message: { Text(restoreResult ?? "") }
    }

    private func prepareExport() {
        guard !appState.planStore.plans.isEmpty, let data = appState.planStore.exportData() else {
            exportURL = nil; return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaceSync-backup.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }
}
