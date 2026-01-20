//
//  OnboardingState.swift
//  Pomodoro
//
//  Created by OpenAI on 2025-02-01.
//

import Foundation

final class OnboardingState: ObservableObject {
    @Published var isPresented: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isPresented = !userDefaults.bool(forKey: DefaultsKey.onboardingCompleted)
    }

    func markCompleted() {
        userDefaults.set(true, forKey: DefaultsKey.onboardingCompleted)
        isPresented = false
    }

    func reopen() {
        isPresented = true
    }

    private enum DefaultsKey {
        static let onboardingCompleted = "onboarding.completed"
    }
}
