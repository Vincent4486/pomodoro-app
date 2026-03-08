import Foundation
import Combine
import FirebaseAuth
import FirebaseFunctions

/// Entitlement-aware feature gating for cloud-powered capabilities.
final class FeatureGate: ObservableObject {
    struct AIUsageProgress {
        let title: String
        let usedRatio: Double

        var usedPercentage: Int {
            Int((usedRatio * 100).rounded())
        }
    }

    enum Tier: String, Decodable {
        case free
        case beta
        case plus
        case pro
        case expired
        case developer
    }

    @Published private(set) var tier: Tier = .free
    @Published private(set) var deepSeekRemainingTokens: Int?
    @Published private(set) var deepSeekMonthlyLimit: Int?
    @Published private(set) var geminiFlash3RemainingTokens: Int?
    @Published private(set) var geminiFlash3MonthlyLimit: Int?
    @Published private(set) var allowanceResetAt: Date?
    @Published private(set) var subscriptionEndAt: Date?
    @Published private(set) var isRefreshingAllowance = false
    @Published private(set) var allowanceErrorMessage: String?

    static let shared = FeatureGate()

    private var authListener: AuthStateDidChangeListenerHandle?
    private let functions: Functions

    private init(functions: Functions? = nil) {
        if let functions {
            self.functions = functions
        } else {
            self.functions = Functions.functions(region: "us-central1")
        }
        listenForAuthChanges()
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    // MARK: - Permissions

    var canUseCloudProxyAI: Bool {
        switch tier {
        case .plus, .pro, .beta, .developer:
            return true
        default:
            return false
        }
    }

    var canUseNotesProFeatures: Bool {
        switch tier {
        case .pro, .developer:
            return true
        default:
            return false
        }
    }

    var canUseSharePrivateSocial: Bool {
        switch tier {
        case .plus, .pro, .beta, .developer:
            return true
        default:
            return false
        }
    }

    var isExpired: Bool {
        tier == .expired
    }

    var hasAnyQuotaData: Bool {
        deepSeekRemainingTokens != nil || geminiFlash3RemainingTokens != nil
    }

    var isAIQuotaExhausted: Bool {
        let trackedValues = [deepSeekRemainingTokens, geminiFlash3RemainingTokens].compactMap { $0 }
        guard !trackedValues.isEmpty else { return false }
        return trackedValues.allSatisfy { $0 <= 0 }
    }

    var canTriggerAIAction: Bool {
        canUseCloudProxyAI && !isAIQuotaExhausted
    }

    var canUseAIPlanning: Bool {
        switch tier {
        case .pro, .developer:
            return true
        default:
            return false
        }
    }

    var canUseAIAssistantBreakdown: Bool {
        switch tier {
        case .plus, .pro, .developer:
            return true
        default:
            return false
        }
    }

    var canUseAdvancedTasks: Bool {
        switch tier {
        case .plus, .pro, .developer:
            return true
        default:
            return false
        }
    }

    var canUseTaskMarkdown: Bool {
        canUseAdvancedTasks
    }

    var canUseSubtasks: Bool {
        canUseAdvancedTasks
    }

    var canUseTaskKeyboardShortcuts: Bool {
        canUseAdvancedTasks
    }

    var canUseEisenhowerMatrix: Bool {
        switch tier {
        case .pro, .developer:
            return true
        default:
            return false
        }
    }

    var aiAssistantUpgradeTitle: String {
        LocalizationManager.shared.text("tasks.ai_assistant.plus_feature_title")
    }

    func canUseAIAssistantAction(_ action: AIAssistantAction) -> Bool {
        switch action {
        case .breakdown:
            return canUseAIAssistantBreakdown
        case .planning:
            return canUseAIPlanning
        }
    }

    func shouldShowUpgradeModal(for action: AIAssistantAction) -> Bool {
        !canUseAIAssistantAction(action)
    }

    func aiAssistantDisabledReason(for action: AIAssistantAction) -> String? {
        if !canUseAIAssistantAction(action) {
            switch action {
            case .breakdown:
                return LocalizationManager.shared.text("tasks.ai_assistant.breakdown_requires_plus")
            case .planning:
                return LocalizationManager.shared.text("tasks.ai_assistant.planning_requires_pro")
            }
        }
        if isAIQuotaExhausted {
            return aiActionDisabledReason
        }
        return nil
    }

    var aiPlanningDisabledReason: String? {
        if !canUseAIPlanning {
            return LocalizationManager.shared.text("tasks.ai_assistant.planning_requires_pro")
        }
        if isAIQuotaExhausted {
            return aiActionDisabledReason
        }
        return nil
    }

    var shouldShowAIPlanningUpgradeModal: Bool {
        !canUseAIPlanning
    }

    var aiPlanningQuotaMessage: String? {
        guard (canUseAIPlanning || canUseAIAssistantBreakdown), isAIQuotaExhausted else { return nil }
        return aiActionDisabledReason
    }

    var canRunAIPlanningRequest: Bool {
        (canUseAIPlanning || canUseAIAssistantBreakdown) && !isAIQuotaExhausted
    }

    var aiUsageProgressItems: [AIUsageProgress] {
        [
            usageProgress(
                title: "DeepSeek",
                remaining: deepSeekRemainingTokens,
                limit: deepSeekMonthlyLimit
            ),
            usageProgress(
                title: "Gemini Flash",
                remaining: geminiFlash3RemainingTokens,
                limit: geminiFlash3MonthlyLimit
            )
        ]
        .compactMap { $0 }
    }

    var aiActionDisabledReason: String? {
        let l10n = LocalizationManager.shared
        if !canUseCloudProxyAI {
            return l10n.text("feature_gate.ai_access_unavailable")
        }
        if isAIQuotaExhausted {
            Self.resetFormatter.locale = l10n.effectiveLocale
            if let resetText = allowanceResetAt.map(Self.resetFormatter.string(from:)) {
                return l10n.format("feature_gate.ai_quota_exhausted_refresh_on", resetText)
            }
            return l10n.text("feature_gate.ai_quota_exhausted")
        }
        return nil
    }

    private func usageProgress(title: String, remaining: Int?, limit: Int?) -> AIUsageProgress? {
        guard let remaining, let limit, limit > 0 else {
            return nil
        }

        let used = max(0, min(limit, limit - remaining))
        let ratio = min(1, max(0, Double(used) / Double(limit)))
        return AIUsageProgress(title: title, usedRatio: ratio)
    }

    // MARK: - Networking

    @MainActor
    func refreshTier() async {
        await refreshAllowance()
    }

    @MainActor
    func refreshAllowance() async {
        guard AuthViewModel.shared.isAuthenticated else {
            resetToSignedOutState()
            return
        }

        isRefreshingAllowance = true
        allowanceErrorMessage = nil
        defer { isRefreshingAllowance = false }

        do {
            let result = try await functions
                .httpsCallable("getAllowance")
                .call()
            let payload = try decodeAllowancePayload(from: result.data)
            apply(payload: payload)
        } catch {
            allowanceErrorMessage = error.localizedDescription
        }
    }

    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user == nil {
                    self.resetToSignedOutState()
                } else {
                    await self.refreshAllowance()
                }
            }
        }
    }

    @MainActor
    private func resetToSignedOutState() {
        tier = .free
        deepSeekRemainingTokens = nil
        deepSeekMonthlyLimit = nil
        geminiFlash3RemainingTokens = nil
        geminiFlash3MonthlyLimit = nil
        allowanceResetAt = nil
        subscriptionEndAt = nil
    }

    @MainActor
    private func apply(payload: AllowancePayload) {
        if let uid = Auth.auth().currentUser?.uid,
           uid == "1ebilryd5YhIgWe7zVGzw3yQZTq1" {
            print("Developer override active for UID:", uid)
            tier = .developer
            deepSeekRemainingTokens = payload.deepSeekRemainingTokens
            deepSeekMonthlyLimit = payload.deepSeekMonthlyLimit
            geminiFlash3RemainingTokens = payload.geminiFlash3RemainingTokens
            geminiFlash3MonthlyLimit = payload.geminiFlash3MonthlyLimit
            allowanceResetAt = payload.resetAt
            subscriptionEndAt = payload.subscriptionEndAt
            return
        }

        tier = payload.tier ?? .free
        deepSeekRemainingTokens = payload.deepSeekRemainingTokens
        deepSeekMonthlyLimit = payload.deepSeekMonthlyLimit
        geminiFlash3RemainingTokens = payload.geminiFlash3RemainingTokens
        geminiFlash3MonthlyLimit = payload.geminiFlash3MonthlyLimit
        allowanceResetAt = payload.resetAt
        subscriptionEndAt = payload.subscriptionEndAt
    }

    private func decodeAllowancePayload(from data: Any) throws -> AllowancePayload {
        let rootObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rootObject = nested
        } else {
            rootObject = data
        }

        guard JSONSerialization.isValidJSONObject(rootObject) else {
            throw GateError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rootObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AllowanceResponse.self, from: responseData) {
            return decoded.payload
        }

        let object = try JSONSerialization.jsonObject(with: responseData)
        guard let json = object as? [String: Any] else {
            throw GateError.decodingFailed
        }
        return AllowancePayload(json: json)
    }

    private enum GateError: LocalizedError {
        case invalidResponse
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return LocalizationManager.shared.text("feature_gate.error.invalid_allowance_response")
            case .decodingFailed:
                return LocalizationManager.shared.text("feature_gate.error.decoding_failed")
            }
        }
    }

    private struct AllowanceResponse: Decodable {
        let tier: Tier?
        let deepseek: ProviderQuota?
        let deepSeek: ProviderQuota?
        let geminiFlash3: ProviderQuota?
        let gemini_flash_3: ProviderQuota?
        let allowances: [String: ProviderQuota]?
        let quotas: [String: ProviderQuota]?
        let deepseekRemaining: Int?
        let deepseekLimit: Int?
        let geminiFlash3Remaining: Int?
        let geminiFlash3Limit: Int?
        let resetAt: Date?
        let reset_at: Date?
        let subscriptionEndAt: Date?
        let subscription_end_at: Date?

        var payload: AllowancePayload {
            let deepSeekQuota = deepseek ?? deepSeek ?? allowances?["deepseek"] ?? quotas?["deepseek"]
            let geminiQuota = geminiFlash3
                ?? gemini_flash_3
                ?? allowances?["geminiFlash3"]
                ?? allowances?["gemini_flash_3"]
                ?? quotas?["geminiFlash3"]
                ?? quotas?["gemini_flash_3"]

            return AllowancePayload(
                tier: tier,
                deepSeekRemainingTokens: deepSeekQuota?.remaining ?? deepseekRemaining,
                deepSeekMonthlyLimit: deepSeekQuota?.limit ?? deepseekLimit,
                geminiFlash3RemainingTokens: geminiQuota?.remaining ?? geminiFlash3Remaining,
                geminiFlash3MonthlyLimit: geminiQuota?.limit ?? geminiFlash3Limit,
                resetAt: resetAt ?? reset_at,
                subscriptionEndAt: subscriptionEndAt ?? subscription_end_at
            )
        }
    }

    private struct ProviderQuota: Decodable {
        let remaining: Int?
        let limit: Int?
    }

    private struct AllowancePayload {
        let tier: Tier?
        let deepSeekRemainingTokens: Int?
        let deepSeekMonthlyLimit: Int?
        let geminiFlash3RemainingTokens: Int?
        let geminiFlash3MonthlyLimit: Int?
        let resetAt: Date?
        let subscriptionEndAt: Date?

        init(
            tier: Tier?,
            deepSeekRemainingTokens: Int?,
            deepSeekMonthlyLimit: Int?,
            geminiFlash3RemainingTokens: Int?,
            geminiFlash3MonthlyLimit: Int?,
            resetAt: Date?,
            subscriptionEndAt: Date?
        ) {
            self.tier = tier
            self.deepSeekRemainingTokens = deepSeekRemainingTokens
            self.deepSeekMonthlyLimit = deepSeekMonthlyLimit
            self.geminiFlash3RemainingTokens = geminiFlash3RemainingTokens
            self.geminiFlash3MonthlyLimit = geminiFlash3MonthlyLimit
            self.resetAt = resetAt
            self.subscriptionEndAt = subscriptionEndAt
        }

        init(json: [String: Any]) {
            let rawTier = (json["tier"] as? String)?.lowercased()
            self.tier = rawTier.flatMap(Tier.init(rawValue:))

            let deepseek = (json["deepseek"] as? [String: Any]) ?? (json["deepSeek"] as? [String: Any])
            let gemini = (json["geminiFlash3"] as? [String: Any]) ?? (json["gemini_flash_3"] as? [String: Any])

            self.deepSeekRemainingTokens = deepseek?["remaining"] as? Int ?? json["deepseekRemaining"] as? Int
            self.deepSeekMonthlyLimit = deepseek?["limit"] as? Int ?? json["deepseekLimit"] as? Int
            self.geminiFlash3RemainingTokens = gemini?["remaining"] as? Int ?? json["geminiFlash3Remaining"] as? Int
            self.geminiFlash3MonthlyLimit = gemini?["limit"] as? Int ?? json["geminiFlash3Limit"] as? Int

            if let reset = json["resetAt"] as? String {
                self.resetAt = Self.parseDate(reset)
            } else if let reset = json["reset_at"] as? String {
                self.resetAt = Self.parseDate(reset)
            } else {
                self.resetAt = nil
            }

            if let end = json["subscriptionEndAt"] as? String {
                self.subscriptionEndAt = Self.parseDate(end)
            } else if let end = json["subscription_end_at"] as? String {
                self.subscriptionEndAt = Self.parseDate(end)
            } else {
                self.subscriptionEndAt = nil
            }
        }

        private static func parseDate(_ value: String) -> Date? {
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            return nil
        }
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    static func formatTokenCount(_ value: Int?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    static func tierDisplayName(_ tier: Tier) -> String {
        switch tier {
        case .free: return LocalizationManager.shared.text("feature_gate.tier.free")
        case .beta: return LocalizationManager.shared.text("feature_gate.tier.beta")
        case .plus: return LocalizationManager.shared.text("feature_gate.tier.plus")
        case .pro: return LocalizationManager.shared.text("feature_gate.tier.pro")
        case .expired: return LocalizationManager.shared.text("feature_gate.tier.expired")
        case .developer: return LocalizationManager.shared.text("feature_gate.tier.developer")
        }
    }
}
