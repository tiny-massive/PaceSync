// TodayView.swift
// The daily home: a today's-workout card + a progress-summary card. The full week-by-week
// browser lives behind "View full plan" / the Plans tab — Today leads with today's run.

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    var unit: DistanceUnit = .kilometers
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.s4) {
                if let plan = appState.planStore.current {
                    PlanOverviewCard(plan: plan, unit: unit)
                    TodayCard(plan: plan, unit: unit)
                    UpNextCard(plan: plan, unit: unit)
                }
                OneOffCard(unit: unit)
                if appState.planStore.current == nil && appState.planStore.standaloneWorkouts.isEmpty {
                    EmptyPlanState(onAdd: { showAdd = true }).padding(.top, 60)
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s2)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)   // centered title
        .addPlanChrome()
        .sheet(isPresented: $showAdd) { AddPlanSheet().environmentObject(appState) }
    }
}

// MARK: - Surface card chrome (shared)

private struct SurfaceCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
private extension View { func surfaceCard() -> some View { modifier(SurfaceCard()) } }

// MARK: - Top overview — race day + a 7-day week progress strip

struct PlanOverviewCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            HStack(alignment: .firstTextBaseline) {
                if let race = plan.raceDate {
                    Text("Race day · \(PlanOverviewCard.fmt.string(from: race))")
                        .font(.psCallout).foregroundStyle(Theme.ink2)
                } else {
                    Text("\(plan.plan.weeks.count)-week plan")
                        .font(.psCallout).foregroundStyle(Theme.ink2)
                }
                Spacer()
                if let d = daysToRace, d >= 0 {
                    Text("\(d) days").font(.psCallout).foregroundStyle(Theme.ink3)
                }
            }
            if let week = plan.currentWeekIndex {
                Text("Week \(week + 1) of \(plan.plan.weeks.count)")
                    .font(.psHeadline).foregroundStyle(Theme.ink)
                WeekStrip(plan: plan, weekIndex: week)
                    .padding(.top, 2)
            } else if plan.isComplete {
                Text("Plan complete").font(.psHeadline).foregroundStyle(Theme.ink)
            }
        }
        .surfaceCard()
    }

    private var daysToRace: Int? {
        guard let race = plan.raceDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today,
                                               to: Calendar.current.startOfDay(for: race)).day
    }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

// MARK: - 7-day week strip (which days you've ticked off this week; today is ringed)

