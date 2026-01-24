import Foundation
import EventKit

/// Primary task data model for the app.
/// Represents both internal todos and synced Apple Reminders.
struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var isCompleted: Bool
    var dueDate: Date?
    var priority: Priority
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String]
    
    /// Optional reference to Apple Reminders EKReminder identifier
    /// Only populated when synced with Apple Reminders
    var remindersIdentifier: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, notes, isCompleted, dueDate, priority, createdAt, modifiedAt, tags, remindersIdentifier
    }
    
    enum Priority: Int, Codable, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
        
        var displayName: String {
            switch self {
            case .none: return "None"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        priority: Priority = .none,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        tags: [String] = [],
        remindersIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.remindersIdentifier = remindersIdentifier
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        remindersIdentifier = try container.decodeIfPresent(String.self, forKey: .remindersIdentifier)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(priority, forKey: .priority)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
        try container.encodeIfPresent(remindersIdentifier, forKey: .remindersIdentifier)
    }
    
    mutating func markComplete(_ completed: Bool) {
        isCompleted = completed
        modifiedAt = Date()
    }
    
    mutating func update(title: String? = nil, notes: String? = nil, dueDate: Date? = nil, priority: Priority? = nil) {
        if let title = title { self.title = title }
        if let notes = notes { self.notes = notes }
        if let dueDate = dueDate { self.dueDate = dueDate }
        if let priority = priority { self.priority = priority }
        modifiedAt = Date()
    }
}
