import Foundation
import EventKit

/// Centralized sync engine for tasks, reminders, and calendar events.
/// - External ID rules:
///   - Tasks use pomodoroapp://task/<UUID>
///   - Calendar events use pomodoroapp://event/<UUID>
///   - External IDs are stored inside `notes` and are the sole matching key.
/// - Conflict resolution: lastModified wins (remote vs. local).
@MainActor
final class SyncEngine {
    private let eventStore: EKEventStore
    private let permissionsManager: PermissionsManager
    private weak var todoStore: TodoStore?
    private let syncLoopProtectionWindow: TimeInterval = 2
    
    init(permissionsManager: PermissionsManager, todoStore: TodoStore? = nil, eventStore: EKEventStore? = nil) {
        self.permissionsManager = permissionsManager
        self.todoStore = todoStore
        self.eventStore = eventStore ?? SharedEventStore.shared.eventStore
    }
    
    func attachTodoStore(_ store: TodoStore) {
        todoStore = store
    }
    
    func syncAll() async throws {
        try await syncTasksWithReminders()
        try await syncCalendarEvents()
    }
    
    func syncTasksWithReminders() async throws {
        let start = Date()
        print("[SyncEngine] Reminders sync-all start at \(start)")
        try await ensureRemindersAccess()
        guard let store = todoStore else { return }
        let calendar = try reminderCalendar()
        var failureMessages: [String] = []
        
        do {
            try await reverseSyncReminders(in: calendar, store: store)
        } catch {
            let message = "Reverse sync failed: \(error.localizedDescription)"
            print("[SyncEngine][Reminders] \(message)")
            failureMessages.append(message)
        }

        for item in store.items {
            guard item.durationMinutes == nil else { continue }
            do {
                _ = try await syncReminder(for: item, calendar: calendar)
            } catch {
                let message = "Failed to sync task '\(item.title)': \(error.localizedDescription)"
                print("[SyncEngine][Reminders] \(message)")
                failureMessages.append(message)
            }
        }

        let duration = Date().timeIntervalSince(start)
        print("[SyncEngine] Reminders sync-all end. failed: \(failureMessages.count) duration: \(String(format: "%.2f", duration))s")

        if let firstFailure = failureMessages.first {
            throw SyncError.partialReminderSyncFailed(firstFailure)
        }
    }

    func syncReminder(for item: TodoItem) async throws -> String {
        let calendar = try reminderCalendar()
        return try await syncReminder(for: item, calendar: calendar)
    }

    func testReminderCreation() async {
        print("[SyncEngine][RemindersTest] Starting test reminder creation")

        do {
            try await ensureRemindersAccess()
            let calendar = try reminderCalendar()
            print("[SyncEngine][RemindersTest] permission status: \(permissionsManager.remindersStatusText)")
            print("[SyncEngine][RemindersTest] using calendar: \(calendar.title)")

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Pomodoro Test Reminder"
            reminder.notes = "EventKit connectivity test"
            reminder.calendar = calendar
            reminder.priority = 0

            do {
                try eventStore.save(reminder, commit: true)
                print("[SyncEngine][RemindersTest] Test reminder created successfully")
            } catch {
                print("[SyncEngine][RemindersTest] Test reminder failed: \(error)")
            }
        } catch {
            print("[SyncEngine][RemindersTest] Setup failed: \(error)")
        }
    }

