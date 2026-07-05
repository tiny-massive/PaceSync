// EventKitService.swift
// Syncs workouts to a dedicated "PaceSync" calendar on the phone. Events are keyed by
// their EKEvent identifier (stored on WorkoutDay.calendarEventID) so re-dating MOVES an
// event rather than duplicating it. We only ever touch our own calendar.

import Foundation
import EventKit
import UIKit

@MainActor
final class EventKitService {
    static let shared = EventKitService()
    private let store = EKEventStore()
    private let calendarIDKey = "pacesync.calendarID"

    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
        } catch {
            return false
        }
    }

    private func paceSyncCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarIDKey),
           let cal = store.calendar(withIdentifier: id) { return cal }
        if let existing = store.calendars(for: .event).first(where: { $0.title == "PaceSync" }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: calendarIDKey)
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "PaceSync"
        cal.cgColor = UIColor(red: 0.06, green: 0.54, blue: 0.29, alpha: 1).cgColor
        cal.source = store.defaultCalendarForNewEvents?.source
                  ?? store.sources.first { $0.sourceType == .local }
                  ?? store.sources.first
        guard cal.source != nil else { return nil }
        do {
            try store.saveCalendar(cal, commit: true)
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: calendarIDKey)
            return cal
        } catch {
            return nil
        }
    }

    /// Create or move an all-day event for a workout. Returns its identifier.
    func upsert(title: String, notes: String?, date: Date, existingID: String?) -> String? {
        guard let cal = paceSyncCalendar() else { return nil }
        let event = existingID.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
        event.calendar = cal
        event.title = title
        event.notes = notes
        event.isAllDay = true
        let start = Calendar.current.startOfDay(for: date)
        event.startDate = start
        event.endDate = start
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    func remove(_ id: String) {
        guard let e = store.event(withIdentifier: id) else { return }
        try? store.remove(e, span: .thisEvent, commit: true)
    }
}
