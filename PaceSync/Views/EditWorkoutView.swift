// EditWorkoutView.swift
// Edit segments on a workout day before scheduling.

import SwiftUI

// MARK: - EditWorkoutView

struct EditWorkoutView: View {
    let dayID: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var segments: [WorkoutSegment] = []
    @State private var editingSegment: WorkoutSegment?
    @State private var addingSegment = false

    @AppStorage("distanceUnit") private var unit: DistanceUnit = .kilometers

    private var day: WorkoutDay? {
        appState.planStore.current?.plan.allDays.first { $0.id == dayID }
    }

    private var displayItems: [SegmentDisplayItem] {
        groupedSegmentItems(from: segments)
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            List {
                ForEach(displayItems) { item in
                    switch item {
                    case .single(let segment):
                        Button { editingSegment = segment } label: {
                            SegmentEditRow(segment: segment, unit: unit)
                        }
                        .listRowBackground(Theme.surface)

                    case .repeatGroup(_, let iterations, let groupSegments):
                        Section {
                            ForEach(groupSegments) { segment in
                                Button { editingSegment = segment } label: {
                                    SegmentEditRow(segment: segment, unit: unit, showReps: false)
                                }
                                .listRowBackground(Theme.surfaceRaised)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "repeat")
                                    .font(.psCaption)
                                    .foregroundStyle(Theme.ink3)
                                SectionHeader(text: "Repeat × \(iterations)")
                            }
                        }
                    }
                }

                Button {
                    addingSegment = true
                } label: {
                    Label("Add Segment", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.psHeadline)
                }
                .listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.psHeadline)
                    .tint(Theme.accent)
            }
        }
        .sheet(item: $editingSegment) { segment in
            EditSegmentSheet(segment: segment, unit: unit) { updated in
                if let i = segments.firstIndex(where: { $0.id == updated.id }) {
                    segments[i] = updated
                }
            }
        }
        .sheet(isPresented: $addingSegment) {
            EditSegmentSheet(
                segment: WorkoutSegment(id: UUID(), type: .easy,
                                        durationSeconds: nil, distanceMiles: nil),
                unit: unit
            ) { new in
                segments.append(new)
            }
        }
        .onAppear {
            if let day { segments = day.segments }
        }
    }

    private func save() {
        guard var day else { return }
        day.segments = segments
        // If already scheduled, reset so user re-sends updated version
        if appState.scheduleStatuses[dayID] == .scheduled {
            appState.resetScheduleStatus(for: day)
        }
        appState.planStore.updateDay(day)
        dismiss()
    }
}

// MARK: - Segment edit row (list cell)

private struct SegmentEditRow: View {
    let segment: WorkoutSegment
    let unit: DistanceUnit
    var showReps: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.type.rawValue.capitalized)
                    .font(.psHeadline)
                    .foregroundStyle(Theme.ink)
                Text(segment.label(unit: unit, showReps: showReps))
                    .font(.psCallout)
                    .foregroundStyle(Theme.ink2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.psCaption)
                .foregroundStyle(Theme.ink3)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - EditSegmentSheet