struct WeekStrip: View {
    let plan: SavedPlan
    let weekIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(plan.plan.weeks[weekIndex]) { day in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(fill(day))
                        .frame(height: 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(isToday(day) ? Theme.accent : .clear, lineWidth: 1.5)
                        )
                    Text(String(day.dayOfWeek.short.prefix(1)))
                        .font(.psLabel)
                        .foregroundStyle(isToday(day) ? Theme.ink : Theme.ink3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func fill(_ day: WorkoutDay) -> Color {
        if day.isCompleted { return Theme.accent }         // ticked off
        if day.isRestDay   { return Theme.hairline }        // rest — barely there
        return Theme.ink3.opacity(0.25)                     // a workout, not done yet
    }
    private func isToday(_ day: WorkoutDay) -> Bool {
        guard let d = plan.date(forWeekIndex: weekIndex, day: day) else { return false }
        return Calendar.current.isDate(d, inSameDayAs: Date())
    }
}

// MARK: - Shared workout row — date + sync ABOVE the title, then title + distance. Tappable.

struct TodayWorkoutRow: View {
    let day: WorkoutDay
    let dateText: String
    var plannedDate: Date?
    var unit: DistanceUnit = .kilometers
    var standaloneID: UUID? = nil

    private var dist: String { day.distanceLabel(unit: unit) }
    private var syncState: SyncState { day.scheduledDate != nil ? .synced : .notSynced }

    var body: some View {
        NavigationLink {
            RedesignWorkoutDetail(day: day, unit: unit, dateText: dateText,
                                  plannedDate: plannedDate, standaloneID: standaloneID)
        } label: {
            VStack(alignment: .leading, spacing: Theme.s2) {
                header
                HStack(alignment: .top, spacing: 9) {
                    CategoryDot(category: day.displayCategory, size: 10).padding(.top, 4)
                    Text(day.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Spacer(minLength: Theme.s2)
                    if !dist.isEmpty {
                        Text(dist).font(.psCallout).foregroundStyle(Theme.ink2).psTabular().fixedSize()
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                        .padding(.top, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // date · sync/done — the sync status lives up here so you don't have to open the workout.
    private var header: some View {
        HStack(spacing: 5) {
            Text(dateText)
            Text("·")
            if day.isCompleted {
                Text("Done").foregroundStyle(Theme.accent)
            } else {
                Text(syncState.label).foregroundStyle(syncState.color)
            }
        }
        .font(.psCaption)
        .foregroundStyle(Theme.ink3)
    }
}

// MARK: - Card A — TODAY only (workout / rest / nothing). Never bleeds into "next".

struct TodayCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    private var today: (weekIndex: Int, day: WorkoutDay)? { plan.workout(on: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) { content }.surfaceCard()
    }

    @ViewBuilder private var content: some View {
        if let tw = today, !tw.day.isRestDay {
            TodayWorkoutRow(day: tw.day, dateText: "Today",
                            plannedDate: Calendar.current.startOfDay(for: Date()), unit: unit)
        } else if today?.day.isRestDay == true {
            emptyState("Rest day")
        } else {
            emptyState("Nothing scheduled today")
        }
    }

    // "Today" on top, then the state text in the SAME typeface/size as a workout title.
    private func emptyState(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text("Today").font(.psCaption).foregroundStyle(Theme.ink3)
            Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink2)
        }
    }
}

// MARK: - Card B — UP NEXT (the next 2–3 upcoming workouts)

struct UpNextCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    private var upcoming: [(day: WorkoutDay, date: Date)] { plan.upcomingWorkouts(after: Date(), limit: 3) }

    var body: some View {
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionHeader(text: "Up next")
                VStack(alignment: .leading, spacing: Theme.s3) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.day.id) { i, item in
                        TodayWorkoutRow(day: item.day,
                                        dateText: UpNextCard.fmt.string(from: item.date),
                                        plannedDate: item.date, unit: unit)
                        if i < upcoming.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                    }
                }
            }
            .surfaceCard()
        }
    }

    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

// MARK: - One-off workouts (standalone, dated individually)

struct OneOffCard: View {
    @EnvironmentObject var appState: AppState
    var unit: DistanceUnit = .kilometers

    private var workouts: [StandaloneWorkout] {
        let today = Calendar.current.startOfDay(for: Date())
        let horizon = Calendar.current.date(byAdding: .day, value: 3, to: today) ?? today
        // Home only surfaces one-offs that are imminent (today → +3 days); the rest live on Plans.
        return appState.planStore.standaloneWorkouts
            .filter { $0.date >= today && $0.date <= horizon }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionHeader(text: "One-off workouts")
                VStack(alignment: .leading, spacing: Theme.s3) {
                    ForEach(Array(workouts.enumerated()), id: \.element.id) { i, sw in
                        TodayWorkoutRow(day: sw.day,
                                        dateText: OneOffCard.fmt.string(from: sw.date),
                                        plannedDate: sw.date, unit: unit, standaloneID: sw.id)
                        if i < workouts.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                    }
                }
            }
            .surfaceCard()
        }
    }

    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

// MARK: - Plan date helpers

private extension SavedPlan {
    /// The plan day mapped to a given calendar date (rest or workout), if any.
    func workout(on date: Date) -> (weekIndex: Int, day: WorkoutDay)? {
        let target = Calendar.current.startOfDay(for: date)
        for (wi, days) in plan.weeks.enumerated() {
            for day in days {
                if let d = self.date(forWeekIndex: wi, day: day),
                   Calendar.current.isDate(d, inSameDayAs: target) { return (wi, day) }
            }
        }
        return nil
    }

