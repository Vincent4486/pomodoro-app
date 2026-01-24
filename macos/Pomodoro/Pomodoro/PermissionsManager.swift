import Foundation
import AppKit
import Combine
import EventKit
import UserNotifications

/// Centralized permissions manager for Notifications, Calendar, and Reminders.
/// Provides authorization status checks and system settings opening.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    // System Settings URL
    private static let systemSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy"
    
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var calendarStatus: EKAuthorizationStatus = .notDetermined
    @Published var remindersStatus: EKAuthorizationStatus = .notDetermined
    
    // Alert state for denied permissions
    @Published var showCalendarDeniedAlert = false
    @Published var showRemindersDeniedAlert = false
    
    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {
        refreshAllStatuses()
    }
    
    // MARK: - Status Refresh
    
    /// Refresh all permission statuses
    func refreshAllStatuses() {
        Task {
            await refreshNotificationStatus()
            refreshCalendarStatus()
            refreshRemindersStatus()
        }
    }
    
    func refreshNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
    
    func refreshCalendarStatus() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    func refreshRemindersStatus() {
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    }
    
    // MARK: - Permission Requests
    
    /// Request notification permission - shows system dialog if notDetermined, alert if denied/restricted
    func requestNotificationPermission() async {
        // Check current status
        await refreshNotificationStatus()
        
        switch notificationStatus {
        case .notDetermined:
            // Request permission - this will show the system dialog
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshNotificationStatus()
                
                if !granted {
                    // User denied in the dialog - no additional action needed
                    print("[PermissionsManager] Notification permission denied by user")
                }
            } catch {
                print("[PermissionsManager] Notification request failed: \(error)")
            }
            
        case .denied:
            // Already denied - inform user via alert (handled in UI)
            print("[PermissionsManager] Notification permission already denied")
            // Note: Notifications don't have a dedicated alert flag since they're handled differently in the UI
            // but the pattern is consistent with Calendar/Reminders
            
        case .authorized, .provisional, .ephemeral:
            // Already authorized
            print("[PermissionsManager] Notification permission already authorized")
            
        @unknown default:
            print("[PermissionsManager] Unknown notification status")
        }
    }
    
    /// Request calendar permission - shows system dialog if notDetermined, sets alert flag if denied/restricted
    func requestCalendarPermission() async {
        // Check current status
        refreshCalendarStatus()

        if #available(macOS 14.0, *) {
            switch calendarStatus {
            case .notDetermined:
                let granted = await requestCalendarAccess()
                refreshCalendarStatus()
                if !granted { showCalendarDeniedAlert = true }
            case .denied, .restricted:
                showCalendarDeniedAlert = true
            case .fullAccess, .writeOnly:
                break
            default:
                break
            }
        } else {
            switch calendarStatus {
            case .notDetermined:
                let granted = await requestCalendarAccess()
                refreshCalendarStatus()
                if !granted { showCalendarDeniedAlert = true }
            case .denied, .restricted:
                showCalendarDeniedAlert = true
            case .authorized:
                break
            default:
                break
            }
        }
    }
    
    /// Request reminders permission - shows system dialog if notDetermined, sets alert flag if denied/restricted
    func requestRemindersPermission() async {
        // Check current status
        refreshRemindersStatus()

        if #available(macOS 14.0, *) {
            switch remindersStatus {
            case .notDetermined:
                let granted = await requestRemindersAccess()
                refreshRemindersStatus()
                if !granted { showRemindersDeniedAlert = true }
            case .denied, .restricted:
                showRemindersDeniedAlert = true
            case .fullAccess, .writeOnly:
                break
            default:
                break
            }
        } else {
            switch remindersStatus {
            case .notDetermined:
                let granted = await requestRemindersAccess()
                refreshRemindersStatus()
                if !granted { showRemindersDeniedAlert = true }
            case .denied, .restricted:
                showRemindersDeniedAlert = true
            case .authorized:
                break
            default:
                break
            }
        }
    }
    
    // MARK: - Legacy Methods (Deprecated)
    
    /// Register notification intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestNotificationPermission() instead")
    func registerNotificationIntent() async {
        await requestNotificationPermission()
    }
    
    /// Register calendar intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestCalendarPermission() instead")
    func registerCalendarIntent() async {
        await requestCalendarPermission()
    }
    
    /// Register reminders intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestRemindersPermission() instead")
    func registerRemindersIntent() async {
        await requestRemindersPermission()
    }
    
    // MARK: - System Settings
    
    /// Opens macOS System Settings app
    /// This is the primary UX for permission management
    func openSystemSettings() {
        if let url = URL(string: Self.systemSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private helpers

    private func requestCalendarAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestRemindersAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    // MARK: - Status Helpers
    
    var isNotificationsAuthorized: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }
    
    var isCalendarAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return calendarStatus == .fullAccess || calendarStatus == .writeOnly
        } else {
            return calendarStatus == .authorized
        }
    }
    
    var isRemindersAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return remindersStatus == .fullAccess || remindersStatus == .writeOnly
        } else {
            return remindersStatus == .authorized
        }
    }
    
    var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .authorized, .provisional:
            return "Authorized"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
    
    var calendarStatusText: String {
        if #available(macOS 14.0, *) {
            switch calendarStatus {
            case .notDetermined: return "Not Requested"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .fullAccess: return "Full Access"
            case .writeOnly: return "Write Only"
            default: return "Unknown"
            }
        } else {
            switch calendarStatus {
            case .notDetermined: return "Not Requested"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .authorized: return "Authorized"
            default: return "Unknown"
            }
        }
    }
    
    var remindersStatusText: String {
        if #available(macOS 14.0, *) {
            switch remindersStatus {
            case .notDetermined: return "Not Requested"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .fullAccess: return "Full Access"
            case .writeOnly: return "Write Only"
            default: return "Unknown"
            }
        } else {
            switch remindersStatus {
            case .notDetermined: return "Not Requested"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .authorized: return "Authorized"
            default: return "Unknown"
            }
        }
    }
}
