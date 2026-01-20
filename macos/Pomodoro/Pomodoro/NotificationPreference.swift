//
//  NotificationPreference.swift
//  Pomodoro
//
//  Created by OpenAI on 2025-02-01.
//

import Foundation

enum NotificationPreference: String, CaseIterable, Identifiable {
    case off
    case silent
    case sound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .silent:
            return "Silent banner"
        case .sound:
            return "Banner + sound"
        }
    }
}

enum NotificationDeliveryStyle: String, CaseIterable, Identifiable {
    case system
    case inApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System Notifications"
        case .inApp:
            return "In-App Popup"
        }
    }

    var detail: String {
        switch self {
        case .system:
            return "Use macOS banners or alerts."
        case .inApp:
            return "Show a confirmation popup inside the app window."
        }
    }
}

enum ReminderPreference: String, CaseIterable, Identifiable {
    case off
    case oneMinute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .oneMinute:
            return "1 minute before"
        }
    }

    var leadTimeSeconds: Int {
        switch self {
        case .off:
            return 0
        case .oneMinute:
            return 60
        }
    }
}
