import Foundation
import Combine
import EventKit

/// Task-centric sync manager for Reminders and Calendar events.
@MainActor
final class RemindersSync: ObservableObject {
    private let eventStore = EKEventStore()
    private let permissionsManager: PermissionsManager
    private weak var todoStore: TodoStore?
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncEnabled: Bool = false
    
    init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager
    }
    
    func setTodoStore(_ store: TodoStore) {
        self.todoStore = store
    }
    
    // MARK: - Sync Operations
    
    var isSyncAvailable: Bool {
        permissionsManager.isRemindersAuthorized
    }
    
    /// Sync a single task to Reminders or Calendar (one-way, task is source of truth)
    func syncTask(_ item: TodoItem) async throws {
        try await ensureAccess()
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            try await syncSingleItem(item)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }
    
    /// One-way sync for all tasks (create/update only, never delete)
    func syncAllTasks() async {
        print("SYNC START")
        do {
            try await ensureAccess()
        } catch {
            lastSyncError = error.localizedDescription
            return
        }
        guard let store = todoStore else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Pull from Reminders first
        await pullRemindersIntoStore()
        
        // Push all tasks to Reminders/Calendar
        for item in store.items {
            do {
                try await syncSingleItem(item)
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
        
        // Remove tasks whose reminder no longer exists
        await pruneDeletedReminders()
        
        lastSyncDate = Date()
        DispatchQueue.main.async {
            self.todoStore?.objectWillChange.send()
        }
    }
    
    /// Remove Reminder link (does not delete remote)
    func unsyncFromReminders(_ item: TodoItem) {
        guard item.reminderIdentifier != nil else { return }
        todoStore?.unlinkFromReminder(itemId: item.id)
    }
    
    /// Delete reminder from Apple Reminders
    func deleteReminder(_ item: TodoItem) async throws {
        guard isSyncAvailable,
              let remindersId = item.reminderIdentifier,
              let reminder = eventStore.calendarItem(withIdentifier: remindersId) as? EKReminder else {
            return
        }
        
        try eventStore.remove(reminder, commit: true)
        todoStore?.unlinkFromReminder(itemId: item.id)
    }
    
    // MARK: - Private Helpers
    
    private func syncSingleItem(_ item: TodoItem) async throws {
        guard item.dueDate != nil else { return }
        
        if let duration = item.durationMinutes, duration > 0 {
            // Calendar event path
            if let eventId = item.calendarEventIdentifier,
               let event = eventStore.event(withIdentifier: eventId) {
                try await updateEvent(event, with: item, duration: duration)
            } else {
                let eventId = try await createEvent(from: item, duration: duration)
                todoStore?.linkToCalendarEvent(itemId: item.id, eventId: eventId)
            }
        } else {
            // Reminder path
            if let remindersId = item.reminderIdentifier {
                try await updateReminder(remindersId, with: item)
            } else {
                let reminderId = try await createReminder(from: item)
                todoStore?.linkToReminder(itemId: item.id, remindersId: reminderId)
            }
        }
    }
    
    private func ensureAccess() async throws {
        if permissionsManager.isRemindersAuthorized { return }
        let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestAccess(to: .reminder) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        if !granted {
            throw SyncError.notAuthorized
        }
        permissionsManager.refreshRemindersStatus()
    }
    
    private func fetchAllReminders() async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
    
    private func pullRemindersIntoStore() async {
        guard let store = todoStore else { return }
        let reminders = await fetchAllReminders()
        
        for reminder in reminders {
            let id = reminder.calendarItemIdentifier
            if var existing = store.items.first(where: { $0.reminderIdentifier == id }) {
                existing.title = reminder.title
                existing.notes = reminder.notes
                existing.isCompleted = reminder.isCompleted
                if let comps = reminder.dueDateComponents,
                   let date = Calendar.current.date(from: comps) {
                    existing.dueDate = date
                }
                existing.syncStatus = .synced
                store.updateItem(existing)
            } else {
                let newTask = TodoItem(
                    title: reminder.title,
                    notes: reminder.notes,
                    isCompleted: reminder.isCompleted,
                    dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    durationMinutes: nil,
                    priority: .none,
                    tags: [],
                    reminderIdentifier: id,
                    calendarEventIdentifier: nil,
                    syncStatus: .synced
                )
                store.addItem(newTask)
            }
        }
    }
    
    private func pruneDeletedReminders() async {
        guard let store = todoStore else { return }
        let reminders = await fetchAllReminders()
        let existingIDs = Set(reminders.compactMap { $0.calendarItemIdentifier })
        let toDelete = store.items.filter { item in
            if let reminderId = item.reminderIdentifier {
                return !existingIDs.contains(reminderId)
            }
            return false
        }
        toDelete.forEach { store.deleteItem($0) }
    }
    
    private func createReminder(from item: TodoItem) async throws -> String {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = item.title
        reminder.notes = combinedNotes(from: item)
        reminder.isCompleted = item.isCompleted
        
        if let dueDate = item.dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }
        
        reminder.priority = reminderPriority(from: item.priority)
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    
    private func updateReminder(_ remindersId: String, with item: TodoItem) async throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: remindersId) as? EKReminder else {
            throw SyncError.reminderNotFound
        }
        
        reminder.title = item.title
        reminder.notes = combinedNotes(from: item)
        reminder.isCompleted = item.isCompleted
        
        if let dueDate = item.dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        } else {
            reminder.dueDateComponents = nil
        }
        
        reminder.priority = reminderPriority(from: item.priority)
        try eventStore.save(reminder, commit: true)
    }
    
    private func createEvent(from item: TodoItem, duration: Int) async throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = combinedNotes(from: item)
        event.startDate = item.dueDate
        event.endDate = item.dueDate?.addingTimeInterval(Double(duration * 60))
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
    
    private func updateEvent(_ event: EKEvent, with item: TodoItem, duration: Int) async throws {
        event.title = item.title
        event.notes = combinedNotes(from: item)
        event.startDate = item.dueDate
        event.endDate = item.dueDate?.addingTimeInterval(Double(duration * 60))
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    
    private func reminderPriority(from todoPriority: TodoItem.Priority) -> Int {
        switch todoPriority {
        case .none:
            return 0
        case .low:
            return 9
        case .medium:
            return 5
        case .high:
            return 1
        }
    }
    
    private func combinedNotes(from item: TodoItem) -> String? {
        var parts: [String] = []
        if let notes = item.notes, !notes.isEmpty {
            parts.append(notes)
        }
        if !item.tags.isEmpty {
            parts.append("Tags: \(item.tags.joined(separator: ", "))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
    
    // MARK: - Error Types
    
    enum SyncError: LocalizedError {
        case notAuthorized
        case failedToSync
        case reminderNotFound
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Reminders access not authorized"
            case .failedToSync:
                return "Failed to sync with Reminders"
            case .reminderNotFound:
                return "Reminder not found"
            }
        }
    }
}
