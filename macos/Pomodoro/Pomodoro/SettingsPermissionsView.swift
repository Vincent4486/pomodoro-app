import EventKit
import AppKit
import SwiftUI

/// Settings view with centralized permission overview.
/// Shows status and enable buttons for Notifications, Calendar, and Reminders.
@MainActor
struct SettingsPermissionsView: View {
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject private var featureGate = FeatureGate.shared
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showAdvancedAccountTools = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(localizationManager.text("permissions.title"))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(localizationManager.text("permissions.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                permissionRow(
                    icon: "bell.fill",
                    title: localizationManager.text("permissions.notifications"),
                    status: permissionsManager.notificationStatusText,
                    isAuthorized: permissionsManager.isNotificationsAuthorized,
                    action: {
                        Task {
                            await permissionsManager.requestNotificationPermission()
                        }
                    }
                )
                
                Divider()
                
                permissionRow(
                    icon: "calendar",
                    title: localizationManager.text("permissions.calendar"),
                    status: permissionsManager.calendarStatusText,
                    isAuthorized: permissionsManager.isCalendarAuthorized,
                    isDenied: permissionsManager.calendarStatus == .denied || permissionsManager.calendarStatus == .restricted,
                    action: {
                        Task {
                            await permissionsManager.requestCalendarPermission()
                        }
                    }
                )
                
                Divider()
                
                permissionRow(
                    icon: "checklist",
                    title: localizationManager.text("permissions.reminders"),
                    status: permissionsManager.remindersStatusText,
                    isAuthorized: permissionsManager.isRemindersAuthorized,
                    isDenied: permissionsManager.remindersStatus == .denied || permissionsManager.remindersStatus == .restricted,
                    action: {
                        Task {
                            await permissionsManager.requestRemindersPermission()
                        }
                    }
                )
            }
            .padding(16)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            Text(localizationManager.text("permissions.note.reminders_optional"))
                .font(.caption)
                .foregroundStyle(.secondary)

            aiSubscriptionSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear {
            permissionsManager.refreshAllStatuses()
            Task { @MainActor in
                guard !featureGate.isRefreshingAllowance else { return }
                await featureGate.refreshAllowance()
            }
        }
        .alert(localizationManager.text("permissions.calendar.denied_title"), isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("permissions.calendar.denied_message"))
        }
        .alert(localizationManager.text("permissions.reminders.denied_title"), isPresented: $permissionsManager.showRemindersDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("permissions.reminders.denied_message"))
        }

        Divider()

        DisclosureGroup(
            "Account & Cloud (Cloud/AI Features Coming Soon)",
            isExpanded: $showAdvancedAccountTools
        ) {
            CloudSettingsSection()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
        .accessibilityLabel("Account & Cloud (Cloud/AI Features Coming Soon)")
        .accessibilityIdentifier("settings.account_cloud_disclosure")
        .font(.subheadline.weight(.medium))
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)

        Button {
            guard let url = URL(string: "https://pomodoro-app.tech/policies.html") else {
                return
            }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                Text("Privacy & Policies")
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var aiSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizationManager.text("settings.ai_subscription.title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                statusRow(
                    label: localizationManager.text("settings.ai_subscription.current_plan"),
                    value: currentPlanLabel
                )

                aiPlanningContent

                if let subscriptionEndAt = featureGate.subscriptionEndAt,
                          featureGate.tier == .plus || featureGate.tier == .pro {
                    statusRow(
                        label: localizationManager.text("settings.ai_subscription.subscription_ends"),
                        value: formattedDate(subscriptionEndAt)
                    )
                }

                if let resetAt = featureGate.allowanceResetAt {
                    statusRow(
                        label: localizationManager.text("settings.ai_subscription.usage_resets"),
                        value: formattedDate(resetAt)
                    )
                }

                if !displayedAIUsageProgressItems.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(displayedAIUsageProgressItems, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))

                                ProgressView(value: item.usedRatio)
                                    .tint(usageColor(for: item.usedRatio))

                                Text(localizationManager.format("settings.ai_usage.used_percentage", item.usedPercentage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var aiPlanningContent: some View {
        switch aiPlanningDisplayMode {
        case .upgrade:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                Text(localizationManager.text("settings.ai_planning.free_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(localizationManager.text("tasks.ai_assistant.upgrade")) {
                    openUpgradePage()
                }
                .buttonStyle(.borderedProminent)
            }
        case .deepSeek:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                statusRow(
                    label: localizationManager.text("settings.ai_planning.available_model"),
                    value: "DeepSeek"
                )
            }
        case .deepSeekAndGemini:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 8) {
                    modelRow("Gemini")
                    modelRow("DeepSeek")
                }
            }
        }
    }

    private var displayedAIUsageProgressItems: [FeatureGate.AIUsageProgress] {
        switch aiPlanningDisplayMode {
        case .upgrade:
            return []
        case .deepSeek:
            return featureGate.aiUsageProgressItems.filter { $0.title == "DeepSeek" }
        case .deepSeekAndGemini:
            return featureGate.aiUsageProgressItems.filter { $0.title == "DeepSeek" || $0.title == "Gemini Flash" }
        }
    }

    private var aiPlanningDisplayMode: AIPlanningDisplayMode {
        switch featureGate.tier {
        case .plus, .beta:
            return .deepSeek
        case .pro, .developer:
            return .deepSeekAndGemini
        case .free, .expired:
            return .upgrade
        }
    }

    private func usageColor(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.6:
            return .accentColor
        case ..<0.8:
            return .yellow
        default:
            return .red
        }
    }

    private var currentPlanLabel: String {
        switch featureGate.tier {
        case .free:
            return localizationManager.text("settings.ai_subscription.plan.free")
        case .plus:
            return localizationManager.text("settings.ai_subscription.plan.plus")
        case .pro:
            return localizationManager.text("settings.ai_subscription.plan.pro")
        case .developer:
            return localizationManager.text("settings.ai_subscription.plan.developer")
        case .beta:
            return localizationManager.text("settings.ai_subscription.plan.beta")
        case .expired:
            return localizationManager.text("settings.ai_subscription.plan.expired")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    private func openUpgradePage() {
        guard let url = URL(string: "https://pomodoro-app.tech") else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func statusRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func modelRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
    
    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        status: String,
        isAuthorized: Bool,
        isDenied: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isAuthorized ? .green : (isDenied ? .red : .secondary))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isAuthorized ? .green : (isDenied ? .red : .secondary))
            }
            
            Spacer()
            
            if isAuthorized {
                Text(localizationManager.text("permissions.authorized"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else if isDenied {
                Button(action: action) {
                    Text(localizationManager.text("permissions.request_again"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: action) {
                    Text(localizationManager.text("permissions.enable"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private enum AIPlanningDisplayMode {
    case upgrade
    case deepSeek
    case deepSeekAndGemini
}

#Preview {
    MainActor.assumeIsolated {
        SettingsPermissionsView(permissionsManager: .shared)
            .frame(width: 600, height: 400)
            .environmentObject(AuthViewModel.shared)
    }
}
