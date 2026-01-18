import Foundation

enum PomodoroMode {
    case idle
    case work
    case break
    case longBreak
}

extension PomodoroMode {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .work:
            return "Focus"
        case .break:
            return "Break"
        case .longBreak:
            return "Long Break"
        }
    }
}
