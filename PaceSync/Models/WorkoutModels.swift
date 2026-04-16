// WorkoutModels.swift
// Core data structures shared across the app.

import Foundation

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, Codable {
    case miles, kilometers

    var shortLabel: String {
        switch self {
        case .miles:     return "mi"
        case .kilometers: return "km"
        }
    }

    var displayName: String {
        switch self {
        case .miles:     return "Miles"
        case .kilometers: return "Kilometres"
        }
    }

    /// Convert a value stored internally as miles into this unit for display.
    func convert(_ miles: Double) -> Double {
        switch self {
        case .miles:      return miles
        case .kilometers: return miles * 1.60934
        }
    }

    /// Convert a user-entered value (in this unit) back to miles for storage.
    func toMiles(_ value: Double) -> Double {
        switch self {
        case .miles:      return value
        case .kilometers: return value / 1.60934
        }
    }

    /// Format a miles value for display in this unit (e.g. "3.1 mi" or "5.0 km").
    func format(_ miles: Double, decimals: Int = 1) -> String {
        let v = convert(miles)
        return String(format: "%.\(decimals)f %@", v, shortLabel)
    }
}

// MARK: - WorkoutSegment

struct WorkoutSegment: Identifiable, Codable {
    let id: UUID
    let type: SegmentType
    var durationSeconds: Int?
    var distanceMiles: Double?
    var distanceMeters: Double?  // original meter value for track intervals (800, 400, 200)
    var reps: Int?
    var restDurationSeconds: Int?
    var effort: EffortLevel?
    var setIndex: Int?           // shared index for multi-step interval groups

    func label(unit: DistanceUnit = .miles, showReps: Bool = true) -> String {
        var parts: [String] = []
        if showReps, let r = reps, r > 1 { parts.append("\(r)x") }
        if let m = distanceMeters { parts.append("\(Int(m))m") }
        else if let d = distanceMiles { parts.append(unit.format(d)) }
        if let s = durationSeconds, s > 0 { parts.append(formatDuration(s)) }
        if let e = effort { parts.append("@ \(e.displayName)") }
        return parts.isEmpty ? type.rawValue.capitalized : parts.joined(separator: " ")
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

enum SegmentType: String, Codable, CaseIterable {
    case warmup, cooldown, easy, interval, tempo, hills, rest
}

enum EffortLevel: String, Codable, CaseIterable {
    case easy, marathon, threshold, tenK, fiveK, threeK

    var displayName: String {
        switch self {
        case .easy:      return "Easy"
        case .marathon:  return "Marathon"
        case .threshold: return "Threshold"
        case .tenK:      return "10K"
        case .fiveK:     return "5K"
        case .threeK:    return "3K"
        }
    }
}

// MARK: - WorkoutDay

struct WorkoutDay: Identifiable, Codable {
    let id: UUID
    let week: Int
    let dayOfWeek: DayOfWeek
    let title: String
    let notes: String?
    var segments: [WorkoutSegment]
    /// True when Claude explicitly identifies this as the race day.
    /// Falls back to positional detection (last day of last week) if false everywhere.
    var isRaceDay: Bool = false

    var isRestDay: Bool { segments.isEmpty }

    var summary: String {
        let types = segments.map { $0.type.rawValue }.joined(separator: ", ")
        return types.isEmpty ? "Rest" : types
    }
}

enum DayOfWeek: String, Codable, CaseIterable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var short: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        case .sunday:    return "Sun"
        }
    }

    /// Offset in days from the start of the plan week (Monday = 0).
    var calendarOffset: Int {
        switch self {
        case .monday:    return 0
        case .tuesday:   return 1
        case .wednesday: return 2
        case .thursday:  return 3
        case .friday:    return 4
        case .saturday:  return 5
        case .sunday:    return 6
        }
    }
}

// MARK: - TrainingPlan

struct TrainingPlan: Identifiable, Codable {
    let id: UUID
    let title: String
    var weeks: [[WorkoutDay]]

    var allDays: [WorkoutDay] {
        weeks.flatMap { $0 }
    }
}
