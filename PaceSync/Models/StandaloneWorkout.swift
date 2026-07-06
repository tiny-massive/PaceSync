// StandaloneWorkout.swift
// A one-off workout that isn't part of a race-anchored plan — you describe it, pick a date,
// and sync it to the Watch. Stored separately from SavedPlan (see PlanStore.standaloneWorkouts).

import Foundation

struct StandaloneWorkout: Codable, Identifiable {
    let id: UUID
    var date: Date          // start-of-day; the day it's planned for
    var day: WorkoutDay     // reuses segments / completion / scheduledDate / calendarEventID as-is
    let dateAdded: Date

    init(id: UUID = UUID(), date: Date, day: WorkoutDay, dateAdded: Date) {
        self.id = id
        self.date = date
        self.day = day
        self.dateAdded = dateAdded
    }

    var isCompleted: Bool { day.isCompleted }
}
