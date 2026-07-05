// FullPlanView.swift
// Redesigned week-by-week plan view with a List ⇄ Calendar toggle.
// List rows use the agreed pattern: "Wed 10 | Synced to Watch" header line,
// dot + title + metric, trailing completion checkbox. Wired to real SavedPlan data.

import SwiftUI

struct FullPlanView: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    enum Mode: String, CaseIterable { case list = "List", calendar = "Calendar" }
    @State private var mode: Mode = .list

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
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: List

    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: Theme.s5) {
            ForEach(Array(plan.plan.weeks.enumerated()), id: \.offset) { weekIndex, days in
                VStack(alignment: .leading, spacing: 9) {
                    SectionHeader(text: weekLabel(weekIndex))
                        .padding(.horizontal, Theme.s4)

                    PSCard(padded: false) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { i, day in
                            if day.isRestDay {
                                WorkoutRow(day: day, dateLabel: dateLabel(weekIndex, day),
                                           unit: unit, syncState: .synced)
                            } else {
                                NavigationLink {
                                    RedesignWorkoutDetail(day: day, unit: unit,
                                                          dateText: dateLabel(weekIndex, day))
                                } label: {
                                    WorkoutRow(day: day, dateLabel: dateLabel(weekIndex, day),
                                               unit: unit, syncState: .synced)
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
        plan.currentWeekIndex == i ? "Week \(i + 1) · This week" : "Week \(i + 1)"
    }

    private func dateLabel(_ weekIndex: Int, _ day: WorkoutDay) -> String {
        if let d = plan.date(forWeekIndex: weekIndex, day: day) {
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
