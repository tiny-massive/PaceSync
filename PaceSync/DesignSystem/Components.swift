// Components.swift
// Reusable PaceSync UI atoms built on Theme. Ported from the Figma component sheet,
// with the agreed tweaks: completion is a trailing checkbox (not a leading tick),
// sync reads "Synced to Watch", chips are reduced to quiet text.

import SwiftUI

// MARK: - Sync state

enum SyncState: Equatable {
    case synced, notSynced, failed

    var label: String {
        switch self {
        case .synced:    return "Synced to Watch"
        case .notSynced: return "Not synced"
        case .failed:    return "Failed — retry"
        }
    }
    var color: Color { self == .failed ? Theme.error : Theme.ink3 }
}

// MARK: - Category dot

struct CategoryDot: View {
    let category: Theme.Category
    var size: CGFloat = 9
    var body: some View { Circle().fill(category.color).frame(width: size, height: size) }
}

// MARK: - Completion checkbox (trailing) — native centred checkmark, no alignment hacks

struct CompletionCheckbox: View {
    let isDone: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isDone ? Theme.accent : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isDone ? .clear : Theme.ink3.opacity(0.55), lineWidth: 1.5)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .opacity(isDone ? 1 : 0)
            )
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }
}

// MARK: - Reduced sync chip (for the Today card / detail; the list uses a header line)

struct SyncChip: View {
    let state: SyncState
    var body: some View {
        Text(state.label)
            .font(.psCaption)
            .foregroundStyle(state.color)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.psLabel)
            .tracking(0.7)
            .foregroundStyle(Theme.ink2)
    }
}

// MARK: - Card

struct PSCard<Content: View>: View {
    var padded: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padded ? Theme.s4 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Progress ring (days-to-race)

struct ProgressRing: View {
    var fraction: Double
    var big: String
    var small: String
    var size: CGFloat = 58

    var body: some View {
        ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text(big).font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundStyle(Theme.ink).psTabular()
                Text(small).font(.system(size: size * 0.15, weight: .regular))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons

struct PSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.psHeadline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
    }
}

struct PSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.psHeadline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rControl, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Workout row (rearranged per feedback)
//   header line:  "Wed 10 | Synced to Watch"
//   main line:    ● Title   metric …            [ trailing checkbox ]
//   rest days:    "Tue 9                              Rest day"

struct WorkoutRow: View {
    let day: WorkoutDay
    let dateLabel: String                 // e.g. "Wed 10"
    var unit: DistanceUnit = .kilometers
    var syncState: SyncState = .synced
    var isDone: Bool = false
    var onToggleDone: () -> Void = {}

    var body: some View {
        if day.isRestDay {
            HStack {
                Text(dateLabel).font(.psCallout).foregroundStyle(Theme.ink3)
                Spacer()
                Text("Rest day").font(.psCallout).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, Theme.s4)
            .padding(.vertical, Theme.s3)
        } else {
            VStack(alignment: .leading, spacing: Theme.s2) {
                HStack(spacing: 6) {
                    Text(dateLabel)
                    if syncState != .notSynced {
                        Text("|")
                        Text(syncState.label).foregroundStyle(syncState.color)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink3)

                HStack(spacing: 9) {
                    CategoryDot(category: day.displayCategory)
                    Text(day.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if !day.shortMetric(unit: unit).isEmpty {
                        Text(day.shortMetric(unit: unit))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink2).psTabular()
                    }
                    Spacer(minLength: Theme.s2)
                    CompletionCheckbox(isDone: isDone)
                }
            }
            .padding(Theme.s4)
        }
    }
}

// MARK: - Compact metric label for a workout

extension WorkoutDay {
    func shortMetric(unit: DistanceUnit) -> String {
        if isRestDay { return "" }
        if let iv = segments.first(where: { $0.type == .interval && ($0.reps ?? 0) > 1 }) {
            var s = iv.label(unit: unit, showReps: true)
            let secs = segments.compactMap { $0.durationSeconds }.reduce(0, +)
            if secs >= 600 { s += " · \(secs / 60) min" }
            return s
        }
        let miles = segments.compactMap { $0.distanceMiles }.reduce(0, +)
        if miles > 0 { return unit.format(miles) }
        let secs = segments.compactMap { $0.durationSeconds }.reduce(0, +)
        if secs >= 60 { return "\(secs / 60) min" }
        return ""
    }
}
