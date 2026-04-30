// HomeView.swift (file: ImportView.swift)
// Chat-style entry point: persistent input bar + plan card.

import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    // Direct observation of PlanStore ensures clear() / updateDay() re-render immediately
    // without relying on the objectWillChange forwarding chain in AppState.
    @ObservedObject private var planStore = PlanStore.shared
    @FocusState private var inputFocused: Bool
    @State private var inputText       = ""
    @State private var showFilePicker  = false
    @State private var showRaceDateSheet = false
    @State private var showRenameAlert = false
    @State private var showSettings    = false
    @State private var renameText      = ""
    @State private var navigateToPlan      = false
    @State private var hasAutoNavigated    = false

    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private var plan: SavedPlan? { planStore.current }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Main content — tap anywhere here to dismiss keyboard
                    ZStack {
                        if appState.isLoading {
                            parsingView
                        } else if let plan {
                            planCardArea(plan: plan)
                        } else {
                            emptyState
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = false }

                    // Error bubble
                    if let error = appState.errorMessage {
                        errorBubble(error)
                    }

                    // Input bar — always visible
                    inputBar
                }
            }
            .navigationTitle("PaceSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPlan) {
                if let plan { PlanScheduleView(savedPlan: plan) }
            }
            .onAppear {
                // Auto-push to the plan on first appearance when a plan already exists
                if plan != nil && !hasAutoNavigated {
                    hasAutoNavigated = true
                    navigateToPlan = true
                }
            }
            .onChange(of: planStore.current?.id) { _, newID in
                // Navigate whenever a new plan is imported
                if newID != nil {
                    navigateToPlan = true
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPicker { url in
                    Task { await appState.importFile(from: url) }
                }
            }
            .sheet(isPresented: $showRaceDateSheet) {
                RaceDateSheet().environmentObject(appState)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .alert("Rename Plan", isPresented: $showRenameAlert) {
                TextField("Plan name", text: $renameText)
                Button("Save") { appState.planStore.rename(renameText) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Empty state (pinned to top)

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 90, height: 90)
                Image(systemName: "figure.run")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.green)
            }
            VStack(spacing: 8) {
                Text("PaceSync")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Paste or describe your training plan below,\nor tap the paperclip to attach a PDF or text file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.top, 48)
        .padding(.horizontal, 32)
    }

    // MARK: - Parsing state (with progress bar)

    private var parsingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 70, height: 70)
                Image(systemName: "figure.run")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
            }
            .padding(.top, 48)

            VStack(spacing: 12) {
                Text(appState.parsingPhase.isEmpty ? "Processing…" : appState.parsingPhase)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .animation(.default, value: appState.parsingPhase)
                    .frame(maxWidth: 260, alignment: .center)
                    .multilineTextAlignment(.center)

                ProgressView(value: appState.parsingProgress)
                    .tint(.green)
                    .frame(maxWidth: 260)
                    .animation(.easeOut(duration: 0.4), value: appState.parsingProgress)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Plan card area

    @ViewBuilder
    private func planCardArea(plan: SavedPlan) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                PlanCardView(
                    plan: plan,
                    unit: unit,
                    onViewPlan:    { navigateToPlan = true },
                    onRename:      { renameText = plan.title; showRenameAlert = true },
                    onSetRaceDate: { showRaceDateSheet = true }
                )
                .padding(.horizontal)
                .padding(.top, 16)

                // Secondary actions
                HStack(spacing: 20) {
                    Button {
                        Task { await appState.reparse() }
                    } label: {
                        Label("Re-parse", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("·").foregroundStyle(.tertiary)

                    Button(role: .destructive) {
                        Task { appState.planStore.clear() }
                    } label: {
                        Label("Remove plan", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Error bubble

    @ViewBuilder
    private func errorBubble(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { appState.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color(UIColor.systemGray4))

            HStack(alignment: .bottom, spacing: 10) {
                // Attach file
                Button { showFilePicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                // Text input
                TextField("Paste or describe a training plan…", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemGray6))
                    .foregroundStyle(.white)
                    .cornerRadius(18)
                    .font(.subheadline)
                    .focused($inputFocused)

                // Send
                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    inputText = ""
                    inputFocused = false
                    Task { await appState.importText(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.gray : Color.green
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.bottom, 4)
        }
        .background(Color.black)
    }
}

// MARK: - PlanCardView

struct PlanCardView: View {
    let plan: SavedPlan
    let unit: DistanceUnit
    let onViewPlan: () -> Void
    let onRename: () -> Void
    let onSetRaceDate: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // Title + rename + stats
            VStack(spacing: 10) {
                Text(plan.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Button(action: onRename) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.caption2.bold())
                        Text("Rename")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(8)
                }

                HStack(spacing: 16) {
                    statBadge(icon: "calendar",    value: "\(plan.plan.weeks.count) weeks")
                    statBadge(icon: "figure.run",  value: "\(plan.workoutCount) workouts")
                    if plan.totalMiles > 1 {
                        let total = plan.totalMiles
                        statBadge(icon: "road.lanes",
                                  value: "~\(unit.format(total, decimals: 0)) total")
                    }
                }
            }
            .padding()

            Divider().background(Color(UIColor.systemGray4))

            // Race date row
            Button(action: onSetRaceDate) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.green)
                        .frame(width: 22)

                    if let raceDate = plan.raceDate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Race Day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(raceDate, style: .date)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        if let weekIndex = plan.currentWeekIndex {
                            Text("Week \(weekIndex + 1) of \(plan.plan.weeks.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Set race date")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }

            Divider().background(Color(UIColor.systemGray4))

            // View plan
            Button(action: onViewPlan) {
                HStack {
                    Text("View Plan")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                .padding()
            }
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(16)
    }

    private func statBadge(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - RaceDateSheet

struct RaceDateSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    DatePicker(
                        "Race Date",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .tint(.green)
                    .colorScheme(.dark)
                    .padding()

                    if appState.planStore.current?.raceDate != nil {
                        Button("Remove Race Date") {
                            appState.planStore.setRaceDate(nil)
                            dismiss()
                        }
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .padding(.bottom, 8)
                    }

                    Spacer()
                }
            }
            .navigationTitle("Race Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") {
                        appState.planStore.setRaceDate(selectedDate)
                        dismiss()
                    }
                    .font(.headline)
                    .tint(.green)
                }
            }
            .onAppear {
                selectedDate = appState.planStore.current?.raceDate
                    ?? Calendar.current.date(byAdding: .month, value: 3, to: Date())!
            }
        }
    }
}

// MARK: - SettingsSheet

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Picker("Distance", selection: $distanceUnitRaw) {
                            ForEach(DistanceUnit.allCases, id: \.rawValue) { unit in
                                Text(unit.displayName).tag(unit.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color(UIColor.systemGray6))
                    } header: {
                        Text("Units")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        HStack {
                            Text("Version")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.secondary)
                                .font(.subheadline.monospacedDigit())
                        }
                        .listRowBackground(Color(UIColor.systemGray6))
                    } header: {
                        Text("About")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .tint(.green)
                }
            }
        }
    }
}
