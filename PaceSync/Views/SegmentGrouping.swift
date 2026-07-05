// SegmentGrouping.swift
// Groups a flat segment list into single segments and repeat-groups (by setIndex or
// a work+rest pair with reps). Shared by the editor and any segment display.

import Foundation

enum SegmentDisplayItem: Identifiable {
    case single(WorkoutSegment)
    case repeatGroup(id: Int, iterations: Int, segments: [WorkoutSegment])

    var id: String {
        switch self {
        case .single(let seg): return seg.id.uuidString
        case .repeatGroup(let idx, _, _): return "group-\(idx)"
        }
    }
}

func groupedSegmentItems(from segments: [WorkoutSegment]) -> [SegmentDisplayItem] {
    var items: [SegmentDisplayItem] = []
    var nextGroupID = 100  // avoid colliding with setIndex values
    var i = 0
    while i < segments.count {
        let seg = segments[i]

        if let setIdx = seg.setIndex {
            // Complex set: all consecutive segments sharing this setIndex
            var group: [WorkoutSegment] = []
            while i < segments.count && segments[i].setIndex == setIdx {
                group.append(segments[i])
                i += 1
            }
            let iterations = group.first(where: { $0.reps != nil })?.reps ?? 1
            items.append(.repeatGroup(id: setIdx, iterations: iterations, segments: group))

        } else if let reps = seg.reps, reps > 1,
                  seg.setIndex == nil,
                  i + 1 < segments.count,
                  segments[i + 1].type == .rest,
                  segments[i + 1].setIndex == nil {
            // Simple pair with reps: work + rest → wrap in repeat group
            let rest = segments[i + 1]
            items.append(.repeatGroup(id: nextGroupID, iterations: reps, segments: [seg, rest]))
            nextGroupID += 1
            i += 2

        } else {
            items.append(.single(seg))
            i += 1
        }
    }
    return items
}
