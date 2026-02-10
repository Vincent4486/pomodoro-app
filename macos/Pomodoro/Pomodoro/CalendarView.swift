import SwiftUI
import EventKit
import AppKit

/// Calendar view showing time-based events and allowing event creation.
/// Blocked when unauthorized with explanation and enable button.
struct CalendarView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var todoStore: TodoStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    @State private var selectedView: ViewType = .day
    @State private var anchorDate: Date = Date()
    @State private var selectedEventIDs: Set<String> = []
    @State private var lastSelectedEventID: String?
    @State private var batchEventDate: Date = Date()
    @State private var showDeleteEventsConfirmation = false
    @State private var batchEventWarning: String?
    
    // New event sheet state
    @State private var showingAddEvent = false
    @State private var newEventTitle: String = ""
    @State private var newEventStart: Date = Date()
    @State private var newEventDurationMinutes: Int = 60
    @State private var newEventNotes: String = ""
    @State private var addEventError: String?
    
    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
        return formatter
    }()
    
    enum ViewType {
        case day
        case week
        case month
        
        var title: String {
            switch self {
            case .day: return LocalizationManager.shared.text("calendar.view.day")
            case .week: return LocalizationManager.shared.text("calendar.view.week")
            case .month: return LocalizationManager.shared.text("calendar.view.month")
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if permissionsManager.isCalendarAuthorized {
                authorizedContent
            } else {
                unauthorizedContent
            }
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 900, minHeight: 520, alignment: .top)
        .onAppear {
            permissionsManager.refreshCalendarStatus()
            if permissionsManager.isCalendarAuthorized {
                Task {
                    await loadEvents()
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(
                title: $newEventTitle,
                startDate: $newEventStart,
                durationMinutes: $newEventDurationMinutes,
                notes: $newEventNotes,
                errorMessage: addEventError,
                onCancel: {
                    showingAddEvent = false
                    addEventError = nil
                },
                onSave: {
                    Task { await saveEvent() }
                }
            )
        }
    }
    
    private var authorizedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizationManager.text("calendar.title"))
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text(localizationManager.text("calendar.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 12) {
                    Picker(localizationManager.text("calendar.view"), selection: $selectedView) {
                        Text(localizationManager.text("calendar.view.day")).tag(ViewType.day)
                        Text(localizationManager.text("calendar.view.week")).tag(ViewType.week)
                        Text(localizationManager.text("calendar.view.month")).tag(ViewType.month)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .onChange(of: selectedView) { _, _ in
                        Task { await loadEvents() }
                    }
                    
                    DatePicker(
                        "",
                        selection: $anchorDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .onChange(of: anchorDate) { _, _ in
                        Task { await loadEvents() }
                    }
                    
                    Spacer()
                    
                    Button {
                        prepareNewEventDefaults()
                        showingAddEvent = true
                    } label: {
                        Label(localizationManager.text("calendar.add_event"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button {
                        Task { await loadEvents() }
                    } label: {
                        Label(localizationManager.text("common.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
                if selectedEventIDs.count > 1 {
                    batchEventActionsBar
                }
            }
            
            // Events list constrained to the available detail height
            GeometryReader { proxy in
                ScrollView {
                    eventsContent(maxWidth: proxy.size.width)
                }
                .frame(height: max(proxy.size.height, 280))
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 860, alignment: .leading)
    }
    
    private var unauthorizedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                Text(localizationManager.text("calendar.unavailable.title"))
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(localizationManager.text("calendar.unavailable.body"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(localizationManager.text("calendar.unavailable.cta"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 400)
            
            Button(action: {
                Task {
                    await permissionsManager.requestCalendarPermission()
                }
            }) {
                Label(localizationManager.text("calendar.request_access"), systemImage: "calendar")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: 520, minHeight: 420, alignment: .center)
        .alert(localizationManager.text("calendar.access_denied.title"), isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("calendar.access_denied.body"))
        }
    }
    
    @ViewBuilder
    private func eventsContent(maxWidth: CGFloat) -> some View {
        if calendarManager.isLoading {
            ProgressView(localizationManager.text("calendar.loading"))
                .padding(32)
                .frame(maxWidth: maxWidth, alignment: .leading)
        } else {
            switch selectedView {
            case .day:
                dayContent(maxWidth: maxWidth)
            case .week:
                WeekCalendarView(
                    days: daysInWeek(from: anchorDate),
                    events: calendarManager.events,
                    tasks: todoStore.items
                )
                .frame(maxWidth: maxWidth, alignment: .leading)
            case .month:
                monthContent(maxWidth: maxWidth)
            }
        }
    }
    
    @ViewBuilder
    private func dayContent(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            daySummary
            dayBlocks
        }
        .frame(maxWidth: maxWidth, alignment: Alignment.leading)
        .padding(Edge.Set.horizontal, 8)
    }
    
    @ViewBuilder
    private func monthContent(maxWidth: CGFloat) -> some View {
        CalendarMonthView(
            date: anchorDate,
            events: calendarManager.events
        )
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
    
    private func daysInWeek(from date: Date) -> [Date] {
        var days: [Date] = []
        var calendar = Calendar.current
        calendar.locale = localizationManager.effectiveLocale
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        guard let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfDay) else {
            return days
        }
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: startOfWeek) {
                days.append(day)
            }
        }
        return days
    }
    
    private func loadEvents() async {
        switch selectedView {
        case .day:
            await calendarManager.fetchDayEvents(for: anchorDate)
        case .week:
            await calendarManager.fetchWeekEvents(containing: anchorDate)
        case .month:
            await calendarManager.fetchMonthEvents(containing: anchorDate)
        }
    }

    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay {
            return localizationManager.text("calendar.all_day")
        }
        Self.eventTimeFormatter.locale = localizationManager.effectiveLocale
        let start = Self.eventTimeFormatter.string(from: event.startDate)
        let end = Self.eventTimeFormatter.string(from: event.endDate)
        return "\(start) - \(end)"
    }

    // MARK: - Day helpers

    private var daySummary: some View {
        let todayEvents = events(for: anchorDate)
        let todayTasks = tasks(for: anchorDate)
        let totalMinutes = todayEvents.reduce(0) { partial, event in
            partial + max(0, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("calendar.today_summary"))
                .font(.headline)
            HStack(spacing: 12) {
                summaryPill(title: localizationManager.text("calendar.blocks"), value: "\(todayEvents.count)")
                summaryPill(title: localizationManager.text("calendar.tasks"), value: "\(todayTasks.count)")
                summaryPill(title: localizationManager.text("calendar.planned_mins"), value: "\(totalMinutes)")
            }
        }
    }

    private var dayBlocks: some View {
        let todayEvents = events(for: anchorDate)
        let todayTasks = tasks(for: anchorDate)

        return ScrollView {
            if todayEvents.isEmpty && todayTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(localizationManager.text("calendar.no_blocks_today"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !todayEvents.isEmpty {
                        Text(localizationManager.text("calendar.time_blocks"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(todayEvents, id: \.eventIdentifier) { event in
                            blockCard(event, events: todayEvents)
                        }
                    }

                    if !todayTasks.isEmpty {
                        Text(localizationManager.text("calendar.tasks"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(todayTasks) { task in
                            taskCard(task)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .top)
    }

    // MARK: - Card builders

    private func blockCard(_ event: EKEvent, events: [EKEvent]) -> some View {
        let isSelected = event.eventIdentifier.map { selectedEventIDs.contains($0) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            Text(event.title ?? localizationManager.text("common.untitled"))
                .font(.headline)
            Text(formatEventTime(event))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let calendar = event.calendar {
                Text(calendar.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture(perform: {
            handleEventSelection(event, allEvents: events)
        })
    }

    private func taskCard(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .strikethrough(item.isCompleted)
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let due = item.dueDate {
                Text(formattedTaskDue(item: item, due: due))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    // MARK: - Selection helpers

    private func handleEventSelection(_ event: EKEvent, allEvents: [EKEvent]) {
        guard let id = event.eventIdentifier else { return }
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)
        
        if isShift, let anchor = lastSelectedEventID,
           let anchorIndex = allEvents.firstIndex(where: { $0.eventIdentifier == anchor }),
           let targetIndex = allEvents.firstIndex(where: { $0.eventIdentifier == id }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangeIDs = allEvents[lower...upper].compactMap { $0.eventIdentifier }
            selectedEventIDs.formUnion(rangeIDs)
            lastSelectedEventID = id
            return
        }
        
        if isCommand {
            if selectedEventIDs.contains(id) {
                selectedEventIDs.remove(id)
            } else {
                selectedEventIDs.insert(id)
                lastSelectedEventID = id
            }
            return
        }
        
        // Default single selection
        selectedEventIDs = [id]
        lastSelectedEventID = id
    }
    
    @ViewBuilder
    private var batchEventActionsBar: some View {
        let editableSelection = selectedEventIDs.compactMap { id in
            calendarManager.events.first(where: { $0.eventIdentifier == id })
        }.filter { $0.calendar.allowsContentModifications }
        let hasReadOnly = selectedEventIDs.count != editableSelection.count
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(localizationManager.format("common.selected_count", selectedEventIDs.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if hasReadOnly {
                    Text(localizationManager.text("calendar.read_only_warning"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                DatePicker(
                    localizationManager.text("common.move_to"),
                    selection: $batchEventDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                
                Button {
                    Task { await applyEventMove(to: batchEventDate, editable: editableSelection) }
                } label: {
                    Label(localizationManager.text("common.move"), systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .disabled(editableSelection.isEmpty)
                
                Button(role: .destructive) {
                    showDeleteEventsConfirmation = true
                } label: {
                    Label(localizationManager.text("common.delete"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(editableSelection.isEmpty)
            }
            
            if let warning = batchEventWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .alert(localizationManager.format("calendar.delete_events.confirmation", editableSelection.count), isPresented: $showDeleteEventsConfirmation) {
            Button(localizationManager.text("common.delete"), role: .destructive) {
                Task { await applyEventDelete(editable: editableSelection) }
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("calendar.delete_events.read_only_note"))
        }
    }
    
    private func applyEventMove(to date: Date, editable: [EKEvent]) async {
        guard !editable.isEmpty else { return }
        let ids = editable.compactMap { $0.eventIdentifier }
        do {
            try await calendarManager.moveEvents(with: ids, to: date)
            selectedEventIDs.removeAll()
            lastSelectedEventID = nil
            await loadEvents()
        } catch {
            batchEventWarning = localizationManager.format("calendar.error.move_all_failed", error.localizedDescription)
            print("[CalendarView] move events failed: \(error)")
        }
    }
    
    private func applyEventDelete(editable: [EKEvent]) async {
        guard !editable.isEmpty else { return }
        let ids = editable.compactMap { $0.eventIdentifier }
        do {
            try await calendarManager.deleteEvents(with: ids)
            selectedEventIDs.removeAll()
            lastSelectedEventID = nil
            await loadEvents()
        } catch {
            batchEventWarning = localizationManager.format("calendar.error.delete_all_failed", error.localizedDescription)
            print("[CalendarView] delete events failed: \(error)")
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Data helpers

    private func events(for day: Date) -> [EKEvent] {
        let calendar = Calendar.current
        return calendarManager.events
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func tasks(for day: Date) -> [TodoItem] {
        let calendar = Calendar.current
        return todoStore.items.filter { item in
            if let due = item.dueDate {
                return calendar.isDate(due, inSameDayAs: day)
            }
            return false
        }
    }

    private func formattedTaskDue(item: TodoItem, due: Date) -> String {
        Self.shortDayFormatter.locale = localizationManager.effectiveLocale
        Self.eventTimeFormatter.locale = localizationManager.effectiveLocale
        let day = Self.shortDayFormatter.string(from: due)
        let suffix = item.hasDueTime ? " • \(Self.eventTimeFormatter.string(from: due))" : ""
        return day + suffix
    }
    
    private func prepareNewEventDefaults() {
        newEventTitle = ""
        newEventNotes = ""
        newEventDurationMinutes = 60
        
        // Align start time to the selected date, keeping the current hour.
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = minute >= 30 ? 30 : 0
        newEventStart = calendar.date(
            bySettingHour: hour,
            minute: roundedMinute,
            second: 0,
            of: anchorDate
        ) ?? anchorDate
    }
    
    private func saveEvent() async {
        let endDate = newEventStart.addingTimeInterval(Double(newEventDurationMinutes * 60))
        do {
            try await calendarManager.createEvent(
                title: newEventTitle.isEmpty ? localizationManager.text("calendar.new_event_default_title") : newEventTitle,
                startDate: newEventStart,
                endDate: endDate,
                notes: newEventNotes.isEmpty ? nil : newEventNotes
            )
            addEventError = nil
            showingAddEvent = false
            await loadEvents()
        } catch {
            addEventError = error.localizedDescription
        }
    }
}

private struct AddEventSheet: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var durationMinutes: Int
    @Binding var notes: String
    
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text(localizationManager.text("calendar.add_event"))
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField(localizationManager.text("common.title"), text: $title)
                    .textFieldStyle(.roundedBorder)
                
                DatePicker(localizationManager.text("common.start"), selection: $startDate)
                
                HStack {
                    Text(localizationManager.text("common.duration"))
                    Spacer()
                    Stepper(localizationManager.format("common.duration_minutes_format", durationMinutes), value: $durationMinutes, in: 15...480, step: 15)
                }
                
                TextField(localizationManager.text("common.notes_optional"), text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button(localizationManager.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(localizationManager.text("common.save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

#Preview {
    CalendarView(
        calendarManager: CalendarManager(permissionsManager: .shared),
        permissionsManager: .shared,
        todoStore: TodoStore()
    )
    .frame(width: 700, height: 600)
}
