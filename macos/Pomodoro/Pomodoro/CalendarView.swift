import SwiftUI
import EventKit

/// Calendar view showing time-based events.
/// Blocked when unauthorized with explanation and enable button.
struct CalendarView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var permissionsManager: PermissionsManager
    
    @State private var selectedView: ViewType = .today
    
    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    enum ViewType {
        case today
        case week
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
    }
    
    private var authorizedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Text("Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your time-based events and schedules")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            
            // View selector
            Picker("View", selection: $selectedView) {
                Text("Today").tag(ViewType.today)
                Text("Week").tag(ViewType.week)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .onChange(of: selectedView) { _ in
                Task {
                    await loadEvents()
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
                Text("Calendar Unavailable")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Calendar access is required to view your events and schedules.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Click the button below to request access.")
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
                Label("Request Calendar Access", systemImage: "calendar")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: 520, minHeight: 420, alignment: .center)
        .alert("Calendar Access Denied", isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button("Open Settings") {
                permissionsManager.openSystemSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Calendar access is required to view your events. You can enable it in System Settings → Privacy & Security → Calendar.")
        }
    }
    
    @ViewBuilder
    private func eventsContent(maxWidth: CGFloat) -> some View {
        if calendarManager.isLoading {
            ProgressView("Loading events...")
                .padding(32)
                .frame(maxWidth: maxWidth, alignment: .leading)
        } else if calendarManager.events.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                
                Text("No events")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("You have no events in this time period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: maxWidth, alignment: .center)
            .padding(48)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(calendarManager.events, id: \.eventIdentifier) { event in
                    eventRow(event)
                }
            }
            .padding(16)
            .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func eventRow(_ event: EKEvent) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled")
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text(formatEventTime(event))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if let calendar = event.calendar {
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text(calendar.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay {
            return "All day"
        } else {
            let start = Self.eventTimeFormatter.string(from: event.startDate)
            let end = Self.eventTimeFormatter.string(from: event.endDate)
            return "\(start) - \(end)"
        }
    }
    
    private func loadEvents() async {
        switch selectedView {
        case .today:
            await calendarManager.fetchTodayEvents()
        case .week:
            await calendarManager.fetchWeekEvents()
        }
    }
}

#Preview {
    CalendarView(
        calendarManager: CalendarManager(permissionsManager: .shared),
        permissionsManager: .shared
    )
    .frame(width: 700, height: 600)
}