struct EditSegmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let unit: DistanceUnit
    let onSave: (WorkoutSegment) -> Void

    @State private var type: SegmentType
    @State private var durationMinutes: String
    @State private var distanceInput: String   // stored in user's unit
    @State private var reps: Int
    @State private var effort: EffortLevel?

    /// The original segment, so fields the editor doesn't manage (distanceMeters for track
    /// intervals, recovery rest, the repeat-group index) survive an edit instead of being wiped.
    private let original: WorkoutSegment
    /// The strings we seeded the fields with — let us tell whether the user changed them.
    private let seededDistanceInput: String
    private let seededDurationInput: String
    private var segmentID: UUID { original.id }

    init(segment: WorkoutSegment, unit: DistanceUnit = .kilometers,
         onSave: @escaping (WorkoutSegment) -> Void) {
        self.onSave    = onSave
        self.unit      = unit
        self.original  = segment
        _type            = State(initialValue: segment.type)
        let seededDur = segment.durationSeconds.map { String($0 / 60) } ?? ""
        self.seededDurationInput = seededDur
        _durationMinutes = State(initialValue: seededDur)
        // Seed the distance field from miles, or from a metre value (track intervals) converted
        // to the display unit, so a 1000m rep shows a value instead of an empty field.
        let seededMiles = segment.distanceMiles ?? segment.distanceMeters.map { $0 / 1609.34 }
        let seeded = seededMiles.map { String(format: "%.2f", unit.convert($0)) } ?? ""
        self.seededDistanceInput = seeded
        _distanceInput   = State(initialValue: seeded)
        _reps            = State(initialValue: segment.reps ?? 1)
        _effort          = State(initialValue: segment.effort)
    }

    private var showReps: Bool { type == .interval || type == .hills }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                Form {
                    Section {
                        Picker("Segment type", selection: $type) {
                            ForEach(SegmentType.allCases, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        .pickerStyle(.wheel)
                    } header: { SectionHeader(text: "Type") }
                    .listRowBackground(Theme.surface)

                    Section {
                        HStack {
                            Text("Minutes")
                                .foregroundStyle(Theme.ink2)
                            Spacer()
                            TextField("—", text: $durationMinutes)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.ink)
                                .frame(width: 80)
                        }
                        HStack {
                            Text(unit.displayName)
                                .foregroundStyle(Theme.ink2)
                            Spacer()
                            TextField("—", text: $distanceInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Theme.ink)
                                .frame(width: 80)
                        }
                    } header: { SectionHeader(text: "Duration / Distance") }
                    .listRowBackground(Theme.surface)

                    if showReps {
                        Section {
                            Stepper("Reps: \(reps)", value: $reps, in: 1...30)
                                .foregroundStyle(Theme.ink)
                        } header: { SectionHeader(text: "Repetitions") }
                        .listRowBackground(Theme.surface)
                    }

                    Section {
                        Picker("Effort", selection: $effort) {
                            Text("None").tag(Optional<EffortLevel>.none)
                            ForEach(EffortLevel.allCases, id: \.self) { e in
                                Text(e.displayName).tag(Optional<EffortLevel>.some(e))
                            }
                        }
                        .pickerStyle(.wheel)
                    } header: { SectionHeader(text: "Effort") }
                    .listRowBackground(Theme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.ink2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveAndDismiss() }
                        .font(.psHeadline).tint(Theme.accent)
                }
            }
        }
    }

    private func saveAndDismiss() {
        // Keep the exact original seconds when the minutes field is untouched — the field shows
        // only whole minutes, so recomputing would truncate e.g. a 90s recovery to 60s.
        let durTrimmed = durationMinutes.trimmingCharacters(in: .whitespaces)
        let seconds: Int? = (durTrimmed == seededDurationInput)
            ? original.durationSeconds
            : Int(durTrimmed).map { $0 * 60 }
        let trimmed = distanceInput.trimmingCharacters(in: .whitespaces)

        // If the distance field is untouched, keep the original representation exactly (so a
        // metre-based interval keeps its metres). If edited, store the typed value as miles.
        let distanceMiles: Double?
        let distanceMeters: Double?
        if trimmed == seededDistanceInput {
            distanceMiles  = original.distanceMiles
            distanceMeters = original.distanceMeters
        } else {
            distanceMiles  = Double(trimmed).map { unit.toMiles($0) }
            distanceMeters = nil
        }

        let segment = WorkoutSegment(
            id: segmentID,
            type: type,
            durationSeconds: seconds,
            distanceMiles: distanceMiles,
            distanceMeters: distanceMeters,
            reps: showReps ? reps : original.reps,
            restDurationSeconds: original.restDurationSeconds,   // preserve recovery rest
            effort: effort,
            setIndex: original.setIndex                          // keep it in its repeat group
        )
        onSave(segment)
        dismiss()
    }
}
