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
            if let plan = appState.planStore.current {
                VStack(spacing: Theme.s4) {
                    TodayWorkoutCard(plan: plan, unit: unit)
                    ProgressCard(plan: plan, unit: unit)
                }
                .padding(.horizontal, Theme.s4)
                .padding(.top, Theme.s2)
            } else {
                EmptyPlanState(onAdd: { showAdd = true }).padding(.top, 80)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .planChrome()
        .sheet(isPresented: $showAdd) { AddPlanSheet().environmentObject(appState) }
    }
}

// MARK: - Card A — today's workout

struct TodayWorkoutCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            SectionHeader(text: "Today")
            content
        }
        .padding(Theme.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private var content: some View {
        if let tw = todayWorkout, !tw.day.isRestDay {
            NavigationLink {
                RedesignWorkoutDetail(day: tw.day, unit: unit, dateText: "Today",
                                      plannedDate: Calendar.current.startOfDay(for: Date()))
            } label: { row(tw.day) }
            .buttonStyle(.plain)
        } else if todayWorkout?.day.isRestDay == true {
            HStack {
                Text("Rest day").font(.psBody).foregroundStyle(Theme.ink2)
                Spacer()
                if let n = nextWorkout {
                    Text("Next · \(n.label)").font(.psCallout).foregroundStyle(Theme.ink3)
                }
            }
        } else if let n = nextWorkout {
            NavigationLink {
                RedesignWorkoutDetail(day: n.day, unit: unit, dateText: n.label, plannedDate: n.date)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing scheduled today").font(.psCallout).foregroundStyle(Theme.ink3)
                    row(n.day, dateOverride: "Next · \(n.label)")
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("No workouts scheduled").font(.psBody).foregroundStyle(Theme.ink3)
        }
    }

    private func row(_ day: WorkoutDay, dateOverride: String? = nil) -> some View {
        HStack(spacing: 9) {
            CategoryDot(category: day.displayCategory, size: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                if let o = dateOverride {
                    Text(o).font(.psCaption).foregroundStyle(Theme.ink3)
                } else if !day.shortMetric(unit: unit).isEmpty {
                    Text(day.shortMetric(unit: unit)).font(.psCallout).foregroundStyle(Theme.ink2)
                }
            }
            Spacer(minLength: Theme.s2)
            if day.isCompleted {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.accent)
            } else {
                SyncChip(state: day.scheduledDate != nil ? .synced : .notSynced)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
        }
    }

    private var todayWorkout: (weekIndex: Int, day: WorkoutDay)? {
        let today = Calendar.current.startOfDay(for: Date())
        for (wi, days) in plan.plan.weeks.enumerated() {
            for day in days {
                if let d = plan.date(forWeekIndex: wi, day: day),
                   Calendar.current.isDate(d, inSameDayAs: today) { return (wi, day) }
            }
        }
        return nil
    }

    private var nextWorkout: (day: WorkoutDay, date: Date, label: String)? {
        let today = Calendar.current.startOfDay(for: Date())
        var best: (WorkoutDay, Date)?
        for (wi, days) in plan.plan.weeks.enumerated() {
            for day in days where !day.isRestDay {
                if let d = plan.date(forWeekIndex: wi, day: day), d >= today,
                   best == nil || d < best!.1 { best = (day, d) }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, TodayWorkoutCard.dayFmt.string(from: b.1))
    }

    static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f }()
}

// MARK: - Card B — progress summary

struct ProgressCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    var body: some View {
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
                }
                Spacer(minLength: Theme.s2)
                if let d = daysToRace, d >= 0 {
                    ProgressRing(fraction: ringFraction, big: "\(d)", small: "days")
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            NavigationLink {
                FullPlanView(plan: plan, unit: unit)
            } label: {
                HStack {
                    Text("View full plan").font(.psHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var syncedCount: Int { plan.plan.allDays.filter { $0.scheduledDate != nil }.count }
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
