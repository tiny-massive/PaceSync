// WorkoutDetailView.swift
// Workout day detail — segments, scheduling, and edit access.

import SwiftUI

// MARK: - Segment Display Item (groups segments by setIndex)

enum SegmentDisplayItem: Identifiable {
    case single(WorkoutSegment)
    case repeatGroup(id: Int, iterations: Int, segments: [WorkoutSegment])

    var id: String {
        switch self {
        case .single(let seg): return seg.id.uuidString
        case .repeatGroup(let idx, _, _): return "group-\(idx)"
        }
    }
}

func groupedSegmentItems(from segments: [WorkoutSegment]) -> [SegmentDisplayItem] {
    var items: [SegmentDisplayItem] = []
    var nextGroupID = 100  // avoid colliding with setIndex values
    var i = 0
    while i < segments.count {
        let seg = segments[i]

        if let setIdx = seg.setIndex {
            // Complex set: all consecutive segments sharing this setIndex
            var group: [WorkoutSegment] = []
            while i < segments.count && segments[i].setIndex == setIdx {
                group.append(segments[i])
                i += 1
            }
            let iterations = group.first(where: { $0.reps != nil })?.reps ?? 1
            items.append(.repeatGroup(id: setIdx, iterations: iterations, segments: group))

        } else if let reps = seg.reps, reps > 1,
                  seg.setIndex == nil,
                  i + 1 < segments.count,
                  segments[i + 1].type == .rest,
                  segments[i + 1].setIndex == nil {
            // Simple pair with reps: work + rest → wrap in repeat group
            let rest = segments[i + 1]
            items.append(.repeatGroup(id: nextGroupID, iterations: reps, segments: [seg, rest]))
            nextGroupID += 1
            i += 2

        } else {
            items.append(.single(seg))
            i += 1
        }
    }
    return items
}

struct WorkoutDetailView: View {
    let dayID: UUID
    @EnvironmentObject var appState: AppState
    @State private var selectedDate = Date()

    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.miles.rawValue
    private var unit: DistanceUnit { DistanceUnit(rawValue: distanceUnitRaw) ?? .miles }

    private var day: WorkoutDay? {
        appState.planStore.current?.plan.allDays.first { $0.id == dayID }
    }

    private var status: ScheduleStatus {
        appState.scheduleStatuses[dayID] ?? .unscheduled
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let day {
                ScrollView {
                    VStack(spacing: 20) {

                        // Header card — left-aligned with metadata
                        VStack(alignment: .leading, spacing: 6) {
                            Text(day.dayOfWeek.short.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                            Text(day.title)
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                            if let notes = day.notes {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 4)

                            if let dateAdded = appState.planStore.current?.dateAdded {
                                Text("Added \(dateAdded, format: .dateTime.month(.abbreviated).day().year())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let scheduledDate = appState.scheduledDates[dayID] {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar.badge.clock")
                                        .font(.caption2)
                                    Text("Scheduled for \(scheduledDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(14)

                        // Schedule section — at the top (skip for rest days)
                        if !day.segments.isEmpty {
                            VStack(spacing: 12) {
                                Text("SEND TO WATCH")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)

                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(.green)
                                    DatePicker("", selection: $selectedDate,
                                               in: Date()..., displayedComponents: [.date])
                                        .datePickerStyle(.compact)
                                        .tint(.green)
                                        .labelsHidden()
                                    Spacer()
                                }
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(12)

                                scheduleButton(day: day)
                                statusMessage
                            }
                        }

                        // Segments
                        if day.segments.isEmpty {
                            Text("Rest Day")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(14)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SEGMENTS")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                ForEach(groupedSegmentItems(from: day.segments)) { item in
                                    switch item {
                                    case .single(let segment):
                                        SegmentRowView(segment: segment, unit: unit)
                                    case .repeatGroup(_, let iterations, let segments):
                                        RepeatGroupView(iterations: iterations,
                                                        segments: segments, unit: unit)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Workout Not Found", systemImage: "questionmark.circle")
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Week \(day?.week ?? 0)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if day != nil {
                    NavigationLink {
                        EditWorkoutView(dayID: dayID)
                    } label: {
                        Text("Edit")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Schedule Button

    @ViewBuilder
    private func scheduleButton(day: WorkoutDay) -> some View {
        switch status {
        case .unscheduled, .failed:
            Button {
                Task { await appState.scheduleWorkout(day, on: selectedDate) }
            } label: {
                Label("Send to Watch", systemImage: "applewatch")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.black)
                    .cornerRadius(14)
            }

        case .scheduling:
            HStack(spacing: 10) {
                ProgressView().tint(.green)
                Text("Scheduling…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(14)

        case .scheduled:
            Button {
                Task { await appState.scheduleWorkout(day, on: selectedDate) }
            } label: {
                Label("Reschedule", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Status Message

    @ViewBuilder
    private var statusMessage: some View {
        switch status {
        case .scheduled:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Confirmed in Workout app")
                    .font(.subheadline).foregroundStyle(.green)
            }

        case .failed(let msg):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync may have failed")
                        .font(.subheadline).foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

        default:
            EmptyView()
        }
    }
}

// MARK: - Segment Row

struct SegmentRowView: View {
    let segment: WorkoutSegment
    var unit: DistanceUnit = .miles

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(segmentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(segment.type.rawValue.capitalized)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(segment.label(unit: unit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let effort = segment.effort {
                Text(effort.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(segmentColor.opacity(0.2))
                    .foregroundStyle(segmentColor)
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
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

// MARK: - Repeat Group (visual container for setIndex-grouped intervals)

struct RepeatGroupView: View {
    let iterations: Int
    let segments: [WorkoutSegment]
    var unit: DistanceUnit = .miles

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — mimics Apple's "Repeat ↻ 4"
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("Repeat × \(iterations)")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Grouped segment rows
            VStack(spacing: 6) {
                ForEach(segments) { segment in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colorFor(segment))
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.type.rawValue.capitalized)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                            Text(segment.label(unit: unit, showReps: false))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let effort = segment.effort {
                            Text(effort.displayName)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(colorFor(segment).opacity(0.2))
                                .foregroundStyle(colorFor(segment))
                                .cornerRadius(5)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
            .padding(.bottom, 12)
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func colorFor(_ segment: WorkoutSegment) -> Color {
        switch segment.type {
        case .warmup, .cooldown: return .blue
        case .easy:              return .green
        case .interval, .tempo:  return .orange
        case .hills:             return .yellow
        case .rest:              return .gray
        }
    }
}
