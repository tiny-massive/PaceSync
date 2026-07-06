// AddPlanSheet.swift
// The "+" import flow + plan-lifecycle chrome (rename / change race day / re-import / remove),
// reconnected to the real AppState/PlanStore actions.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add / import a plan

struct AddPlanSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Race day
    @State private var raceDate: Date? = nil               // unset until chosen (skippable)
    @State private var pickerDate = AddPlanSheet.defaultRaceDay()
    @State private var showDatePicker = false
    @State private var showRaceSkip = false
    @State private var importAfterRaceDay = false
    // Import a plan
    @State private var planText = ""
    @State private var attachedFileURL: URL?               // attached, NOT parsed until Import
    @State private var showFileImporter = false
    @State private var showPasteField = false
    // One-off workout
    @State private var workoutText = ""
    @State private var workoutDate = Calendar.current.startOfDay(for: Date())

    private var hasPlanContent: Bool {
        attachedFileURL != nil || !planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                raceDaySection
                importPlanSection
                oneOffSection
            }
            .navigationTitle("Add Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showDatePicker) {
                RaceDaySheet(date: $pickerDate) {
                    raceDate = pickerDate
                    if importAfterRaceDay { importAfterRaceDay = false; Task { await runImport() } }
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: planFileTypes, allowsMultipleSelection: false) { result in
                // Attach ONLY — copy into temp now while we hold access; parse on Import.
                if case .success(let urls) = result, let url = urls.first {
                    attachedFileURL = copyToTemp(url); showPasteField = false
                }
            }
            .overlay { if appState.isLoading { progress } }
            .interactiveDismissDisabled(appState.isLoading || appState.isBuildingWorkout)
            .alert("No race day set", isPresented: $showRaceSkip) {
                Button("Add Race Day") {
                    importAfterRaceDay = true; pickerDate = AddPlanSheet.defaultRaceDay(); showDatePicker = true
                }
                Button("Skip for Now") { Task { await runImport() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your workouts won't have dates until you set one. You can add it any time from the plan's menu.")
            }
            .alert("Couldn't add plan", isPresented: errorBinding(appState)) {
                Button("OK") {}
            } message: { Text(appState.errorMessage ?? "") }
        }
    }

    // MARK: Section 1 — Race day

    @ViewBuilder private var raceDaySection: some View {
        Section {
            if let raceDate {
                Button { pickerDate = raceDate; showDatePicker = true } label: {
                    HStack {
                        Text("Race day").foregroundStyle(Theme.ink)
                        Spacer()
                        Text(AddPlanSheet.fmt.string(from: raceDate)).foregroundStyle(Theme.accent)
                    }
                }
                .tint(Theme.ink)
            } else {
                Button { pickerDate = AddPlanSheet.defaultRaceDay(); showDatePicker = true } label: {
                    Label("Set race day", systemImage: "calendar.badge.plus")
                }
                .tint(Theme.accent)
            }
        } header: { Text("Race day") } footer: {
            Text("PaceSync dates every workout by counting back from race day. You can skip this and add it later.")
        }
    }

    // MARK: Section 2 — Import a plan

    @ViewBuilder private var importPlanSection: some View {
        Section {
            Text("Upload your full training plan — PDF, Markdown (.md), or plain text (.txt). A file with a clear week-by-week layout parses best.")
                .font(.psCallout).foregroundStyle(Theme.ink2)

            if let url = attachedFileURL {
                HStack(spacing: Theme.s2) {
                    Label(url.lastPathComponent, systemImage: "doc")
                        .lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.ink)
                    Spacer()
                    Button { attachedFileURL = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Remove file")
                }
            } else {
                Button { showFileImporter = true } label: {
                    Label("Choose File", systemImage: "doc.badge.plus")
                }
                .tint(Theme.accent)

                if showPasteField {
                    TextField("Paste your whole plan here…", text: $planText, axis: .vertical)
                        .lineLimit(6...12)
                } else {
                    Button { showPasteField = true } label: {
                        Text("Paste plan text instead").font(.psCaption)
                    }
                    .tint(Theme.ink3)
                }
            }

            Button {
                if raceDate == nil { showRaceSkip = true } else { Task { await runImport() } }
            } label: {
                Text("Import Plan").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
            .disabled(!hasPlanContent || appState.isLoading)
        } header: { Text("Import a plan") }
    }

    // MARK: Section 3 — One-off workout

    @ViewBuilder private var oneOffSection: some View {
        Section {
            Text("Not importing a whole plan? Describe a single workout and PaceSync will build it, ready for your Apple Watch.")
                .font(.psCallout).foregroundStyle(Theme.ink2)

            TextField("3K warm-up, then 3×10min threshold, 2K cool-down", text: $workoutText, axis: .vertical)
                .lineLimit(3...8)
            DatePicker("Workout date", selection: $workoutDate,
                       in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)

            if let e = appState.workoutBuildError {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.psCaption).foregroundStyle(Theme.error)
            }

            Button {
                Task {
                    if await appState.createStandaloneWorkout(text: workoutText, on: workoutDate) { dismiss() }
                }
            } label: {
                HStack(spacing: 8) {
                    if appState.isBuildingWorkout {
                        ProgressView().controlSize(.small)
                        Text("Building your workout…")
                    } else {
                        Text("Create Workout")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
            .disabled(workoutText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isBuildingWorkout)
        } header: { Text("Single custom workout") }
    }

    // MARK: Progress overlay (full-plan import only)

    private var progress: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Theme.s3) {
                ProgressView(value: appState.parsingProgress).frame(width: 200)
                Text(progressLine).font(.psCallout).foregroundStyle(Theme.ink2)
            }
            .padding(Theme.s5)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard))
        }
    }

    private var progressLine: String {
        if !appState.parsingPhase.isEmpty { return appState.parsingPhase }
        if let raceDate { return "Building your plan around \(AddPlanSheet.shortFmt.string(from: raceDate))…" }
        return "Reading your plan…"
    }

    // MARK: Actions

    private func runImport() async {
        if let url = attachedFileURL {
            await appState.importFile(from: url, raceDate: raceDate)
        } else {
            let title = raceDate.map { "Plan · \(AddPlanSheet.shortFmt.string(from: $0))" } ?? "Training Plan"
            await appState.importText(planText, title: title, raceDate: raceDate)
        }
        if appState.errorMessage == nil { dismiss() }
    }

    private var planFileTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        return types
    }

    /// Copy a security-scoped picked file into temp now (while access is held) so it can be parsed
    /// later on Import. Returns the temp URL (or the original on failure).
    private func copyToTemp(_ url: URL) -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); return dest }
        catch { return url }
    }

    /// ~12 weeks out, snapped forward to the next Sunday (races are almost always weekends).
    private static func defaultRaceDay() -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: 84, to: Date()) ?? Date()
        let weekday = cal.component(.weekday, from: base)   // 1 = Sunday
        return cal.date(byAdding: .day, value: (8 - weekday) % 7, to: base) ?? base
    }

    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE, d MMM yyyy"; return f }()
    static let shortFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f }()
}

