import Foundation
import FirebaseFunctions
import FirebaseAuth
import EventKit

@MainActor
final class AIService {
    struct TaskBreakdownRequest: Encodable {
        let task: String
        let deadline: String
        let estimatedHours: Int
    }

    struct TaskPlanningRequest: Encodable {
        struct PresetPayload: Encodable {
            let id: String
            let workMinutes: Int
            let shortBreakMinutes: Int
        }

        let tasks: [String]
        let deadline: String
        let estimatedHours: Int
        let pomodoroPresets: [PresetPayload]
    }

    struct AIPlanningResponse: Decodable {
        struct Subtask: Decodable {
            let title: String
            let pomodoros: Int
            let pomodoroPreset: String?
        }

        let taskTitle: String
        let subtasks: [Subtask]
        let estimatedPomodoros: Int
    }

    typealias TaskBreakdownResponse = AIPlanningResponse
    typealias TaskPlanningResponse = AIPlanningResponse

    struct FreeSlot: Codable, Equatable {
        let start: Date
        let end: Date
    }

    struct AIScheduleResponse: Codable {
        let success: Bool
        let schedule: [ScheduleBlock]
        let freeSlots: [FreeSlot]

        init(success: Bool, schedule: [ScheduleBlock], freeSlots: [FreeSlot] = []) {
            self.success = success
            self.schedule = schedule
            self.freeSlots = freeSlots
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
            schedule = try container.decodeIfPresent([ScheduleBlock].self, forKey: .schedule) ?? []
            freeSlots = try container.decodeIfPresent([FreeSlot].self, forKey: .freeSlots) ?? []
        }
    }

    struct ScheduleBlock: Codable {
        let taskId: String
        let taskTitle: String
        let eventId: String
        let start: Date
        let end: Date
        let pomodoros: Int
        let pomodoroPreset: String?
        let calendarWritable: Bool

        init(
            taskId: String,
            taskTitle: String,
            eventId: String = "",
            start: Date,
            end: Date,
            pomodoros: Int,
            pomodoroPreset: String? = nil,
            calendarWritable: Bool = true
        ) {
            self.taskId = taskId
            self.taskTitle = taskTitle
            self.eventId = eventId
            self.start = start
            self.end = end
            self.pomodoros = pomodoros
            self.pomodoroPreset = pomodoroPreset
            self.calendarWritable = calendarWritable
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskId = try container.decode(String.self, forKey: .taskId)
            taskTitle = try container.decode(String.self, forKey: .taskTitle)
            eventId = try container.decodeIfPresent(String.self, forKey: .eventId) ?? ""
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            pomodoros = try container.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 1
            pomodoroPreset = try container.decodeIfPresent(String.self, forKey: .pomodoroPreset)
            calendarWritable = try container.decodeIfPresent(Bool.self, forKey: .calendarWritable) ?? true
        }
    }

    struct SchedulingPreferences {
        let pomodoroLength: Int
        let breakLength: Int
        let workingHoursStart: String
        let workingHoursEnd: String

        init(
            pomodoroLength: Int? = nil,
            breakLength: Int? = nil,
            workingHoursStart: String = "08:00",
            workingHoursEnd: String = "22:00"
        ) {
            let fallbackPreset = Preset.shortestBuiltIn
            self.pomodoroLength = pomodoroLength ?? max(1, fallbackPreset.durationConfig.workDuration / 60)
            self.breakLength = breakLength ?? max(0, fallbackPreset.durationConfig.shortBreakDuration / 60)
            self.workingHoursStart = workingHoursStart
            self.workingHoursEnd = workingHoursEnd
        }
    }

    private struct CalendarRescheduleRequest: Encodable {
        struct TaskPayload: Encodable {
            let id: String
            let title: String
            let estimatedPomodoros: Int
            let priority: Int
            let deadline: String?
        }

        struct CalendarEventPayload: Encodable {
            let eventId: String
            let title: String
            let start: Date
            let end: Date
            let calendarWritable: Bool
            let isSubscribed: Bool
            let subscribed: Bool
            let readOnly: Bool
            let calendarReadOnly: Bool
        }

        struct PreferencesPayload: Encodable {
            struct PresetPayload: Encodable {
                let id: String
                let workMinutes: Int
                let shortBreakMinutes: Int
            }

            let pomodoroLength: Int
            let breakLength: Int
            let workingHoursStart: String
            let workingHoursEnd: String
            let pomodoroPresets: [PresetPayload]
        }

        let uid: String?
        let tasks: [TaskPayload]
        let calendarEvents: [CalendarEventPayload]
        let freeSlots: [FreeSlot]
        let preferences: PreferencesPayload
        let preferredDayEnd: Date?
        /// When set to "today" the cloud function clamps scheduling to today only.
        let rescheduleScope: String?
    }

