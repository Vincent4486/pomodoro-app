//
//  OnboardingFlowView.swift
//  Pomodoro
//
//  Created by OpenAI on 2025-02-01.
//

import AppKit
import SwiftUI
import UserNotifications

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flow: [OnboardingStep] = []
    @State private var index: Int = 0
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingAuthorization = false

    private var step: OnboardingStep {
        guard index < flow.count else { return .welcome }
        return flow[index]
    }

    private var isLastStep: Bool {
        index == flow.count - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(localizationManager.text(step.titleKey))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                Spacer()
                Button(localizationManager.text("onboarding.not_now")) {
                    onboardingState.markCompleted()
                }
                .buttonStyle(.borderless)
            }

            stepContent

            Spacer()

            HStack {
                if index > 0 {
                    Button(localizationManager.text("onboarding.back")) {
                        back()
                    }
                }
                Spacer()
                Button(isLastStep ? localizationManager.text("onboarding.finish") : localizationManager.text("onboarding.continue")) {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 520, height: 360)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onAppear {
            rebuildFlow()
            refreshAuthorizationStatusIfNeeded()
        }
        .onChange(of: step) { _, _ in
            refreshAuthorizationStatusIfNeeded()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.welcome.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .notificationStyle:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.notification_style.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                Picker(localizationManager.text("onboarding.notification_style.title"), selection: $appState.notificationDeliveryStyle) {
                    ForEach(NotificationDeliveryStyle.allCases) { style in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                            Text(style.detail)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        case .notificationPermission:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.notification_permission.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                statusRow

                HStack(spacing: 12) {
                    Button(isRequestingAuthorization ? localizationManager.text("onboarding.requesting") : localizationManager.text("onboarding.enable_notifications")) {
                        requestAuthorization()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequestingAuthorization)

                    if authorizationStatus == .denied {
                        Button(localizationManager.text("common.open_system_settings")) {
                            openNotificationSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case .media:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.media.title"))
                    .font(.system(.headline, design: .rounded))
                Text(localizationManager.text("onboarding.media.body_primary"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(localizationManager.text("onboarding.media.body_secondary"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .systemPermissions:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.permissions.title"))
                    .font(.system(.headline, design: .rounded))
                Text(localizationManager.text("onboarding.permissions.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(localizationManager.text("onboarding.permissions.enable_access")) {
                        Task {
                            isRequestingAuthorization = true
                            await appState.requestCalendarAndReminderAccessIfNeeded()
                            isRequestingAuthorization = false
                            onboardingState.markPermissionsPrompted()
                            advance()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRequestingAuthorization)

                    Button(localizationManager.text("onboarding.not_now")) {
                        onboardingState.markPermissionsPrompted()
                        advance()
                    }
                    .buttonStyle(.bordered)
                }

                Text(appState.calendarReminderPermissionStatusText)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .menuBarTip:
            VStack(alignment: .leading, spacing: 12) {
                Text(localizationManager.text("onboarding.menu_bar_tip.title"))
                    .font(.system(.headline, design: .rounded))
                Text(localizationManager.text("onboarding.menu_bar_tip.body"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                Button(localizationManager.text("onboarding.got_it")) {
                    onboardingState.markMenuBarTipSeen()
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return localizationManager.text("onboarding.notifications.enabled")
        case .denied:
            return localizationManager.text("onboarding.notifications.denied")
        case .notDetermined:
            return localizationManager.text("onboarding.notifications.not_requested")
        case .ephemeral:
            return localizationManager.text("onboarding.notifications.ephemeral")
        @unknown default:
            return localizationManager.text("onboarding.notifications.unavailable")
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .ephemeral:
            return .blue
        @unknown default:
            return .gray
        }
    }

    private func refreshAuthorizationStatusIfNeeded() {
        guard step == .notificationPermission else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestAuthorization() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        appState.requestSystemNotificationAuthorization { status in
            authorizationStatus = status
            isRequestingAuthorization = false
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    private func advance() {
        guard !flow.isEmpty else {
            onboardingState.markCompleted()
            return
        }
        if index + 1 < flow.count {
            index += 1
        } else {
            onboardingState.markCompleted()
        }
    }

    private func back() {
        guard index > 0 else { return }
        index -= 1
    }

    private func rebuildFlow() {
        flow = OnboardingStep.baseFlow(deliveryStyle: appState.notificationDeliveryStyle)
        if onboardingState.needsSystemPermissions {
            flow.append(.systemPermissions)
        }
        if onboardingState.needsMenuBarTip {
            flow.append(.menuBarTip)
        }
        if flow.isEmpty {
            flow = [.welcome]
        }
        index = 0
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case notificationStyle
    case notificationPermission
    case media
    case systemPermissions
    case menuBarTip

    var titleKey: String {
        switch self {
        case .welcome:
            return "onboarding.welcome.title"
        case .notificationStyle:
            return "onboarding.notification_style.title"
        case .notificationPermission:
            return "onboarding.notification_permission.title"
        case .media:
            return "onboarding.media.title"
        case .systemPermissions:
            return "onboarding.permissions.title"
        case .menuBarTip:
            return "onboarding.menu_bar_tip.title"
        }
    }

    static func baseFlow(deliveryStyle: NotificationDeliveryStyle) -> [OnboardingStep] {
        if deliveryStyle == .system {
            return [.welcome, .notificationStyle, .notificationPermission, .media]
        } else {
            return [.welcome, .notificationStyle, .media]
        }
    }
}