// MARK: - Change race day

struct RaceDaySheet: View {
    @Binding var date: Date
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Race day", selection: $date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Race day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Add-plan chrome (top-right "+") — for the Home & Plans overviews

struct AddPlanChrome: ViewModifier {
    @EnvironmentObject var appState: AppState
    @State private var showAdd = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("Add plan")
                }
            }
            .sheet(isPresented: $showAdd) { AddPlanSheet().environmentObject(appState) }
            .alert("Something went wrong", isPresented: errorBinding(appState)) {
                Button("OK") {}
            } message: { Text(appState.errorMessage ?? "") }
    }
}

// MARK: - Plan-settings chrome (top-right "⋯": rename / change race day / re-import / remove)
//   Lives on the full-plan detail screen, where exactly ONE plan is in view — so "rename",
//   "change race day" etc. are unambiguous (unlike on the multi-plan Plans overview).

struct PlanSettingsChrome: ViewModifier {
    @EnvironmentObject var appState: AppState
    @State private var showRename = false
    @State private var showRaceDate = false
    @State private var showRemove = false
    @State private var renameText = ""
    @State private var raceDate = Date()

    func body(content: Content) -> some View {
        content
            .toolbar {
                if appState.planStore.current != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                renameText = appState.planStore.current?.title ?? ""
                                showRename = true
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button {
                                raceDate = appState.planStore.current?.raceDate ?? Date()
                                showRaceDate = true
                            } label: { Label("Change race day", systemImage: "calendar") }
                            Button { Task { await appState.reparse() } } label: {
                                Label("Re-import", systemImage: "arrow.clockwise")
                            }
                            Divider()
                            Button(role: .destructive) { showRemove = true } label: {
                                Label("Remove plan", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .sheet(isPresented: $showRaceDate) {
                RaceDaySheet(date: $raceDate) {
                    appState.planStore.setRaceDate(raceDate)
                    appState.scheduleStatuses = [:]        // clear stale transient status
                    Task {
                        await appState.autoMatchCompletions()
                        if UserDefaults.standard.bool(forKey: "calendarSyncEnabled") {
                            await appState.syncCalendar()   // move events to the new dates
                        }
                    }
                }
            }
            .alert("Rename plan", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") { appState.planStore.rename(renameText) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Remove this plan?", isPresented: $showRemove) {
                Button("Remove", role: .destructive) {
                    if let id = appState.planStore.activePlanID { appState.removePlan(id) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the plan from PaceSync and clears its calendar events.")
            }
            .alert("Something went wrong", isPresented: errorBinding(appState)) {
                Button("OK") {}
            } message: { Text(appState.errorMessage ?? "") }
    }
}

/// Presents AppState.errorMessage as a dismissable alert binding.
func errorBinding(_ appState: AppState) -> Binding<Bool> {
    Binding(get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } })
}

extension View {
    func addPlanChrome() -> some View { modifier(AddPlanChrome()) }
    func planSettingsChrome() -> some View { modifier(PlanSettingsChrome()) }
}
