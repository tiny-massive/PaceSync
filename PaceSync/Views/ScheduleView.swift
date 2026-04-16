// PlanScheduleView.swift (file: ScheduleView.swift)
// Full week-by-week plan browser. Opened by tapping the plan card.

import SwiftUI

// MARK: - PlanScheduleView

struct PlanScheduleView: View {
    let savedPlan: SavedPlan
    @EnvironmentObject var appState: AppState

    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { proxy in
                List {
                    ForEach(savedPlan.plan.weeks.indices, id: \.self) { weekIndex in
                        let week          = savedPlan.plan.weeks[weekIndex]
                        let isCurrent     = savedPlan.currentWeekIndex == weekIndex
                        let isWeekPast    = weekIndex < (savedPlan.currentWeekIndex ?? 0)
                        let hasExplicitRaceDay = savedPlan.plan.allDays.contains(where: { $0.isRaceDay })
                        let isLastWeek         = weekIndex == savedPlan.plan.weeks.count - 1

                        Section {
                            ForEach(week) { day in
                                // Use Claude's explicit flag; fall back to last day of last week
                                // for plans parsed before isRaceDay was added.
                                let isRaceDay = day.isRaceDay ||
                                    (!hasExplicitRaceDay && isLastWeek && day.id == week.last?.id)
                                let workoutDate = savedPlan.date(forWeekIndex: weekIndex, day: day)
                                let isDayPast   = workoutDate.map {
                                    Calendar.current.startOfDay(for: $0) < today
                                } ?? false
                                let isToday     = workoutDate.map {
                                    Calendar.current.isDateInToday($0)
                                } ?? false

                                NavigationLink {
                                    WorkoutDetailView(dayID: day.id)
                                } label: {
                                    WorkoutRowView(
                                        day: day,
                                        status: appState.scheduleStatuses[day.id] ?? .unscheduled,
                                        date: workoutDate,
                                        isRaceDay: isRaceDay,
                                        isPast: isDayPast,
                                        isToday: isToday
                                    )
                                }
                                .listRowBackground(
                                    Color(UIColor.systemGray6)
                                        .opacity(isDayPast ? 0.45 : 1)
                                )
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text("Week \(weekIndex + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                                    .textCase(nil)
                                if isCurrent {
                                    Text("— Current")
                                        .font(.caption.bold())
                                        .foregroundStyle(.green)
                                        .textCase(nil)
                                } else if isWeekPast {
                                    Text("— Past")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .onAppear {
                    // Scroll to the first row of the current week
                    if let weekIndex = savedPlan.currentWeekIndex,
                       weekIndex < savedPlan.plan.weeks.count,
                       let firstDay = savedPlan.plan.weeks[weekIndex].first {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            withAnimation { proxy.scrollTo(firstDay.id, anchor: .top) }
                        }
                    }
                }
            }
        }
        .navigationTitle(savedPlan.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - WorkoutRowView

struct WorkoutRowView: View {
    let day: WorkoutDay
    let status: ScheduleStatus
    var date: Date?      = nil
    var isRaceDay: Bool  = false
    var isPast: Bool     = false
    var isToday: Bool    = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Day pill — solid green for today, muted for past, subtle for future
            VStack(spacing: 1) {
                Text(day.dayOfWeek.short)
                    .font(.caption2.bold())
                if let date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2)
                }
            }
            .frame(width: 44, height: 40)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(day.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(isPast ? Color.secondary : Color.white)
                    if isRaceDay { Text("🏁").font(.caption) }
                    if isToday {
                        Text("TODAY")
                            .font(.caption2.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                    }
                }
                Text(day.isRestDay ? "Rest" : "\(day.segments.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status badge
            statusBadge
        }
        .padding(.vertical, 4)
        .opacity(isPast ? 0.6 : 1)
    }

    private var pillBackground: Color {
        if isToday   { return .green }
        if isRaceDay { return .green.opacity(0.25) }
        return .green.opacity(0.12)
    }

    private var pillForeground: Color {
        if isToday { return .black }
        if isPast  { return .secondary }
        return .green
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .unscheduled:
            EmptyView()
        case .scheduling:
            ProgressView().tint(.green).scaleEffect(0.8)
        case .scheduled:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}