    private func syncReminder(for item: TodoItem, calendar: EKCalendar) async throws -> String {
        let start = Date()
        print("[SyncEngine][Reminders] Sync start for task '\(item.title)' at \(start)")
        try await ensureRemindersAccess()
        guard !shouldSkipLoopProtectedImport(for: item) else {
            print("[SyncEngine][Reminders] Skipping outbound sync for '\(item.title)' due to loop protection")
            return item.reminderIdentifier ?? ""
        }

        let existing = existingReminder(for: item)
        let reminder = existing ?? EKReminder(eventStore: eventStore)

        print("[SyncEngine][Reminders] permission status: \(permissionsManager.remindersStatusText)")
        print("[SyncEngine][Reminders] using calendar: \(calendar.title)")
        print("[SyncEngine][Reminders] \(existing == nil ? "Creating" : "Updating") reminder: \(item.title)")

        reminder.calendar = calendar
        applyReminderFields(to: reminder, from: item)

        do {
            try eventStore.save(reminder, commit: true)
            print("[SyncEngine][Reminders] save result: success for '\(item.title)'")
            markTaskSynced(itemId: item.id, reminderIdentifier: reminder.calendarItemIdentifier)
            let duration = Date().timeIntervalSince(start)
            print("[SyncEngine][Reminders] sync end for '\(item.title)' in \(String(format: "%.2f", duration))s")
            return reminder.calendarItemIdentifier
        } catch {
            print("[SyncEngine][Reminders] save result: failed for '\(item.title)' error: \(error)")
            throw SyncError.reminderSaveFailed(item.title, error.localizedDescription)
        }
    }
    
    func syncCalendarEvents() async throws {
        let start = Date()
        var stats = SyncStats()
        print("[SyncEngine] Calendar sync start at \(start)")
        
        try await ensureCalendarAccess()
        guard let store = todoStore else { return }
        
        let events = fetchUpcomingEvents()
        stats.read = events.count
        
        var eventMap: [String: EKEvent] = [:]
        events.forEach { event in
            if let parsed = ExternalID.parse(from: event.notes),
               (parsed.externalId.hasPrefix(ExternalID.eventPrefix) || parsed.externalId.hasPrefix(ExternalID.taskPrefix)) {
                eventMap[parsed.externalId] = event
            } else {
                // Respect user control: do not import Calendar events that are not Pomodoro-managed.
                stats.skipped += 1
            }
        }
        
        for item in store.items {
            guard item.syncToCalendar else { continue }
            guard item.dueDate != nil else { continue }
            
            let externalId = item.externalId
            let legacyExternalId = ExternalID.eventId(for: item.id)
            if let existing = eventMap[externalId] ?? eventMap[legacyExternalId] {
                let remoteModified = existing.lastModifiedDate ?? existing.creationDate ?? .distantPast
                if remoteModified > item.lastModified {
                    var updated = item
                    updated.title = existing.title
                    updated.notes = ExternalID.parse(from: existing.notes)?.cleanNotes
                    updated.dueDate = existing.startDate
                    updated.hasDueTime = !existing.isAllDay
                    updated.calendarEventIdentifier = existing.eventIdentifier
                    updated.linkedCalendarEventId = existing.eventIdentifier
                    updated.lastModified = remoteModified
                    store.updateItem(updated)
                    print("[SyncEngine][Calendar] remote wins for \(externalId)")
                } else {
                    try updateEvent(existing, with: item, externalId: externalId)
                    var updated = item
                    updated.linkedCalendarEventId = existing.eventIdentifier
                    store.updateItem(updated)
                    print("[SyncEngine][Calendar] local wins for \(externalId)")
                }
                stats.written += 1
            } else {
                let eventId = try createEvent(from: item, externalId: externalId)
                var updated = item
                updated.calendarEventIdentifier = eventId
                updated.linkedCalendarEventId = eventId
                updated.lastModified = Date()
                store.updateItem(updated)
                print("[SyncEngine][Calendar] created remote for \(externalId)")
                stats.written += 1
            }
        }
        
        let duration = Date().timeIntervalSince(start)
        print("[SyncEngine] Calendar sync end. read: \(stats.read) written: \(stats.written) skipped: \(stats.skipped) duration: \(String(format: "%.2f", duration))s")
    }
    
    func deleteReminder(for item: TodoItem) async throws {
        guard let reminderIdentifier = item.reminderIdentifier else { return }
        try await ensureRemindersAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else { return }
        try eventStore.remove(reminder, commit: true)
    }
    
    // MARK: - Permissions
    
