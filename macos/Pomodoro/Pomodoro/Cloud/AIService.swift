import Foundation
import FirebaseFunctions

@MainActor
final class AIService {
    struct TaskBreakdownRequest: Encodable {
        let task: String
        let deadline: String
        let estimatedHours: Int
    }

    struct TaskPlanningRequest: Encodable {
        let tasks: [String]
        let deadline: String
        let estimatedHours: Int
    }

    struct AIPlanningResponse: Decodable {
        struct Subtask: Decodable {
            let title: String
            let pomodoros: Int
        }

        let taskTitle: String
        let subtasks: [Subtask]
        let estimatedPomodoros: Int
    }

    typealias TaskBreakdownResponse = AIPlanningResponse
    typealias TaskPlanningResponse = AIPlanningResponse

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
            estimatedHours: estimatedHours
        )
        let callable = functions.httpsCallable("taskPlanning")
        let payload: [String: Any] = [
            "tasks": request.tasks,
            "deadline": request.deadline,
            "estimatedHours": request.estimatedHours
        ]

        print("[AIService] Calling callable taskPlanning in us-central1 for \(tasks.count) tasks")
        let result = try await callable.call(payload)
        print("[AIService] taskPlanning response received")
        return try decodeAIPlanningResponse(from: result.data)
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
}
