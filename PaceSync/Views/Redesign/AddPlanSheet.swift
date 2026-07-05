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
    @State private var title = ""
    @State private var raceDate = Calendar.current.date(byAdding: .day, value: 84, to: Date()) ?? Date()
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your plan") {
                    TextField("Name (optional)", text: $title)
                    TextField("Paste your training plan…", text: $text, axis: .vertical)
                        .lineLimit(6...12)
                    Button { showFileImporter = true } label: {
                        Label("Attach a PDF or text file", systemImage: "paperclip")
                    }
                }
                Section("Race day") {
                    DatePicker("Race day", selection: $raceDate,
                               in: Date()..., displayedComponents: .date)
                }
            }
            .navigationTitle("Add plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Build") { Task { await buildFromText() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.pdf, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await buildFromFile(url) }
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
                ProgressView(value: appState.parsingProgress)
                    .frame(width: 200)
                Text(appState.parsingPhase.isEmpty ? "Reading your plan…" : appState.parsingPhase)
                    .font(.psCallout).foregroundStyle(Theme.ink2)
            }
            .padding(Theme.s5)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard))
        }
    }

    private func buildFromText() async {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Training Plan" : title
        await appState.importText(text, title: name, raceDate: raceDate)
        if appState.errorMessage == nil { dismiss() }
    }

    private func buildFromFile(_ url: URL) async {
        await appState.importFile(from: url, raceDate: raceDate)
        if appState.errorMessage == nil { dismiss() }
    }
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

// MARK: - Plan chrome (toolbar: "+" add, "⋯" lifecycle) shared by Today & Plans

struct PlanChrome: ViewModifier {
    @EnvironmentObject var appState: AppState
    @State private var showAdd = false
    @State private var showRename = false
    @State private var showRaceDate = false
    @State private var showRemove = false
    @State private var renameText = ""
    @State private var raceDate = Date()

    func body(content: Content) -> some View {
        content
            .toolbar {
                if appState.planStore.current != nil {
                    ToolbarItem(placement: .topBarLeading) {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("Add plan")
                }
            }
            .sheet(isPresented: $showAdd) { AddPlanSheet().environmentObject(appState) }
            .sheet(isPresented: $showRaceDate) {
                RaceDaySheet(date: $raceDate) { appState.planStore.setRaceDate(raceDate) }
            }
            .alert("Rename plan", isPresented: $showRename) {
                TextField("Name", text: $renameText)
                Button("Save") { appState.planStore.rename(renameText) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Remove this plan?", isPresented: $showRemove) {
                Button("Remove", role: .destructive) { appState.planStore.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the plan from PaceSync.")
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
    func planChrome() -> some View { modifier(PlanChrome()) }
}