    private func ensureRemindersAccess() async throws {
        if permissionsManager.isRemindersAuthorized { return }
        await permissionsManager.requestRemindersPermission()
        if !permissionsManager.isRemindersAuthorized {
            throw SyncError.notAuthorized
        }
    }
    
    private func ensureCalendarAccess() async throws {
        if permissionsManager.isCalendarAuthorized { return }
        await permissionsManager.requestCalendarPermission()
        if !permissionsManager.isCalendarAuthorized {
            throw SyncError.notAuthorized
        }
    }
    
    // MARK: - Reminders Helpers

    private func reminderComponents(from item: TodoItem) -> DateComponents? {
        guard let due = item.dueDate else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
        if item.hasDueTime {
            let time = Calendar.current.dateComponents([.hour, .minute], from: due)
            components.hour = time.hour
            components.minute = time.minute
        }
        return components
    }
    
    private func fetchAllReminders() async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
    
    private func createReminder(from item: TodoItem) throws -> String {
        let reminder = EKReminder(eventStore: eventStore)
        applyReminderFields(to: reminder, from: item)
        reminder.calendar = try reminderCalendar()
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    
    private func updateReminder(_ reminder: EKReminder, with item: TodoItem) throws {
        if reminder.calendar == nil {
            reminder.calendar = try reminderCalendar()
        }
        applyReminderFields(to: reminder, from: item)
        try eventStore.save(reminder, commit: true)
    }

    private func applyReminderFields(to reminder: EKReminder, from item: TodoItem) {
        reminder.title = item.title
        reminder.notes = reminderNotes(from: item)
        reminder.isCompleted = item.isCompleted
        reminder.dueDateComponents = reminderComponents(from: item)
        reminder.priority = 0
    }

    private func reminderCalendar() throws -> EKCalendar {
        print("[SyncEngine][Reminders] selecting default reminders calendar")
        if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            return defaultCalendar
        }
        print("[SyncEngine][Reminders] no default reminders calendar available")
        throw SyncError.noReminderCalendar
    }

    private func reminderNotes(from item: TodoItem) -> String {
        item.notes ?? ""
    }

    private func existingReminder(for item: TodoItem) -> EKReminder? {
        guard let reminderIdentifier = item.reminderIdentifier else { return nil }
        return eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder
    }

    private func reverseSyncReminders(in calendar: EKCalendar, store: TodoStore) async throws {
        print("[SyncEngine][Reminders] Reverse sync start for calendar: \(calendar.title)")
        let reminders = await fetchReminders(in: calendar)
        print("[SyncEngine][Reminders] Reverse sync fetched \(reminders.count) reminders")

        for reminder in reminders {
            let reminderTitle = reminder.title ?? "Untitled Reminder"
            print("[SyncEngine][Reminders] Importing reminder: \(reminderTitle)")

            if let local = store.items.first(where: { $0.reminderIdentifier == reminder.calendarItemIdentifier }) {
                if shouldSkipLoopProtectedImport(for: local) {
                    print("[SyncEngine][Reminders] Skipping import for '\(reminderTitle)' due to loop protection")
                    continue
                }

                var updated = local
                updated.title = reminderTitle
                updated.notes = cleanedReminderNotes(reminder.notes)
                updated.isCompleted = reminder.isCompleted
                updated.dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                updated.hasDueTime = reminder.dueDateComponents?.hasTimeComponents ?? false
                updated.lastModified = reminder.lastModifiedDate ?? reminder.creationDate ?? Date()
                updated.reminderIdentifier = reminder.calendarItemIdentifier
                updated.lastSyncedAt = Date()
                updated.syncStatus = .synced
                store.updateItem(updated)
                print("[SyncEngine][Reminders] Updated local task from reminder: \(reminderTitle)")
            } else {
                let newTask = TodoItem(
                    title: reminderTitle,
                    notes: cleanedReminderNotes(reminder.notes),
                    isCompleted: reminder.isCompleted,
                    dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    hasDueTime: reminder.dueDateComponents?.hasTimeComponents ?? false,
                    reminderIdentifier: reminder.calendarItemIdentifier,
                    lastSyncedAt: Date(),
                    syncStatus: .synced
                )
                store.addItem(newTask)
                print("[SyncEngine][Reminders] Created local task from reminder: \(reminderTitle)")
            }
        }
    }

