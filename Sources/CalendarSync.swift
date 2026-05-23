import SwiftUI
import EventKit
import Foundation

@MainActor
final class CalendarSync {
    static let shared = CalendarSync()
    private let store = EKEventStore()
    private(set) var eventsAuthorized = false
    private(set) var remindersAuthorized = false

    func requestPermissions() async {
        if #available(macOS 14, *) {
            eventsAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
            remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            eventsAuthorized = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
            remindersAuthorized = await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { ok, _ in cont.resume(returning: ok) }
            }
        }
    }

    /// Push task to Reminders (always) and Calendar (only if dueDate).
    /// Returns updated (eventID, reminderID) which the caller persists onto the task.
    @discardableResult
    func upsert(task: TodoTask, categoryName: String) -> (event: String?, reminder: String?) {
        var eventID = task.calendarEventID
        var reminderID = task.reminderID
        let titled = "[\(categoryName)] \(task.title)"

        // Calendar event — only when a due date is set
        if let due = task.dueDate, eventsAuthorized,
           let cal = store.defaultCalendarForNewEvents {
            let event: EKEvent
            if let id = eventID, let existing = store.event(withIdentifier: id) {
                event = existing
            } else {
                event = EKEvent(eventStore: store)
                event.calendar = cal
            }
            event.title = titled
            event.notes = task.notes.isEmpty ? nil : task.notes
            event.startDate = due
            event.endDate = due.addingTimeInterval(30 * 60)
            event.isAllDay = false
            do {
                try store.save(event, span: .thisEvent, commit: true)
                eventID = event.eventIdentifier
            } catch {
                NSLog("QueueDo: calendar save failed: \(error)")
            }
        } else if let id = eventID, let existing = store.event(withIdentifier: id) {
            try? store.remove(existing, span: .thisEvent, commit: true)
            eventID = nil
        }

        // Reminder — always (whether or not dueDate is set)
        if remindersAuthorized, let cal = store.defaultCalendarForNewReminders() {
            let reminder: EKReminder
            if let id = reminderID,
               let existing = store.calendarItem(withIdentifier: id) as? EKReminder {
                reminder = existing
            } else {
                reminder = EKReminder(eventStore: store)
                reminder.calendar = cal
            }
            reminder.title = titled
            reminder.notes = task.notes.isEmpty ? nil : task.notes
            if let due = task.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: due)
            } else {
                reminder.dueDateComponents = nil
            }
            reminder.isCompleted = false
            do {
                try store.save(reminder, commit: true)
                reminderID = reminder.calendarItemIdentifier
            } catch {
                NSLog("QueueDo: reminder save failed: \(error)")
            }
        }

        return (eventID, reminderID)
    }

    func remove(eventID: String?, reminderID: String?) {
        if let id = eventID, let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
        if let id = reminderID,
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
    }

    func markComplete(reminderID: String?, eventID: String?) {
        if let id = reminderID,
           let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
            reminder.isCompleted = true
            try? store.save(reminder, commit: true)
        }
        // Calendar event: leave in calendar for record-keeping; do not delete on complete.
        _ = eventID
    }
}