    /// The next `limit` non-rest workouts strictly after `date`, in date order.
    func upcomingWorkouts(after date: Date, limit: Int) -> [(day: WorkoutDay, date: Date)] {
        let today = Calendar.current.startOfDay(for: date)
        var result: [(WorkoutDay, Date)] = []
        for (wi, days) in plan.weeks.enumerated() {
            for day in days where !day.isRestDay {
                if let d = self.date(forWeekIndex: wi, day: day), d > today { result.append((day, d)) }
            }
        }
        return result.sorted { $0.1 < $1.1 }.prefix(limit).map { (day: $0.0, date: $0.1) }
    }
}

// MARK: - Card B — progress summary

struct ProgressCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    var body: some View {
        // The WHOLE card navigates — "View full plan" stays as the visual affordance,
        // but there are no dead zones to mis-tap.
        NavigationLink {
            FullPlanView(plan: plan, unit: unit)
        } label: {
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack(alignment: .top, spacing: Theme.s3) {
                    VStack(alignment: .leading, spacing: 4) {
                        if plan.raceDate != nil {
                            Text("Race day · \(ProgressCard.fmt.string(from: plan.raceDate!))")
                                .font(.psCallout).foregroundStyle(Theme.ink2)
                        }
                        Text(weekLine).font(.psHeadline).foregroundStyle(Theme.ink)
                        Text("Done \(plan.completedCount) of \(plan.workoutCount) workouts")
                            .font(.psCallout).foregroundStyle(Theme.ink2)
                        if syncedCount > 0 {
                            Text("On Watch · \(syncedCount) of \(plan.workoutCount)")
                                .font(.psCaption).foregroundStyle(Theme.ink3)
                        }
                        if calendarCount > 0 {
                            Text("On Calendar · \(calendarCount) of \(plan.workoutCount)")
                                .font(.psCaption).foregroundStyle(Theme.ink3)
                        }
                    }
                    Spacer(minLength: Theme.s2)
                    if let d = daysToRace, d >= 0 {
                        ProgressRing(fraction: ringFraction, big: "\(d)", small: "days")
                    }
                }
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack {
                    Text("View full plan").font(.psHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .padding(Theme.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var syncedCount: Int { plan.plan.allDays.filter { $0.scheduledDate != nil }.count }
    private var calendarCount: Int { plan.plan.allDays.filter { $0.calendarEventID != nil }.count }
    private var weekLine: String {
        if let wi = plan.currentWeekIndex { return "Week \(wi + 1) of \(plan.plan.weeks.count)" }
        return "\(plan.plan.weeks.count)-week plan"
    }
    private var daysToRace: Int? {
        guard let race = plan.raceDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today,
                                               to: Calendar.current.startOfDay(for: race)).day
    }
    private var ringFraction: Double {
        guard let start = plan.planStartDate, let race = plan.raceDate else { return 0 }
        let total = Calendar.current.dateComponents([.day], from: start, to: race).day ?? 1
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return total > 0 ? Double(elapsed) / Double(total) : 0
    }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

// MARK: - Empty state

struct EmptyPlanState: View {
    var onAdd: () -> Void = {}
    var body: some View {
        VStack(spacing: Theme.s4) {
            Image(systemName: "figure.run")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(Theme.ink3)
            Text("No training plan yet").font(.psTitle).foregroundStyle(Theme.ink)
            Text("Turn your plan into dated workouts on your Apple Watch and calendar.")
                .multilineTextAlignment(.center)
                .font(.psCallout).foregroundStyle(Theme.ink2)
                .padding(.horizontal, Theme.s6)
            Button(action: onAdd) { Text("Add a training plan") }
                .buttonStyle(PSPrimaryButtonStyle())
                .padding(.horizontal, Theme.s6)
                .padding(.top, Theme.s2)
        }
        .padding(.horizontal, Theme.s4)
    }
}
