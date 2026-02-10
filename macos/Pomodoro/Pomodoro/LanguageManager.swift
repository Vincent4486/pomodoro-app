import Foundation
import SwiftUI
import Combine

final class LanguageManager: ObservableObject {
    enum AppLanguage: String, CaseIterable, Identifiable {
        case auto
        case english
        case chinese

        var id: String { rawValue }

        var localeIdentifier: String? {
            switch self {
            case .auto:
                return nil
            case .english:
                return "en"
            case .chinese:
                return "zh-Hans"
            }
        }

        var resourceCode: String {
            switch self {
            case .auto:
                return LanguageManager.systemPreferredResourceCode()
            case .english:
                return "en"
            case .chinese:
                return "zh"
            }
        }

        // Backward compatibility with existing references.
        static var system: AppLanguage { .auto }
        static var simplifiedChinese: AppLanguage { .chinese }
    }

    static let shared = LanguageManager()

    @Published var currentLanguage: AppLanguage {
        didSet {
            guard oldValue != currentLanguage else { return }
            defaults.set(currentLanguage.rawValue, forKey: defaultsKey)
            reloadActiveDictionary()
        }
    }

    private var activeDictionary: [String: String] = [:]

    // Backward compatibility with existing code paths.
    var selectedLanguage: AppLanguage {
        get { currentLanguage }
        set { currentLanguage = newValue }
    }

    private let defaults = UserDefaults.standard
    private let defaultsKey = "app.localization.selectedLanguage"
    private var localeObserver: NSObjectProtocol?
    private var englishDictionary: [String: String] = [:]

    private init() {
        if let raw = defaults.string(forKey: defaultsKey) {
            switch raw {
            case "system":
                currentLanguage = .auto
            case "simplifiedChinese":
                currentLanguage = .chinese
            default:
                currentLanguage = AppLanguage(rawValue: raw) ?? .auto
            }
        } else {
            currentLanguage = .auto
        }

        englishDictionary = loadDictionary(resourceCode: "en")
        if englishDictionary.isEmpty {
            englishDictionary = loadFromStringsFile(localeIdentifier: "en")
        }
        reloadActiveDictionary()

        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.currentLanguage == .auto {
                self.reloadActiveDictionary()
            }
        }
    }

    deinit {
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    var localeOverride: Locale? {
        guard let id = currentLanguage.localeIdentifier else { return nil }
        return Locale(identifier: id)
    }

    var effectiveLocale: Locale {
        localeOverride ?? .autoupdatingCurrent
    }

    func text(_ key: String) -> String {
        activeDictionary[key] ?? englishDictionary[key] ?? key
    }

    func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    func format(_ key: String, arguments: [CVarArg]) -> String {
        let formatString = text(key)
        guard !arguments.isEmpty else { return formatString }
        return String(format: formatString, locale: effectiveLocale, arguments: arguments)
    }

    private func reloadActiveDictionary() {
        let code = currentLanguage.resourceCode
        var dictionary = loadDictionary(resourceCode: code)
        if dictionary.isEmpty, code == "zh" {
            dictionary = loadFromStringsFile(localeIdentifier: "zh-Hans")
        } else if dictionary.isEmpty, code == "en" {
            dictionary = loadFromStringsFile(localeIdentifier: "en")
        }
        if dictionary.isEmpty {
            dictionary = englishDictionary
        }
        activeDictionary = dictionary
    }

    private func loadDictionary(resourceCode: String) -> [String: String] {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: resourceCode, withExtension: "json", subdirectory: "Localization"),
            Bundle.main.url(forResource: resourceCode, withExtension: "json")
        ]
        guard let url = candidateURLs.compactMap({ $0 }).first else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try JSONDecoder().decode([String: String].self, from: data)
            return parsed
        } catch {
            return [:]
        }
    }

    private func loadFromStringsFile(localeIdentifier: String) -> [String: String] {
        guard let languagePath = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: languagePath),
              let stringsPath = bundle.path(forResource: "Localizable", ofType: "strings"),
              let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String] else {
            return [:]
        }
        return dict
    }

    private static func systemPreferredResourceCode() -> String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("zh") {
            return "zh"
        }
        return "en"
    }
}

typealias LocalizationManager = LanguageManager

@inline(__always)
func L(_ key: String) -> String {
    LanguageManager.shared.text(key)
}

@inline(__always)
func L(_ key: String, _ args: CVarArg...) -> String {
    LanguageManager.shared.format(key, arguments: args)
}

struct LText: View {
    @EnvironmentObject private var languageManager: LanguageManager
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(languageManager.text(key))
    }
}
