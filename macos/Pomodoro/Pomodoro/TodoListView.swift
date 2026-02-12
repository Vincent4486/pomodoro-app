import SwiftUI
import AppKit

/// Todo/Tasks view - always accessible with optional Reminders sync.
/// Shows non-blocking banner when Reminders is unauthorized.
@MainActor
struct TodoListView: View {
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var remindersSync: RemindersSync
    @ObservedObject var permissionsManager: PermissionsManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    @State private var showingEditor = false
    @State private var editingItem: TodoItem?
    @State private var titleField = ""
    @State private var notesField = ""
    @State private var tagsField = ""
    @State private var dueDateEnabled = false
    @State private var dueDateField = Date()
    /// Time is opt-in; we default to date-only for quick entry.
    @State private var includeDueTime = false
    @State private var selectedSegment: Segment = .active
    @State private var syncToCalendarField = false
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var lastSelectedTaskID: UUID?
    @State private var batchDueDate: Date = Date()
    @State private var showBatchDeleteConfirmation = false
    @State private var showTaskHint = false
    
    private static let taskHintDefaultsKey = "com.pomodoro.taskHintShown"
    
    private enum Segment: String, CaseIterable, Identifiable {
        case active
        case completed

        var id: String { rawValue }
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    private static let lastSyncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(localizationManager.text("tasks.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(localizationManager.text("tasks.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 16)
            
            // Non-blocking Reminders banner
            if !permissionsManager.isRemindersAuthorized {
                remindersBanner
            }
            
            if showTaskHint {
                taskHint
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
            }

            planningOverview
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            
            // Toolbar
            HStack {
                Button(action: { openEditorForNew() }) {
                    Label(localizationManager.text("tasks.add_task"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                
                if permissionsManager.isRemindersAuthorized {
                    Button {
                        Task { await remindersSync.syncAllTasks() }
                    } label: {
                        if remindersSync.isSyncing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localizationManager.text("tasks.syncing"))
                            }
                        } else {
                            Label(localizationManager.text("tasks.sync_all_tasks"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(remindersSync.isSyncing)
                }
                
                Spacer()
                
                Picker("", selection: $selectedSegment) {
                    Text(localizationManager.text("tasks.segment.active")).tag(Segment.active)
                    Text(localizationManager.text("tasks.segment.completed")).tag(Segment.completed)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            
            if let last = remindersSync.lastSyncDate {
                HStack {
                    Text(localizationManager.format("tasks.last_sync_format", formatLastSyncDate(last)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(localizationManager.text("tasks.auto_sync"), isOn: $remindersSync.isAutoSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 6)
            }
            
            Divider()
            
            // Batch actions bar (shown only when multi-select is active)
            if selectedTaskIDs.count > 1 {
                batchActionsBar
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
            }
            
            // Tasks list
            ScrollView {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            todoRow(item)
                                .opacity(selectedSegment == .completed ? 0.9 : 1.0)
                                .allowsHitTesting(selectedSegment == .completed ? false : true)
                        }
                    }
                    .padding(16)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .sheet(isPresented: $showingEditor) {
            taskEditorSheet
        }
        .onAppear {
            permissionsManager.refreshRemindersStatus()
            if !UserDefaults.standard.bool(forKey: Self.taskHintDefaultsKey) {
                showTaskHint = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewTaskComposer)) { _ in
            openEditorForNew()
        }
    }
    
    private var remindersBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.text("tasks.reminders_sync_disabled.title"))
                    .font(.headline)
                
                Text(localizationManager.text("tasks.reminders_sync_disabled.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(localizationManager.text("permissions.enable")) {
                Task {
                    await permissionsManager.requestRemindersPermission()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
        .alert(localizationManager.text("tasks.reminders_access_denied.title"), isPresented: $permissionsManager.showRemindersDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("tasks.reminders_access_denied.body"))
        }
    }

    private var planningOverview: some View {
        HStack(spacing: 10) {
            planningPill(
                title: localizationManager.text("tasks.planned"),
                value: "\(plannedTaskCount)",
                color: .green
            )
            planningPill(
                title: localizationManager.text("tasks.unplanned"),
                value: "\(unplannedTaskCount)",
                color: .orange
            )
            planningPill(
                title: localizationManager.text("tasks.planned_today"),
                value: "\(plannedTodayCount)",
                color: .blue
            )
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }

    private func planningPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(localizationManager.text("tasks.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(localizationManager.text("tasks.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
    
    /// Inline, dismissible hint for first-time task writers.
    private var taskHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(localizationManager.text("tasks.hint.title"))
                    .font(.headline)
                Text(localizationManager.text("tasks.hint.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showTaskHint = false
                UserDefaults.standard.set(true, forKey: Self.taskHintDefaultsKey)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        let isSelected = selectedTaskIDs.contains(item.id)
        HStack(spacing: 12) {
            Button(action: {
                todoStore.toggleCompletion(item)
                
                // Sync to Reminders if authorized and linked
                if permissionsManager.isRemindersAuthorized,
                   item.reminderIdentifier != nil {
                    Task {
                        if let updatedItem = todoStore.items.first(where: { $0.id == item.id }) {
                            try? await remindersSync.syncTask(updatedItem)
                        }
                    }
                }
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                if IntentMarkers.containsFocusIntent(in: item.title) || IntentMarkers.containsFocusIntent(in: item.notes) {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(localizationManager.text("tasks.focus_marked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !item.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    if item.priority != .none {
                        priorityBadge(item.priority)
                    }
                    
                    if let dueDate = item.dueDate {
                        Label(formattedDueDate(item, dueDate: dueDate), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if item.reminderIdentifier != nil {
                        Label(localizationManager.text("tasks.status.synced"), systemImage: "checkmark.icloud")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if item.syncToCalendar, (item.linkedCalendarEventId ?? item.calendarEventIdentifier) != nil {
                        Label(localizationManager.text("tasks.status.in_calendar"), systemImage: "calendar.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if planningItem(for: item) != nil {
                        Label(planningStatusLabel(for: item), systemImage: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else if !item.isCompleted {
                        Label(localizationManager.text("tasks.unplanned"), systemImage: "calendar.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            Menu {
                if permissionsManager.isRemindersAuthorized {
                    if item.reminderIdentifier == nil {
                        Button(action: {
                            Task {
                                try? await remindersSync.syncTask(item)
                            }
                        }) {
                            Label(localizationManager.text("tasks.action.sync_to_reminders"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else {
                        Button(action: {
                            remindersSync.unsyncFromReminders(item)
                        }) {
                            Label(localizationManager.text("tasks.action.unsync_from_reminders"), systemImage: "xmark.icloud")
                        }
                    }
                    
                    Divider()
                }
                
                Button {
                    openEditorForEdit(item)
                } label: {
                    Label(localizationManager.text("common.edit"), systemImage: "pencil")
                }

                if item.dueDate == nil {
                    Button {
                        planTaskForToday(item)
                    } label: {
                        Label(localizationManager.text("tasks.action.plan_for_today"), systemImage: "calendar.badge.plus")
                    }
                } else {
                    Button {
                        clearPlanDate(for: item)
                    } label: {
                        Label(localizationManager.text("tasks.action.remove_plan_date"), systemImage: "calendar.badge.minus")
                    }
                }
                
                Button(role: .destructive, action: {
                    if item.reminderIdentifier != nil {
                        Task {
                            try? await remindersSync.deleteReminder(item)
                        }
                    }
                    todoStore.deleteItem(item)
                }) {
                    Label(localizationManager.text("common.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTaskSelection(item)
        }
    }
    
    @ViewBuilder
    private func priorityBadge(_ priority: TodoItem.Priority) -> some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.2))
            .foregroundStyle(priorityColor(priority))
            .cornerRadius(4)
    }
    
    private func priorityColor(_ priority: TodoItem.Priority) -> Color {
        switch priority {
        case .none:
            return .gray
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
    
    private func formattedDueDate(_ item: TodoItem, dueDate: Date) -> String {
        Self.dateFormatter.locale = localizationManager.effectiveLocale
        Self.dateTimeFormatter.locale = localizationManager.effectiveLocale
        if item.hasDueTime {
            return Self.dateTimeFormatter.string(from: dueDate)
        }
        return Self.dateFormatter.string(from: dueDate)
    }

    private func formatLastSyncDate(_ date: Date) -> String {
        Self.lastSyncFormatter.locale = localizationManager.effectiveLocale
        return Self.lastSyncFormatter.string(from: date)
    }
    
    /// Strips the time portion unless the user explicitly opted in.
    private func normalizedDueDate(from date: Date, includeTime: Bool) -> Date {
        guard !includeTime else { return date }
        return Calendar.current.startOfDay(for: date)
    }
    
    /// Preserve an existing time component when moving to a new day.
    private func mergedDueDate(newDay: Date, from task: TodoItem) -> (date: Date, hasTime: Bool) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: newDay)
        guard task.hasDueTime, let existing = task.dueDate else {
            return (dayStart, false)
        }
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: existing)
        let merged = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: timeComponents.second ?? 0,
            of: dayStart
        ) ?? dayStart
        return (merged, true)
    }
    
    private var filteredItems: [TodoItem] {
        switch selectedSegment {
        case .active:
            return todoStore.pendingItems
        case .completed:
            return todoStore.completedItems.sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private var taskPlansByID: [UUID: PlanningItem] {
        planningStore.items.reduce(into: [UUID: PlanningItem]()) { result, plan in
            guard plan.sourceType == .task,
                  let sourceID = plan.sourceID,
                  let taskID = UUID(uuidString: sourceID) else {
                return
            }
            result[taskID] = plan
        }
    }

    private var plannedTaskCount: Int {
        todoStore.items.filter { taskPlansByID[$0.id] != nil }.count
    }

    private var unplannedTaskCount: Int {
        max(0, todoStore.items.count - plannedTaskCount)
    }

    private var plannedTodayCount: Int {
        let calendar = Calendar.current
        return todoStore.pendingItems.filter { item in
            guard let start = taskPlansByID[item.id]?.startDate else { return false }
            return calendar.isDateInToday(start)
        }.count
    }

    private func planningItem(for item: TodoItem) -> PlanningItem? {
        taskPlansByID[item.id]
    }

    private func planningStatusLabel(for item: TodoItem) -> String {
        guard let start = planningItem(for: item)?.startDate else {
            return localizationManager.text("tasks.unplanned")
        }
        Self.dateFormatter.locale = localizationManager.effectiveLocale
        Self.dateTimeFormatter.locale = localizationManager.effectiveLocale
        let calendar = Calendar.current
        if calendar.isDateInToday(start) {
            return item.hasDueTime
                ? localizationManager.format("tasks.plan_status.today_time_format", Self.dateTimeFormatter.string(from: start))
                : localizationManager.text("tasks.plan_status.planned_today")
        }
        if calendar.isDateInTomorrow(start) {
            return item.hasDueTime
                ? localizationManager.format("tasks.plan_status.tomorrow_time_format", Self.dateTimeFormatter.string(from: start))
                : localizationManager.text("tasks.plan_status.planned_tomorrow")
        }
        return item.hasDueTime
            ? Self.dateTimeFormatter.string(from: start)
            : Self.dateFormatter.string(from: start)
    }

    private func planTaskForToday(_ item: TodoItem) {
        var updated = item
        updated.dueDate = Calendar.current.startOfDay(for: Date())
        updated.hasDueTime = false
        updated.modifiedAt = Date()
        todoStore.updateItem(updated)
        syncToRemindersIfLinked(updated)
    }

    private func clearPlanDate(for item: TodoItem) {
        var updated = item
        updated.dueDate = nil
        updated.hasDueTime = false
        updated.modifiedAt = Date()
        todoStore.updateItem(updated)
        syncToRemindersIfLinked(updated)
    }

    private func syncToRemindersIfLinked(_ item: TodoItem) {
        guard permissionsManager.isRemindersAuthorized,
              item.reminderIdentifier != nil else {
            return
        }
        Task {
            try? await remindersSync.syncTask(item)
        }
    }
    
    private var taskEditorSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editingItem == nil ? localizationManager.text("tasks.editor.add_title") : localizationManager.text("tasks.editor.edit_title"))
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 10) {
                TextField(localizationManager.text("tasks.editor.title_placeholder"), text: $titleField)
                    .textFieldStyle(.roundedBorder)
                
                Toggle(localizationManager.text("tasks.editor.set_due_date"), isOn: $dueDateEnabled)
                    .onChange(of: dueDateEnabled) { _, isOn in
                        // Default to date-only when enabling; user opts into time explicitly.
                        if !isOn { includeDueTime = false }
                    }
                
                if dueDateEnabled {
                    DatePicker(
                        localizationManager.text("tasks.editor.due_date"),
                        selection: $dueDateField,
                        displayedComponents: [.date]
                    )
                    Toggle(localizationManager.text("tasks.editor.include_time"), isOn: $includeDueTime)
                        .toggleStyle(.switch)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if includeDueTime {
                        DatePicker(
                            localizationManager.text("tasks.editor.time"),
                            selection: $dueDateField,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.field)
                    } else {
                        Text(localizationManager.text("tasks.editor.date_only_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(localizationManager.text("tasks.editor.notes_optional"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(localizationManager.text("tasks.editor.notes_placeholder"), text: $notesField, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                
                Text(localizationManager.text("tasks.editor.tags_optional"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(localizationManager.text("tasks.editor.tags_placeholder"), text: $tagsField)
                    .textFieldStyle(.roundedBorder)
                
                Toggle(localizationManager.text("tasks.editor.sync_to_calendar"), isOn: $syncToCalendarField)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.top, 6)
                    .help(localizationManager.text("tasks.editor.sync_to_calendar_help"))
            }
            
            Spacer(minLength: 0)
            
            HStack {
                Button(localizationManager.text("common.cancel")) {
                    resetEditor()
                    showingEditor = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(editingItem == nil ? localizationManager.text("common.add") : localizationManager.text("common.save")) {
                    saveTask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(titleField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
    
    private func openEditorForNew() {
        editingItem = nil
        titleField = ""
        notesField = ""
        tagsField = ""
        dueDateEnabled = false
        dueDateField = Date()
        includeDueTime = false
        syncToCalendarField = false
        showingEditor = true
    }
    
    private func openEditorForEdit(_ item: TodoItem) {
        editingItem = item
        titleField = item.title
        notesField = item.notes ?? ""
        tagsField = item.tags.joined(separator: ", ")
        if let due = item.dueDate {
            dueDateEnabled = true
            dueDateField = due
            includeDueTime = item.hasDueTime
        } else {
            dueDateEnabled = false
            dueDateField = Date()
            includeDueTime = false
        }
        syncToCalendarField = item.syncToCalendar
        showingEditor = true
    }
    
    private func resetEditor() {
        editingItem = nil
        titleField = ""
        notesField = ""
        tagsField = ""
        dueDateEnabled = false
        dueDateField = Date()
        includeDueTime = false
        syncToCalendarField = false
    }
    
    private func saveTask() {
        let trimmedTitle = titleField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let hasDueTime = dueDateEnabled ? includeDueTime : false
        let dueDate = dueDateEnabled ? normalizedDueDate(from: dueDateField, includeTime: includeDueTime) : nil
        let trimmedNotes = notesField.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tagsField
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        if var editing = editingItem {
            editing.title = trimmedTitle
            editing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            editing.dueDate = dueDate
            editing.hasDueTime = hasDueTime
            editing.tags = tags
            editing.syncToCalendar = syncToCalendarField
            todoStore.updateItem(editing)
            
            if permissionsManager.isRemindersAuthorized,
               editing.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(editing) }
            }
        } else {
            let newItem = TodoItem(
                title: trimmedTitle,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueDate: dueDate,
                hasDueTime: hasDueTime,
                syncToCalendar: syncToCalendarField
            )
            todoStore.addItem(newItem)
        }
        
        resetEditor()
        showingEditor = false
    }
}

// MARK: - Selection helpers

extension TodoListView {
    fileprivate func handleTaskSelection(_ item: TodoItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)
        
        if isShift, let anchor = lastSelectedTaskID,
           let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchor }),
           let targetIndex = filteredItems.firstIndex(where: { $0.id == item.id }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangeIDs = filteredItems[lower...upper].map { $0.id }
            selectedTaskIDs.formUnion(rangeIDs)
            lastSelectedTaskID = item.id
            return
        }
        
        if isCommand {
            if selectedTaskIDs.contains(item.id) {
                selectedTaskIDs.remove(item.id)
            } else {
                selectedTaskIDs.insert(item.id)
                lastSelectedTaskID = item.id
            }
            return
        }
        
        // Default single selection
        selectedTaskIDs = [item.id]
        lastSelectedTaskID = item.id
    }
}

// MARK: - Batch actions

extension TodoListView {
    @ViewBuilder
    fileprivate var batchActionsBar: some View {
        HStack(spacing: 12) {
            Text(localizationManager.format("common.selected_count", selectedTaskIDs.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            DatePicker(
                localizationManager.text("common.move_to"),
                selection: $batchDueDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            
            Button {
                applyBatchMove(to: batchDueDate)
            } label: {
                Label(localizationManager.text("common.move"), systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            
            Button {
                applyBatchClearDate()
            } label: {
                Label(localizationManager.text("tasks.action.clear_date"), systemImage: "calendar.badge.minus")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button(role: .destructive) {
                showBatchDeleteConfirmation = true
            } label: {
                Label(localizationManager.text("common.delete"), systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .alert(localizationManager.format("tasks.batch.delete_confirmation_title", selectedTaskIDs.count), isPresented: $showBatchDeleteConfirmation) {
            Button(localizationManager.text("common.delete"), role: .destructive) {
                applyBatchDelete()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("tasks.batch.delete_confirmation_body"))
        }
    }
    
    /// Move all selected tasks to a specific date (user-invoked, explicit).
    fileprivate func applyBatchMove(to date: Date) {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for var task in tasks {
            let merged = mergedDueDate(newDay: date, from: task)
            task.dueDate = merged.date
            task.hasDueTime = merged.hasTime
            task.modifiedAt = Date()
            todoStore.updateItem(task)
            
            // Propagate to Reminders/Calendar only for managed items; this is user-initiated.
            if permissionsManager.isRemindersAuthorized,
               task.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(task) }
            }
        }
        clearTaskSelection()
    }
    
    /// Clear due date on selected tasks.
    fileprivate func applyBatchClearDate() {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for var task in tasks {
            task.dueDate = nil
            task.hasDueTime = false
            task.modifiedAt = Date()
            todoStore.updateItem(task)
            if permissionsManager.isRemindersAuthorized,
               task.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(task) }
            }
        }
        clearTaskSelection()
    }
    
    /// Atomic delete for selected tasks.
    fileprivate func applyBatchDelete() {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for task in tasks {
            todoStore.deleteItem(task)
        }
        clearTaskSelection()
    }
    
    private func selectedTasks() -> [TodoItem] {
        todoStore.items.filter { selectedTaskIDs.contains($0.id) }
    }
    
    private func clearTaskSelection() {
        selectedTaskIDs.removeAll()
        lastSelectedTaskID = nil
    }
}

#Preview {
    MainActor.assumeIsolated {
        let store = TodoStore()
        let planningStore = PlanningStore()
        store.attachPlanningStore(planningStore)
        let sync = RemindersSync(permissionsManager: .shared)
        sync.setTodoStore(store)

        return TodoListView(
            todoStore: store,
            planningStore: planningStore,
            remindersSync: sync,
            permissionsManager: .shared
        )
        .frame(width: 700, height: 600)
    }
}
