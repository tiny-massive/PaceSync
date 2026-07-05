// FullPlanView.swift
// Week-by-week plan view with a List ⇄ Calendar toggle. Rows reflect real completion
// and Watch-sync state, tap through to the workout detail with the real scheduling date.

import SwiftUI

struct FullPlanView: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    @EnvironmentObject var appState: AppState
    enum Mode: String, CaseIterable { case list = "List", calendar = "Calendar" }
    @State private var mode: Mode = .list

    /// Live plan from the store so edits/completion/sync reflect immediately.
    private var p: SavedPlan { appState.planStore.current ?? plan }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.s4)
            .padding(.vertical, Theme.s2)

            ScrollView {
                switch mode {
                case .list:     listContent
                case .calendar: calendarPlaceholder
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(p.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: List

    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: Theme.s5) {
            ForEach(Array(p.plan.weeks.enumerated()), id: \.offset) { weekIndex, days in
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(text: weekLabel(weekIndex))
                        .padding(.horizontal, Theme.s4)

                    PSCard(padded: false) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                            if day.isRestDay {
                                WorkoutRow(day: day, dateLabel: dateLabel(weekIndex, day),
                                           unit: unit, syncState: .notSynced)
                            } else {
                                NavigationLink {
                                    RedesignWorkoutDetail(
                                        day: day, unit: unit,
                                        dateText: dateLabel(weekIndex, day),
                                        plannedDate: p.date(forWeekIndex: weekIndex, day: day)
                                    )
                                } label: {
                                    WorkoutRow(
                                        day: day, dateLabel: dateLabel(weekIndex, day),
                                        unit: unit,
                                        syncState: day.scheduledDate != nil ? .synced : .notSynced,
                                        isDone: day.isCompleted
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            if i < days.count - 1 {
                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, Theme.s4)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.s4)
                }
            }
        }
        .padding(.top, Theme.s3)
        .padding(.bottom, Theme.s6)
    }

    private var calendarPlaceholder: some View {
        Text("Calendar view — coming next")
            .font(.psCallout)
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    // MARK: Helpers

    private func weekLabel(_ i: Int) -> String {
        p.currentWeekIndex == i ? "Week \(i + 1) · This week" : "Week \(i + 1)"
    }

    private func dateLabel(_ weekIndex: Int, _ day: WorkoutDay) -> String {
        if let d = p.date(forWeekIndex: weekIndex, day: day) {
            return FullPlanView.dayFormatter.string(from: d)
        }
        return day.dayOfWeek.short
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f
    }()
}
