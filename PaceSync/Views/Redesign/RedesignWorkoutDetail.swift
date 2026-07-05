// RedesignWorkoutDetail.swift
// The workout detail — parsed segments + the coach's original text (upsized, verbatim)
// + sync status + mark-done. Reached by tapping any workout row or today's workout.

import SwiftUI

struct RedesignWorkoutDetail: View {
    let day: WorkoutDay
    var unit: DistanceUnit = .kilometers
    var dateText: String = ""

    @State private var isDone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s5) {
                headerCard
                if !day.segments.isEmpty { sessionCard }
                if let notes = day.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    fromPlanCard(notes)
                }
            }
            .padding(.horizontal, Theme.s4)
            .padding(.top, Theme.s3)
            .padding(.bottom, Theme.s6)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(day.isRestDay ? "Rest day" : day.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var headerCard: some View {
        PSCard {
            VStack(alignment: .leading, spacing: Theme.s3) {
                HStack(spacing: 9) {
                    if !day.isRestDay { CategoryDot(category: day.displayCategory, size: 11) }
                    Text(day.isRestDay ? "Rest day" : day.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button { isDone.toggle() } label: {
                        HStack(spacing: 7) {
                            CompletionCheckbox(isDone: isDone)
                            Text(isDone ? "Done" : "Mark done")
                                .font(.psCaption).foregroundStyle(Theme.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !subtitle.isEmpty {
                    Text(subtitle).font(.psCallout).foregroundStyle(Theme.ink2)
                }

                if !day.isRestDay {
                    HStack(spacing: 8) {
                        SyncChip(state: .synced)
                        Text("· Also on Calendar")
                            .font(.psCaption).foregroundStyle(Theme.ink3)
                    }
                }
            }
        }
    }

    // MARK: Session (parsed segments)

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(text: "The session")
            PSCard(padded: false) {
                ForEach(Array(day.segments.enumerated()), id: \.element.id) { i, seg in
                    HStack {
                        Text(segmentName(seg.type))
                            .font(.psHeadline).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(seg.label(unit: unit))
                            .font(.psCallout).foregroundStyle(Theme.ink2)
                    }
                    .padding(.horizontal, Theme.s4)
                    .padding(.vertical, Theme.s3)
                    if i < day.segments.count - 1 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                            .padding(.leading, Theme.s4)
                    }
                }
            }
        }
    }

    // MARK: From your plan (verbatim, upsized)

    private func fromPlanCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(text: "From your plan")
            PSCard {
                Text(notes)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Helpers

    private var subtitle: String {
        var parts: [String] = []
        if !dateText.isEmpty { parts.append(dateText) }
        let miles = day.segments.compactMap { $0.distanceMiles }.reduce(0, +)
        if miles > 0 { parts.append(unit.format(miles)) }
        return parts.joined(separator: " · ")
    }

    private func segmentName(_ t: SegmentType) -> String {
        switch t {
        case .warmup:   return "Warm-up"
        case .cooldown: return "Cool-down"
        case .easy:     return "Easy"
        case .interval: return "Intervals"
        case .tempo:    return "Tempo"
        case .hills:    return "Hills"
        case .rest:     return "Rest"
        }
    }
}