    enum AIServiceError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "AI planning returned an invalid response."
            }
        }
    }

    static let shared = AIService()

    private let functions: Functions

    private init(functions: Functions? = nil) {
        if let functions {
            self.functions = functions
        } else {
            self.functions = Functions.functions(region: "us-central1")
        }
    }

    func taskBreakdown(task: String, deadline: String, estimatedHours: Int) async throws -> TaskBreakdownResponse {
        let request = TaskBreakdownRequest(
            task: task,
            deadline: deadline,
            estimatedHours: estimatedHours
        )
        let callable = functions.httpsCallable("taskBreakdown")
        let payload: [String: Any] = [
            "task": request.task,
            "deadline": request.deadline,
            "estimatedHours": request.estimatedHours
        ]

        print("[AIService] Calling callable taskBreakdown in us-central1 for task: \(task)")
        let result = try await callable.call(payload)
        print("[AIService] taskBreakdown response received")
        return try decodeAIPlanningResponse(from: result.data)
    }

    func taskPlanning(tasks: [String], deadline: String, estimatedHours: Int) async throws -> TaskPlanningResponse {
        let request = TaskPlanningRequest(
            tasks: tasks,
            deadline: deadline,
            estimatedHours: estimatedHours,
            pomodoroPresets: Self.schedulerPresetPayloads
        )
        let callable = functions.httpsCallable("taskPlanning")
        let payload: [String: Any] = [
            "tasks": request.tasks,
            "deadline": request.deadline,
            "estimatedHours": request.estimatedHours,
            "pomodoroPresets": request.pomodoroPresets.map { [
                "id": $0.id,
                "workMinutes": $0.workMinutes,
                "shortBreakMinutes": $0.shortBreakMinutes
            ] }
        ]

        print("[AIService] Calling callable taskPlanning in us-central1 for \(tasks.count) tasks")
        let result = try await callable.call(payload)
        print("[AIService] taskPlanning response received")
        return try decodeAIPlanningResponse(from: result.data)
    }

    func calendarReschedule(
        tasks: [TodoItem],
        events: [EKEvent],
        freeSlots: [FreeSlot],
        preferences: SchedulingPreferences? = nil,
        preferredDayEnd: Date? = nil
    ) async throws -> AIScheduleResponse {
        let effectivePreferences = preferences ?? SchedulingPreferences()
        let uid = Auth.auth().currentUser?.uid
        let requestBody = CalendarRescheduleRequest(
            uid: uid,
            tasks: tasks.map { task in
                CalendarRescheduleRequest.TaskPayload(
                    id: task.id.uuidString,
                    title: task.title,
                    estimatedPomodoros: task.pomodoroEstimate ?? 1,
                    priority: max(1, task.priority.rawValue),
                    deadline: task.dueDate?.ISO8601Format()
                )
            },
            calendarEvents: events.compactMap { event in
                guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
                let isSubscribed = event.calendar.type == .subscription
                let calendarWritable = event.calendar.allowsContentModifications && !isSubscribed
                return CalendarRescheduleRequest.CalendarEventPayload(
                    eventId: event.eventIdentifier ?? "",
                    title: event.title ?? "Busy",
                    start: startDate,
                    end: endDate,
                    calendarWritable: calendarWritable,
                    isSubscribed: isSubscribed,
                    subscribed: isSubscribed,
                    readOnly: !calendarWritable,
                    calendarReadOnly: !calendarWritable
                )
            },
            freeSlots: freeSlots,
            preferences: CalendarRescheduleRequest.PreferencesPayload(
                pomodoroLength: effectivePreferences.pomodoroLength,
                breakLength: effectivePreferences.breakLength,
                workingHoursStart: effectivePreferences.workingHoursStart,
                workingHoursEnd: effectivePreferences.workingHoursEnd,
                pomodoroPresets: Self.schedulerPresetPreferencePayloads
            ),
            preferredDayEnd: preferredDayEnd,
            rescheduleScope: "today"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(requestBody)
        if let requestString = String(data: body, encoding: .utf8) {
            print("[AIService] generateCalendarSchedule payload: \(requestString)")
        }

        let jsonObject = try JSONSerialization.jsonObject(with: body)
        guard let payload = jsonObject as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let options = HTTPSCallableOptions(requireLimitedUseAppCheckTokens: false)
        let callable = functions.httpsCallable(
            "generateCalendarSchedule",
            options: options
        )
        callable.timeoutInterval = 60
        print("[AIService] Calling callable generateCalendarSchedule in us-central1")
        let result = try await callable.call(payload)
        if let data = result.data as? [String: Any] {
            print("[AIService] callable response: \(data)")
        }

        return try decodeCalendarScheduleResponse(from: result.data)
    }

    private func decodeAIPlanningResponse(from data: Any) throws -> AIPlanningResponse {
        let rawObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rawObject = nested
        } else {
            rawObject = data
        }

        guard JSONSerialization.isValidJSONObject(rawObject) else {
            throw AIServiceError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rawObject)
        return try JSONDecoder().decode(AIPlanningResponse.self, from: responseData)
    }

    private func decodeCalendarScheduleResponse(from data: Any) throws -> AIScheduleResponse {
        let rawObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rawObject = nested
        } else {
            rawObject = data
        }

        guard JSONSerialization.isValidJSONObject(rawObject) else {
            throw AIServiceError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rawObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            if let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }

        if let envelope = try? decoder.decode(CalendarScheduleEnvelope.self, from: responseData) {
            return envelope.data
        }
        return try decoder.decode(AIScheduleResponse.self, from: responseData)
    }

    private struct CalendarScheduleEnvelope: Decodable {
        let data: AIScheduleResponse
    }

    private static var schedulerPresetPayloads: [TaskPlanningRequest.PresetPayload] {
        Preset.builtIn.map {
            TaskPlanningRequest.PresetPayload(
                id: $0.id,
                workMinutes: max(1, $0.durationConfig.workDuration / 60),
                shortBreakMinutes: max(0, $0.durationConfig.shortBreakDuration / 60)
            )
        }
    }

    private static var schedulerPresetPreferencePayloads: [CalendarRescheduleRequest.PreferencesPayload.PresetPayload] {
        Preset.builtIn.map {
            CalendarRescheduleRequest.PreferencesPayload.PresetPayload(
                id: $0.id,
                workMinutes: max(1, $0.durationConfig.workDuration / 60),
                shortBreakMinutes: max(0, $0.durationConfig.shortBreakDuration / 60)
            )
        }
    }
}
