// ScheduledView.swift

import SwiftUI
import WorkoutKit

struct ScheduledView: View {
    @State private var plans: [ScheduledWorkoutPlan] = []   // ← changed type
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.green)
                } else if plans.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing Scheduled", systemImage: "applewatch")
                    } description: {
                        Text("Workouts you send to your Watch will appear here.")
                    }
                    .foregroundStyle(.white)
                } else {
                    List {
                        ForEach(plans.indices, id: \.self) { i in
                            ScheduledPlanRow(plan: plans[i].plan) {   // ← .plan
                                Task { await removePlan(plans[i]) }   // ← full ScheduledWorkoutPlan
                            }
                            .listRowBackground(Color(UIColor.systemGray6))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Scheduled")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadPlans() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.green)
                    }
                }
            }
            .task { await loadPlans() }
        }
    }

    private func loadPlans() async {
        isLoading = true
        plans = await WorkoutKitService.shared.fetchScheduled()
        isLoading = false
    }

    private func removePlan(_ scheduledPlan: ScheduledWorkoutPlan) async {   // ← changed param
        await WorkoutKitService.shared.remove(scheduledPlan)
        await loadPlans()
    }
}

// MARK: - Row (unchanged)

struct ScheduledPlanRow: View {
    let plan: WorkoutPlan
    let onRemove: () -> Void

    private var workoutName: String {
        switch plan.workout {
        case .custom(let w):  return w.displayName ?? "Workout"
        case .pacer:          return "Pacer Workout"
        case .swimBikeRun:    return "Multisport Workout"
        default:              return "Workout"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            Text(workoutName)
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            Spacer()

            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
