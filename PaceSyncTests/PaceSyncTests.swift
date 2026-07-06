// PaceSyncTests.swift
// Unit coverage for the date math and formatting logic that drives scheduling.
// These are the highest-risk pure functions: a wrong day offset misplaces every
// workout on the Watch and Calendar.

import XCTest
@testable import PaceSync

@MainActor
final class PaceSyncTests: XCTestCase {

    private let cal = Calendar.current

    // MARK: - Fixtures

    /// A plan of `weeks` weeks, one flagged race day (default Sunday) in the final week.
    private func makePlan(weeks: Int, raceDay: DayOfWeek = .sunday) -> TrainingPlan {
        var wk: [[WorkoutDay]] = []
        for w in 1...weeks {
            let isLast = (w == weeks)
            let day = WorkoutDay(id: UUID(), week: w, dayOfWeek: raceDay, title: "Long run",
                                 notes: nil,
                                 segments: [WorkoutSegment(id: UUID(), type: .easy,
                                                           durationSeconds: nil, distanceMiles: 10,
                                                           distanceMeters: nil, reps: nil,
                                                           restDurationSeconds: nil, effort: .easy,
                                                           setIndex: nil)],
                                 isRaceDay: isLast)
            wk.append([day])
        }
        return TrainingPlan(id: UUID(), title: "Test Plan", weeks: wk)
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? .min
    }

    // MARK: - planStartDate

    func testPlanStartDateAnchorsToMondayOfWeekOne() throws {
        // Race in week 4 on Sunday → start is 3 full weeks + 6 days earlier = 27 days back.
        let race = cal.date(byAdding: .day, value: 40, to: Date())!
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: makePlan(weeks: 4),
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        let start = try XCTUnwrap(saved.planStartDate)
        XCTAssertEqual(daysBetween(start, cal.startOfDay(for: race)), 27,
                       "4-week plan, Sunday race → start is 27 days before race day")
    }

    func testPlanStartDateNilWithoutRaceDate() {
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: nil, plan: makePlan(weeks: 4),
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        XCTAssertNil(saved.planStartDate)
        XCTAssertNil(saved.currentWeekIndex)
        XCTAssertFalse(saved.isComplete)
    }

    // MARK: - date(forWeekIndex:day:)

    func testDateForRaceWeekEqualsRaceDay() throws {
        let race = cal.date(byAdding: .day, value: 40, to: Date())!
        let plan = makePlan(weeks: 4)
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: plan,
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        let raceDayObj = plan.weeks.last!.last!
        let computed = try XCTUnwrap(saved.date(forWeekIndex: 3, day: raceDayObj))
        XCTAssertEqual(daysBetween(computed, cal.startOfDay(for: race)), 0,
                       "date(forWeekIndex: last, raceDay) should land exactly on race day")
    }

    func testDateForWeekIndexAdvancesBySevenDays() throws {
        let race = cal.date(byAdding: .day, value: 40, to: Date())!
        let plan = makePlan(weeks: 4)
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: plan,
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        let day = plan.weeks.first!.first!
        let w0 = try XCTUnwrap(saved.date(forWeekIndex: 0, day: day))
        let w1 = try XCTUnwrap(saved.date(forWeekIndex: 1, day: day))
        XCTAssertEqual(daysBetween(w0, w1), 7, "same weekday one week later is 7 days apart")
    }

    // MARK: - currentWeekIndex / isComplete boundaries

    func testCurrentWeekIndexZeroBeforePlanStarts() {
        // Race far in the future → plan hasn't started → clamp to week 0, not complete.
        let race = cal.date(byAdding: .day, value: 90, to: Date())!
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: makePlan(weeks: 2),
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        XCTAssertEqual(saved.currentWeekIndex, 0)
        XCTAssertFalse(saved.isComplete)
    }

    func testCurrentWeekIndexNilAndCompleteAfterFinalWeek() {
        // Race well in the past → past the final week → nil + complete.
        let race = cal.date(byAdding: .day, value: -60, to: Date())!
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: makePlan(weeks: 2),
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        XCTAssertNil(saved.currentWeekIndex)
        XCTAssertTrue(saved.isComplete)
    }

    func testCurrentWeekIndexInFirstWeekWhenStartIsToday() {
        // Choose a race date so planStartDate == today: offset = (weeks-1)*7 + Sunday(6).
        let weeks = 3
        let offset = (weeks - 1) * 7 + DayOfWeek.sunday.calendarOffset  // 20
        let race = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: race, plan: makePlan(weeks: weeks),
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        XCTAssertEqual(saved.currentWeekIndex, 0)
        XCTAssertFalse(saved.isComplete)
        XCTAssertEqual(saved.skippedWeeks, 0)
    }

    // MARK: - DayOfWeek offsets

    func testDayOfWeekCalendarOffsets() {
        XCTAssertEqual(DayOfWeek.monday.calendarOffset, 0)
        XCTAssertEqual(DayOfWeek.sunday.calendarOffset, 6)
        // Every case is contiguous 0...6, Monday-first.
        let offsets = DayOfWeek.allCases.map { $0.calendarOffset }
        XCTAssertEqual(offsets, Array(0...6))
    }

    // MARK: - DistanceUnit conversion / formatting

    func testDistanceUnitConversionRoundTrip() {
        let km = DistanceUnit.kilometers
        let miles = 6.2137
        let asKm = km.convert(miles)
        XCTAssertEqual(asKm, 10.0, accuracy: 0.01)
        XCTAssertEqual(km.toMiles(asKm), miles, accuracy: 0.0001)
    }

    func testDistanceUnitFormatDropsTrailingZero() {
        XCTAssertEqual(DistanceUnit.miles.format(5.0), "5 mi")
        XCTAssertEqual(DistanceUnit.miles.format(3.1), "3.1 mi")
    }

    // MARK: - WorkoutSegment label

    func testSegmentLabelWithRepsAndMeters() {
        let seg = WorkoutSegment(id: UUID(), type: .interval, durationSeconds: nil,
                                 distanceMiles: nil, distanceMeters: 800, reps: 4,
                                 restDurationSeconds: 90, effort: .fiveK, setIndex: nil)
        let label = seg.label(unit: .miles)
        XCTAssertTrue(label.contains("4x"), "reps prefix")
        XCTAssertTrue(label.contains("800m"), "meter distance")
    }

    // MARK: - Summary stats

    func testTotalMilesAndWorkoutCount() {
        let plan = makePlan(weeks: 3)   // 3 days, each 10 miles easy
        let saved = SavedPlan(id: UUID(), title: "T", raceDate: nil, plan: plan,
                              dateAdded: Date(), sourceFileName: nil, cachedSourceText: nil)
        XCTAssertEqual(saved.totalMiles, 30, accuracy: 0.001)
        XCTAssertEqual(saved.workoutCount, 3)
        XCTAssertEqual(saved.completedCount, 0)
    }
}
