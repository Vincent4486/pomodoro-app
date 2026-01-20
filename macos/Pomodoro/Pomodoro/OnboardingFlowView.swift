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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: OnboardingStep = .welcome
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingAuthorization = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(step.title)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                Spacer()
                Button("Not Now") {
                    onboardingState.markCompleted()
                }
                .buttonStyle(.borderless)
            }

            stepContent

            Spacer()

            HStack {
                if step != .welcome {
                    Button("Back") {
                        step = step.previous(using: appState.notificationDeliveryStyle)
                    }
                }
                Spacer()
                Button(step == .media ? "Finish" : "Continue") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(width: 520, height: 360)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .onAppear {
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
                Text("Pomodoro helps you focus with structured work and break sessions.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        case .notificationStyle:
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose how you want to be notified when sessions end.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                Picker("Notification Style", selection: $appState.notificationDeliveryStyle) {
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
                Text("Pomodoro can notify you when sessions end.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)

                statusRow

                HStack(spacing: 12) {
                    Button(isRequestingAuthorization ? "Requesting..." : "Enable Notifications") {
                        requestAuthorization()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRequestingAuthorization)

                    if authorizationStatus == .denied {
                        Button("Open System Settings") {
                            openNotificationSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case .media:
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio & Music")
                    .font(.system(.headline, design: .rounded))
                Text("Pomodoro includes built-in focus sounds that work without any permission.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Optional Apple Music or Spotify integration is possible later using their official SDKs.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
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
            return "Notifications are enabled."
        case .denied:
            return "Notifications are turned off in System Settings."
        case .notDetermined:
            return "Notifications have not been requested yet."
        case .ephemeral:
            return "Notifications are temporarily available."
        @unknown default:
            return "Notification status unavailable."
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
        if let next = step.next(using: appState.notificationDeliveryStyle) {
            step = next
        } else {
            onboardingState.markCompleted()
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case notificationStyle
    case notificationPermission
    case media

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Pomodoro"
        case .notificationStyle:
            return "Notification Style"
        case .notificationPermission:
            return "Enable Notifications"
        case .media:
            return "Audio & Music"
        }
    }

    func next(using deliveryStyle: NotificationDeliveryStyle) -> OnboardingStep? {
        switch self {
        case .welcome:
            return .notificationStyle
        case .notificationStyle:
            return deliveryStyle == .system ? .notificationPermission : .media
        case .notificationPermission:
            return .media
        case .media:
            return nil
        }
    }

    func previous(using deliveryStyle: NotificationDeliveryStyle) -> OnboardingStep {
        switch self {
        case .welcome:
            return .welcome
        case .notificationStyle:
            return .welcome
        case .notificationPermission:
            return .notificationStyle
        case .media:
            return deliveryStyle == .system ? .notificationPermission : .notificationStyle
        }
    }
}
