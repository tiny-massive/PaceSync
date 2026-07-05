// RedesignWorkoutDetail.swift
// Workout detail — parsed segments + the coach's original text (upsized), plus the
// REAL actions reconnected: Sync to Watch (WorkoutKit), persisted Mark-done, Edit.

import SwiftUI

struct RedesignWorkoutDetail: View {
    let day: WorkoutDay
    var unit: DistanceUnit = .kilometers
    var dateText: String = ""
    /// The workout's real calendar date, used when scheduling to Watch.
    var plannedDate: Date? = nil

    @EnvironmentObject var appState: AppState
    @State private var showEdit = false

    /// Live copy from the store so completion/schedule reflect writes immediately.
    private var liveDay: WorkoutDay {
        appState.planStore.current?.plan.allDays.first { $0.id == day.id } ?? day
    }
    private var status: ScheduleStatus? { appState.scheduleStatuses[day.id] }
    private var isOnWatch: Bool {
        if case .scheduled? = status { return true }
        return liveDay.scheduledDate != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                headerCard
                if !day.isRestDay { syncCard }
                if !day.segments.isEmpty { sessionCard }
                if let notes = day.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    fromPlanCard(notes)
                }
                if !day.isRestDay {
                    Button { showEdit = true } label: {
                        Label("Edit workout", systemImage: "pencil")
                    }
                    .buttonStyle(PSSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s3)
            .padding(.bottom, Theme.s6)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(day.isRestDay ? "Rest day" : day.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            NavigationStack { EditWorkoutView(dayID: day.id) }
                .environmentObject(appState)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        PSCard {
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack(spacing: 9) {
                    if !day.isRestDay { CategoryDot(category: day.displayCategory, size: 11) }
                    Text(day.isRestDay ? "Rest day" : day.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !day.isRestDay {
                        Button { toggleDone() } label: {
                            HStack(spacing: 7) {
                                CompletionCheckbox(isDone: liveDay.isCompleted)
                                Text(liveDay.isCompleted ? "Done" : "Mark done")
                                    .font(.psCaption).foregroundStyle(Theme.ink2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.psCallout).foregroundStyle(Theme.ink2)
                }
                if let c = liveDay.completion, c.isDone {
                    Text(c.source == .auto ? "Auto-detected from your Apple Watch" : "Marked done")
                        .font(.psCaption).foregroundStyle(Theme.ink3)
                }
            }
        }
    }

    // MARK: Apple Watch sync (the real action)

    private var syncCard: some View {
        PSCard {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionHeader(text: "Apple Watch")
                if isOnWatch {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        Text("Synced to Watch").font(.psBody).foregroundStyle(Theme.ink)
                    }
                } else if case .scheduling? = status {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Scheduling…").font(.psBody).foregroundStyle(Theme.ink2)
                    }
                } else if case .failed(let msg)? = status {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        Text(msg).font(.psCallout).foregroundStyle(Theme.error)
                        Button("Retry") { sync() }.buttonStyle(PSSecondaryButtonStyle())
                    }
                } else {
                    Button("Sync to Watch") { sync() }.buttonStyle(PSPrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: Session (parsed segments)

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(text: "The session")
            PSCard(padded: false) {
                ForEach(Array(day.segments.enumerated()), id: \.element.id) { i, seg in
                    HStack {
                        Text(segmentName(seg.type))
                            .font(.psHeadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(seg.label(unit: unit))
                            .font(.psCallout).foregroundStyle(Theme.ink2)
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.vertical, Theme.s3)
                    if i < day.segments.count - 1 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                            .padding(.leading, Theme.s4)
                    }
                }
            }
        }
    }

    // MARK: From your plan (verbatim, upsized)

    private func fromPlanCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(text: "From your plan")
            PSCard {
                Text(notes)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private func toggleDone() {
        if liveDay.isCompleted {
            appState.planStore.setCompletion(dayID: day.id, nil)
        } else {
            appState.planStore.setCompletion(dayID: day.id,
                                             WorkoutCompletion(isDone: true, source: .manual))
        }
    }

    private func sync() {
        Task { await appState.scheduleWorkout(day, on: plannedDate ?? Date()) }
    }

    // MARK: Helpers

    private var subtitle: String {
        var parts: [String] = []
        if !dateText.isEmpty { parts.append(dateText) }
        let miles = day.segments.compactMap { $0.distanceMiles }.reduce(0, +)
        if miles > 0 { parts.append(unit.format(miles)) }
        return parts.joined(separator: " · ")
    }

    private func segmentName(_ t: SegmentType) -> String {
        switch t {
        case .warmup:   return "Warm-up"
        case .cooldown: return "Cool-down"
        case .easy:     return "Easy"
        case .interval: return "Intervals"
        case .tempo:    return "Tempo"
        case .hills:    return "Hills"
        case .rest:     return "Rest"
        }
    }
}
