// SavedPlan.swift
// Persisted model wrapping a TrainingPlan with race-date metadata.

import Foundation

struct SavedPlan: Codable, Identifiable {
    let id: UUID
    var title: String
    var raceDate: Date?
    var plan: TrainingPlan
    let dateAdded: Date
    var sourceFileName: String?
    /// Raw source text cached in-memory (and persisted) so re-parse works even if the source file is missing.
    var cachedSourceText: String?

    // MARK: - Race-date derived properties

    /// The Monday of week 1, computed from the race date.
    /// Anchors correctly regardless of which day of the week the race falls on.
    var planStartDate: Date? {
        guard let raceDate else { return nil }
        // Prefer the day explicitly flagged as race day by Claude.
        // Fall back to the last day of the last week (positional guess).
        let raceDay = plan.allDays.first(where: { $0.isRaceDay })
                   ?? plan.weeks.last?.last
        guard let raceDay else { return nil }
        // Strip time so day arithmetic is always clean.
        let raceDateStart = Calendar.current.startOfDay(for: raceDate)
        // Work backwards: race day is at offset (raceWeek-1)*7 + raceDay.calendarOffset
        // from the Monday of week 1.
        let totalOffset = (raceDay.week - 1) * 7 + raceDay.dayOfWeek.calendarOffset
        return Calendar.current.date(byAdding: .day, value: -totalOffset, to: raceDateStart)
    }

    /// 0-based index of the current calendar week within the plan. Nil if no race date.
    var currentWeekIndex: Int? {
        guard let startDate = planStartDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: startDate, to: today).day ?? 0
        return max(0, min(days / 7, plan.weeks.count - 1))
    }

    /// Number of plan weeks that started before today (i.e., user is already "into" the plan).
    var skippedWeeks: Int {
        guard let start = planStartDate else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
        return max(0, days / 7)
    }

    /// Returns the calendar date for a specific workout day given its week position.
    func date(forWeekIndex weekIndex: Int, day: WorkoutDay) -> Date? {
        guard let startDate = planStartDate else { return nil }
        let offset = weekIndex * 7 + day.dayOfWeek.calendarOffset
        return Calendar.current.date(byAdding: .day, value: offset, to: startDate)
    }

    // MARK: - Summary stats

    var totalMiles: Double {
        plan.allDays.flatMap { $0.segments }.compactMap { $0.distanceMiles }.reduce(0, +)
    }

    var workoutCount: Int {
        plan.allDays.filter { !$0.segments.isEmpty }.count
    }
}
