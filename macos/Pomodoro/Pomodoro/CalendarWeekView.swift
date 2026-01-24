import SwiftUI
import EventKit

/// Week calendar laid out in 7 side-by-side day cards.
struct CalendarWeekView: View {
    let startOfWeek: Date
    let events: [EKEvent]
    
    private let calendar = Calendar.current
    
    private var days: [Date] {
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startOfWeek)) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    
    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 12) {
                ForEach(days, id: \.self) { day in
                    dayColumn(for: day, availableHeight: proxy.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
    }
    
    @ViewBuilder
    private func dayColumn(for day: Date, availableHeight: CGFloat) -> some View {
        let dayEvents = eventsForDay(day)
        let isToday = calendar.isDateInToday(day)
        let dayName = weekdayString(day)
        let dateLabel = dateString(day)
        
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dateLabel)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                Spacer()
                if isToday {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            
            Divider()
                .opacity(0.35)
            
            VStack(alignment: .leading, spacing: 8) {
                if dayEvents.isEmpty {
                    Text("No events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(dayEvents, id: \.eventIdentifier) { event in
                        eventRow(event)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday ? Color.blue.opacity(0.08) : Color.primary.opacity(0.05))
        )
    }
    
    private func eventsForDay(_ day: Date) -> [EKEvent] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }
    
    @ViewBuilder
    private func eventRow(_ event: EKEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 8, height: 8)
                Text(event.title ?? "Untitled")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(timeRange(event))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(10)
    }
    
    private func timeRange(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        if event.isAllDay {
            return "All day"
        }
        return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
    }
    
    private func weekdayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