    private func cleanedReminderNotes(_ notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        return notes
    }

    private func shouldSkipLoopProtectedImport(for item: TodoItem) -> Bool {
        guard let lastSyncedAt = item.lastSyncedAt else { return false }
        return Date().timeIntervalSince(lastSyncedAt) < syncLoopProtectionWindow
    }

    private func markTaskSynced(itemId: UUID, reminderIdentifier: String) {
        guard let store = todoStore,
              let existing = store.items.first(where: { $0.id == itemId }) else {
            return
        }
        var updated = existing
        updated.reminderIdentifier = reminderIdentifier
        updated.lastSyncedAt = Date()
        updated.lastModified = Date()
        updated.syncStatus = .synced
        store.updateItem(updated)
    }
    
    // MARK: - Calendar Helpers
    
    private func fetchUpcomingEvents() -> [EKEvent] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let end = Calendar.current.date(byAdding: .month, value: 12, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
    }
    
    private func createEvent(from item: TodoItem, externalId: String) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = combinedNotes(from: item.notes, tags: item.tags, externalId: externalId)
        if let due = item.dueDate {
            if item.hasDueTime {
                event.isAllDay = false
                event.startDate = due
                let durationMinutes = item.durationMinutes ?? 30
                event.endDate = due.addingTimeInterval(Double(durationMinutes * 60))
            } else {
                let start = Calendar.current.startOfDay(for: due)
                event.isAllDay = true
                event.startDate = start
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: start)
            }
        }
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
    
    private func updateEvent(_ event: EKEvent, with item: TodoItem, externalId: String) throws {
        event.title = item.title
        event.notes = combinedNotes(from: item.notes, tags: item.tags, externalId: externalId)
        if let due = item.dueDate {
            if item.hasDueTime {
                event.isAllDay = false
                event.startDate = due
                let durationMinutes = item.durationMinutes ?? 30
                event.endDate = due.addingTimeInterval(Double(durationMinutes * 60))
            } else {
                let start = Calendar.current.startOfDay(for: due)
                event.isAllDay = true
                event.startDate = start
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: start)
            }
        }
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    
    // MARK: - Shared Helpers
    
    private func combinedNotes(from userNotes: String?, tags: [String], externalId: String) -> String {
        var baseNotes: String?
        if let notes = userNotes, !notes.isEmpty {
            baseNotes = notes
        }
        if !tags.isEmpty {
            let tagLine = "Tags: \(tags.joined(separator: ", "))"
            if var existing = baseNotes, !existing.isEmpty {
                existing.append("\n\(tagLine)")
                baseNotes = existing
            } else {
                baseNotes = tagLine
            }
        }
        return ExternalID.upsert(in: baseNotes, externalId: externalId)
    }
    
    private func uuid(from externalId: String, expectedPrefix: String) -> UUID? {
        guard externalId.hasPrefix(expectedPrefix) else { return nil }
        let suffix = externalId.replacingOccurrences(of: expectedPrefix, with: "")
        return UUID(uuidString: suffix)
    }
    
    // MARK: - Types

    private struct SyncStats {
        var read = 0
        var written = 0
        var skipped = 0
    }
    
    enum SyncError: LocalizedError {
        case notAuthorized
        case noReminderCalendar
        case reminderSaveFailed(String, String)
        case partialReminderSyncFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Reminders access not authorized."
            case .noReminderCalendar:
                return "No default reminders calendar is available."
            case let .reminderSaveFailed(title, message):
                return "Reminder save failed for '\(title)': \(message)"
            case let .partialReminderSyncFailed(message):
                return message
            }
        }
    }
}

private extension DateComponents {
    var hasTimeComponents: Bool {
        hour != nil || minute != nil || second != nil
    }
}
