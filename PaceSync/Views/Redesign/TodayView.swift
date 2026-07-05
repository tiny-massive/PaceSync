// TodayView.swift
// Redesigned home — the daily loop. Hero plan card (ring, race countdown, today's
// workout, week position) + empty state. Reads the real active SavedPlan.

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var appState: AppState
    var unit: DistanceUnit = .kilometers

    var body: some View {
        ScrollView {
            if let plan = appState.planStore.current {
                PlanCard(plan: plan, unit: unit)
                    .padding(.horizontal, Theme.s4)
                    .padding(.top, Theme.s2)
            } else {
                EmptyPlanState()
                    .padding(.top, 80)
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .planChrome()
    }
}

// MARK: - Hero plan card

struct PlanCard: View {
    let plan: SavedPlan
    var unit: DistanceUnit = .kilometers

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {

            // Header: title / subtitle + ring
            HStack(alignment: .top, spacing: Theme.s3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title).font(.psTitle).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.psCaption).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: Theme.s2)
                if let d = daysToRace, d >= 0 {
                    ProgressRing(fraction: ringFraction, big: "\(d)", small: "days")
                }
            }

            if let race = plan.raceDate {
                HStack(spacing: Theme.s2) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Text("Race day · \(Self.raceFormatter.string(from: race))")
                        .font(.psCallout).foregroundStyle(Theme.ink2)
                }
            }

            hairline

            VStack(alignment: .leading, spacing: Theme.s2) {
                SectionHeader(text: "Today")
                todayRow
            }

            hairline

            Text(weekLine).font(.psCallout).foregroundStyle(Theme.ink)

            hairline

            NavigationLink {
                FullPlanView(plan: plan, unit: unit)
            } label: {
                HStack {
                    Text("View full plan").font(.psHeadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private var hairline: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    @ViewBuilder private var todayRow: some View {
        if let tw = todayWorkout {
            if tw.day.isRestDay {
                Text("Rest day").font(.psBody).foregroundStyle(Theme.ink2)
            } else {
                NavigationLink {
                    RedesignWorkoutDetail(day: tw.day, unit: unit, dateText: "Today",
                                          plannedDate: Calendar.current.startOfDay(for: Date()))
                } label: {
                    HStack(spacing: 9) {
                        CategoryDot(category: tw.day.displayCategory)
                        Text(tw.day.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                        if !tw.day.shortMetric(unit: unit).isEmpty {
                            Text(tw.day.shortMetric(unit: unit)).font(.system(size: 14)).foregroundStyle(Theme.ink2)
                        }
                        Spacer(minLength: Theme.s2)
                        if tw.day.isCompleted {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.accent)
                        } else {
                            SyncChip(state: tw.day.scheduledDate != nil ? .synced : .notSynced)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink3)
                    }
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("No workout today").font(.psBody).foregroundStyle(Theme.ink3)
        }
    }

    // MARK: Derived

    private var subtitle: String {
        "\(plan.plan.weeks.count) weeks · \(plan.workoutCount) workouts"
    }

    private var weekLine: String {
        if let wi = plan.currentWeekIndex {
            return "Week \(wi + 1) of \(plan.plan.weeks.count)"
        }
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
        guard total > 0 else { return 0 }
        return Double(elapsed) / Double(total)
    }

    private var todayWorkout: (weekIndex: Int, day: WorkoutDay)? {
        let today = Calendar.current.startOfDay(for: Date())
        for (wi, days) in plan.plan.weeks.enumerated() {
            for day in days {
                if let d = plan.date(forWeekIndex: wi, day: day),
                   Calendar.current.isDate(d, inSameDayAs: today) {
                    return (wi, day)
                }
            }
        }
        return nil
    }

    private static let raceFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()
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
