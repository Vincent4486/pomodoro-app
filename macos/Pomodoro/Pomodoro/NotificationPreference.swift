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
            return LocalizationManager.shared.text("notification.off")
        case .silent:
            return LocalizationManager.shared.text("notification.silent_banner")
        case .sound:
            return LocalizationManager.shared.text("notification.banner_sound")
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
            return LocalizationManager.shared.text("notification.delivery.system")
        case .inApp:
            return LocalizationManager.shared.text("notification.delivery.in_app")
        }
    }

    var detail: String {
        switch self {
        case .system:
            return LocalizationManager.shared.text("notification.delivery.system.detail")
        case .inApp:
            return LocalizationManager.shared.text("notification.delivery.in_app.detail")
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
            return LocalizationManager.shared.text("notification.off")
        case .oneMinute:
            return LocalizationManager.shared.text("notification.reminder.one_minute")
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
