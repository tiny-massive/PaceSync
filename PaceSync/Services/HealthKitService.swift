// HealthKitService.swift
// Reads completed running/walking workouts from HealthKit so finished runs can be
// auto-matched to planned workouts. Read-only; manual completion always wins.

import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Ask for read access to workouts. Safe to call repeatedly.
    func requestReadAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            print("⚠️ [HealthKit] authorization failed: \(error)")
            return false
        }
    }

    /// Completed running/walking workouts recorded on or after `since`.
    func completedRuns(since: Date) async -> [HKWorkout] {
        guard isAvailable else { return [] }
        let datePredicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let runs = (samples as? [HKWorkout])?.filter {
                    $0.workoutActivityType == .running || $0.workoutActivityType == .walking
                } ?? []
                cont.resume(returning: runs)
            }
            store.execute(query)
        }
    }
}
