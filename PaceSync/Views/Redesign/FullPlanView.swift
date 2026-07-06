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
                case .calendar: PlanCalendarView(plan: p, unit: unit)
                }
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(p.title)
        .navigationBarTitleDisplayMode(.inline)
        .planSettingsChrome()   // rename / change race day / re-import / remove (this plan)
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

// MARK: - Calendar (month grid)

private struct DayRef { let week: Int; let day: WorkoutDay }

struct PlanCalendarView: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers
    private let dayMap: [Date: DayRef]

    init(plan: SavedPlan, unit: DistanceUnit = .kilometers) {
        self.plan = plan
        self.unit = unit
        var m: [Date: DayRef] = [:]
        for (wi, days) in plan.plan.weeks.enumerated() {
            for day in days where !day.isRestDay {
                if let d = plan.date(forWeekIndex: wi, day: day) {
                    m[Calendar.current.startOfDay(for: d)] = DayRef(week: wi, day: day)
                }
            }
        }
        self.dayMap = m
    }

    private var months: [Date] {
        var cal = Calendar.current; cal.firstWeekday = 2
        guard let start = plan.planStartDate else { return [] }
        let end = plan.raceDate ?? start
        let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: end)) ?? end
        var result: [Date] = []
        var cursor = startMonth
        while cursor <= endMonth && result.count < 24 {
            result.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    var body: some View {
        if months.isEmpty {
            Text("Set a race day to see the calendar.")
                .font(.psCallout).foregroundStyle(Theme.ink3)
                .frame(maxWidth: .infinity).padding(.top, 80)
        } else {
            LazyVStack(alignment: .leading, spacing: Theme.s4) {
                ForEach(months, id: \.self) { month in
                    MonthGrid(month: month, dayMap: dayMap, unit: unit)
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s3)
            .padding(.bottom, Theme.s6)
        }
    }
}

private struct MonthGrid: View {
    let month: Date            // any date within the month
    let dayMap: [Date: DayRef]
    var unit: DistanceUnit = .kilometers

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(MonthGrid.monthFmt.string(from: month))
                .font(.psHeadline).foregroundStyle(Theme.ink)
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.psLabel).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity)
                }
            }
            let cells = makeCells()
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(cells[row * 7 + col])
                    }
                }
            }
        }
        .padding(Theme.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private func cell(_ date: Date?) -> some View {
        if let date, let ref = dayMap[cal.startOfDay(for: date)] {
            NavigationLink {
                RedesignWorkoutDetail(day: ref.day, unit: unit,
                                      dateText: MonthGrid.dayFmt.string(from: date), plannedDate: date)
            } label: { dayContent(date, ref: ref) }
            .buttonStyle(.plain)
        } else {
            dayContent(date, ref: nil)
        }
    }

    private func dayContent(_ date: Date?, ref: DayRef?) -> some View {
        let isToday = date.map { cal.isDateInToday($0) } ?? false
        return VStack(spacing: 3) {
            Text(date.map { "\(cal.component(.day, from: $0))" } ?? " ")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Theme.accent : (ref != nil ? Theme.ink : Theme.ink3))
            Circle()
                .fill(ref == nil ? Color.clear : (ref!.day.isCompleted ? Theme.accent : Theme.ink3))
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .contentShape(Rectangle())
    }

    // Leading Monday-based blanks + each day of the month, padded to full weeks.
    private func makeCells() -> [Date?] {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let weekday = cal.component(.weekday, from: first)         // 1=Sun … 7=Sat
        let leading = (weekday - cal.firstWeekday + 7) % 7         // Monday-based offset
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for dayNum in range {
            if let d = cal.date(byAdding: .day, value: dayNum - 1, to: first) { cells.append(d) }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    static let monthFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f }()
    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}
