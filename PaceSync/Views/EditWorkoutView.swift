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

    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private var day: WorkoutDay? {
        appState.planStore.current?.plan.allDays.first { $0.id == dayID }
    }

    private var displayItems: [SegmentDisplayItem] {
        groupedSegmentItems(from: segments)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            List {
                ForEach(displayItems) { item in
                    switch item {
                    case .single(let segment):
                        Button { editingSegment = segment } label: {
                            SegmentEditRow(segment: segment, unit: unit)
                        }
                        .listRowBackground(Color(UIColor.systemGray6))

                    case .repeatGroup(_, let iterations, let groupSegments):
                        Section {
                            ForEach(groupSegments) { segment in
                                Button { editingSegment = segment } label: {
                                    SegmentEditRow(segment: segment, unit: unit, showReps: false)
                                }
                                .listRowBackground(Color(UIColor.systemGray5))
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "repeat")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                                Text("Repeat × \(iterations)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Button {
                    addingSegment = true
                } label: {
                    Label("Add Segment", systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
                .listRowBackground(Color(UIColor.systemGray6))
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.headline)
                    .tint(.green)
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
            RoundedRectangle(cornerRadius: 3)
                .fill(segmentColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.type.rawValue.capitalized)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(segment.label(unit: unit, showReps: showReps))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var segmentColor: Color {
        switch segment.type {
        case .warmup, .cooldown: return .blue
        case .easy:              return .green
        case .interval, .tempo:  return .orange
        case .hills:             return .yellow
        case .rest:              return .gray
        }
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

    private let segmentID: UUID

    init(segment: WorkoutSegment, unit: DistanceUnit = .miles,
         onSave: @escaping (WorkoutSegment) -> Void) {
        self.onSave    = onSave
        self.unit      = unit
        self.segmentID = segment.id
        _type            = State(initialValue: segment.type)
        _durationMinutes = State(initialValue: segment.durationSeconds.map { String($0 / 60) } ?? "")
        // Convert stored miles → user's preferred unit for display
        _distanceInput   = State(initialValue: segment.distanceMiles.map {
            String(format: "%.2f", unit.convert($0))
        } ?? "")
        _reps            = State(initialValue: segment.reps ?? 1)
        _effort          = State(initialValue: segment.effort)
    }

    private var showReps: Bool { type == .interval || type == .hills }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    Section("Type") {
                        Picker("Segment type", selection: $type) {
                            ForEach(SegmentType.allCases, id: \.self) { t in
                                Text(t.rawValue.capitalized).tag(t)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .listRowBackground(Color(UIColor.systemGray6))

                    Section("Duration / Distance") {
                        HStack {
                            Text("Minutes")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("—", text: $durationMinutes)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.white)
                                .frame(width: 80)
                        }
                        HStack {
                            Text(unit.displayName)
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("—", text: $distanceInput)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.white)
                                .frame(width: 80)
                        }
                    }
                    .listRowBackground(Color(UIColor.systemGray6))

                    if showReps {
                        Section("Repetitions") {
                            Stepper("Reps: \(reps)", value: $reps, in: 1...30)
                                .foregroundStyle(.white)
                        }
                        .listRowBackground(Color(UIColor.systemGray6))
                    }

                    Section("Effort") {
                        Picker("Effort", selection: $effort) {
                            Text("None").tag(Optional<EffortLevel>.none)
                            ForEach(EffortLevel.allCases, id: \.self) { e in
                                Text(e.displayName).tag(Optional<EffortLevel>.some(e))
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                    .listRowBackground(Color(UIColor.systemGray6))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { saveAndDismiss() }
                        .font(.headline).tint(.green)
                }
            }
        }
    }

    private func saveAndDismiss() {
        let seconds = Int(durationMinutes).map { $0 * 60 }
        // Convert user's unit back to miles for internal storage
        let miles: Double? = Double(distanceInput).map { unit.toMiles($0) }
        let segment = WorkoutSegment(
            id: segmentID,
            type: type,
            durationSeconds: seconds,
            distanceMiles: miles,
            reps: showReps ? reps : nil,
            restDurationSeconds: nil,
            effort: effort
        )
        onSave(segment)
        dismiss()
    }
}
