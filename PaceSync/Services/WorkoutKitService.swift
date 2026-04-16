// WorkoutKitService.swift
// Converts WorkoutDay into a WorkoutKit CustomWorkout and schedules it
// in the native Apple Workout app.

import Combine
import Foundation
import HealthKit
import WorkoutKit

enum ScheduleStatus: Equatable {
    case unscheduled
    case scheduling
    case scheduled
    case failed(String)

    static func == (lhs: ScheduleStatus, rhs: ScheduleStatus) -> Bool {
        switch (lhs, rhs) {
        case (.unscheduled, .unscheduled): return true
        case (.scheduling, .scheduling):   return true
        case (.scheduled, .scheduled):     return true
        case (.failed(let l), .failed(let r)): return l == r
        default: return false
        }
    }
}

@MainActor
class WorkoutKitService: ObservableObject {

    static let shared = WorkoutKitService()

    @Published var authorizationState: WorkoutScheduler.AuthorizationState = .notDetermined

    func requestAuthorization() async {
        authorizationState = await WorkoutScheduler.shared.requestAuthorization()
    }

    // MARK: - Schedule

    func schedule(_ day: WorkoutDay, on date: Date) async throws {
        let workout = try makeCustomWorkout(from: day)
        let plan = WorkoutPlan(.custom(workout))
        let components = Calendar.current.dateComponents(
            [.year, .month, .day], from: date)
        await WorkoutScheduler.shared.schedule(plan, at: components)
    }

    // MARK: - Verify

    func isScheduled(_ day: WorkoutDay) async -> Bool {
        let scheduled = await fetchScheduled()
        return scheduled.contains { scheduledPlan in
            if case .custom(let workout) = scheduledPlan.plan.workout {
                return workout.displayName == day.title
            }
            return false
        }
    }

    // MARK: - Fetch all scheduled

    func fetchScheduled() async -> [ScheduledWorkoutPlan] {
        return await WorkoutScheduler.shared.scheduledWorkouts
    }

    // MARK: - Remove

    func remove(_ scheduledPlan: ScheduledWorkoutPlan) async {
        await WorkoutScheduler.shared.remove(scheduledPlan.plan, at: scheduledPlan.date)
    }

    // MARK: - Mapping WorkoutDay → CustomWorkout

    private func makeCustomWorkout(from day: WorkoutDay) throws -> CustomWorkout {
        let warmupSeg = day.segments.first { $0.type == .warmup }
        let cooldownSeg = day.segments.first { $0.type == .cooldown }
        let workSegs = day.segments.filter { $0.type != .warmup && $0.type != .cooldown }

        let warmup = warmupSeg.map { seg in WorkoutStep(goal: goal(for: seg)) }
        let cooldown = cooldownSeg.map { seg in WorkoutStep(goal: goal(for: seg)) }

        let blocks = makeBlocks(from: workSegs)
        guard !blocks.isEmpty else { throw WorkoutKitError.noWorkSegments }

        return CustomWorkout(
            activity: .running,
            location: .outdoor,
            displayName: day.title,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    private func makeBlocks(from segments: [WorkoutSegment]) -> [IntervalBlock] {
        var blocks: [IntervalBlock] = []
        var i = 0

        print("🏗️ [makeBlocks] Starting with \(segments.count) work segments")

        while i < segments.count {
            let seg = segments[i]

            if let setIdx = seg.setIndex {
                // Collect all consecutive segments sharing this setIndex into one block.
                // This produces a single IntervalBlock with multiple steps that all
                // repeat together — e.g. "4 x 800/400/200" becomes one block of 6 steps × 4.
                var groupSegs: [WorkoutSegment] = []
                while i < segments.count && segments[i].setIndex == setIdx {
                    groupSegs.append(segments[i])
                    i += 1
                }
                let steps = groupSegs.map { s -> IntervalStep in
                    IntervalStep(s.type == .rest ? .recovery : .work, goal: goal(for: s))
                }
                let iterations = groupSegs.first(where: { $0.reps != nil })?.reps ?? 1
                blocks.append(IntervalBlock(steps: steps, iterations: iterations))
                print("🏗️ [makeBlocks] GROUPED block (setIndex=\(setIdx)): \(steps.count) steps × \(iterations) iterations")
                for (j, s) in groupSegs.enumerated() {
                    print("🏗️   step[\(j)] \(s.type.rawValue) distM=\(s.distanceMeters ?? -1) distMi=\(s.distanceMiles ?? -1)")
                }

            } else if i + 1 < segments.count
                        && segments[i + 1].type == .rest
                        && segments[i + 1].setIndex == nil {
                // Simple pair: one work step + one recovery step
                let rest     = segments[i + 1]
                let workStep = IntervalStep(.work,     goal: goal(for: seg))
                let restStep = IntervalStep(.recovery, goal: goal(for: rest))
                blocks.append(IntervalBlock(steps: [workStep, restStep], iterations: seg.reps ?? 1))
                print("🏗️ [makeBlocks] PAIR block: work(\(seg.type.rawValue)) + rest, \(seg.reps ?? 1) iterations")
                i += 2

            } else {
                // Standalone work step (no following rest, or rest already consumed)
                let workStep = IntervalStep(.work, goal: goal(for: seg))
                blocks.append(IntervalBlock(steps: [workStep], iterations: seg.reps ?? 1))
                print("🏗️ [makeBlocks] STANDALONE block: \(seg.type.rawValue), \(seg.reps ?? 1) iterations")
                i += 1
            }
        }
        print("🏗️ [makeBlocks] Final result: \(blocks.count) total blocks")
        return blocks
    }

    private func goal(for segment: WorkoutSegment) -> WorkoutGoal {
        if let meters = segment.distanceMeters {
            return .distance(meters, .meters)
        } else if let miles = segment.distanceMiles {
            return .distance(miles, .miles)
        } else if let seconds = segment.durationSeconds {
            return .time(Double(seconds), .seconds)
        } else {
            return .open
        }
    }
}

enum WorkoutKitError: LocalizedError {
    case validationFailed(String)
    case noWorkSegments

    var errorDescription: String? {
        switch self {
        case .validationFailed(let msg): return "Validation failed: \(msg)"
        case .noWorkSegments:            return "No schedulable segments found in this workout."
        }
    }
}
