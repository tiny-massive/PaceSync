// AddPlanSheet.swift
// The "+" import flow + plan-lifecycle chrome (rename / change race day / re-import / remove),
// reconnected to the real AppState/PlanStore actions.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Add / import a plan

struct AddPlanSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var raceDate: Date? = nil               // unset until the user chooses (no silent default)
    @State private var attachedFileURL: URL?               // attached, NOT parsed until Create
    @State private var showFileImporter = false
    @State private var showDatePicker = false
    @State private var pickerDate = AddPlanSheet.defaultRaceDay()

    private var hasPlanContent: Bool {
        attachedFileURL != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canCreate: Bool { raceDate != nil && hasPlanContent }

    var body: some View {
        NavigationStack {
            Form {
                // 1) Race day — the anchor every workout is dated from, so it comes first.
                Section {
                    if let raceDate {
                        Button {
                            pickerDate = raceDate; showDatePicker = true
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("Race day").foregroundStyle(Theme.ink)
                                    Spacer()
                                    Text(AddPlanSheet.fmt.string(from: raceDate)).foregroundStyle(Theme.accent)
                                }
                                Text(weeksCaption(raceDate)).font(.psCaption).foregroundStyle(Theme.ink3)
                            }
                        }
                        .tint(Theme.ink)
                    } else {
                        Button {
                            pickerDate = AddPlanSheet.defaultRaceDay(); showDatePicker = true
                        } label: {
                            Label("Set race day", systemImage: "calendar.badge.plus")
                        }
                        .tint(Theme.accent)
                    }
                } header: { Text("Race day") } footer: {
                    Text("Every workout is dated by counting back from race day, so set it first.")
                }

                // 2) The plan — upload a file OR paste text (last action wins).
                Section {
                    Text("Add the plan you're following. PaceSync reads it and turns every workout into a dated session on your Apple Watch and calendar.")
                        .font(.psCallout).foregroundStyle(Theme.ink2)

                    if let url = attachedFileURL {
                        HStack(spacing: Theme.s2) {
                            Label(url.lastPathComponent, systemImage: "doc")
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.ink)
                            Spacer()
                            Button { attachedFileURL = nil } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove file")
                        }
                    } else {
                        Button { showFileImporter = true } label: {
                            Label("Choose a PDF or text file", systemImage: "doc.badge.plus")
                        }
                        .tint(Theme.accent)

                        HStack(spacing: Theme.s2) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                            Text("or").font(.psCaption).foregroundStyle(Theme.ink3)
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        .padding(.vertical, 2)

                        TextField("Paste your plan here…", text: $text, axis: .vertical)
                            .lineLimit(6...12)
                    }
                } header: { Text("Your plan") }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }.disabled(!canCreate)
                }
            }
            .sheet(isPresented: $showDatePicker) {
                RaceDaySheet(date: $pickerDate) { raceDate = pickerDate }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.pdf, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                // Attach ONLY — copy into temp now while we hold access; parse on Create.
                if case .success(let urls) = result, let url = urls.first {
                    attachedFileURL = copyToTemp(url)
                }
            }
            .overlay { if appState.isLoading { progress } }
            .interactiveDismissDisabled(appState.isLoading)
            .alert("Couldn't add plan", isPresented: errorBinding(appState)) {
                Button("OK") {}
            } message: { Text(appState.errorMessage ?? "") }
        }
    }

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

    private func create() async {
        guard let raceDate else { return }
        if let url = attachedFileURL {
            await appState.importFile(from: url, raceDate: raceDate)
        } else {
            await appState.importText(text, title: "Plan · \(AddPlanSheet.shortFmt.string(from: raceDate))",
                                      raceDate: raceDate)
        }
        if appState.errorMessage == nil { dismiss() }
    }

    /// Copy a security-scoped picked file into our temp dir immediately, so we can parse it later
    /// on Create without the scoped access having expired. Returns the temp URL (or the original).
    private func copyToTemp(_ url: URL) -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.copyItem(at: url, to: dest); return dest }
        catch { return url }
    }

    private func weeksCaption(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day],
                    from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: date)).day ?? 0
        let weeks = max(0, days) / 7
        if weeks == 0 { return "This week" }
        return "\(weeks) week\(weeks == 1 ? "" : "s") from today"
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
