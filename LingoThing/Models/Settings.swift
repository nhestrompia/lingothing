import Foundation

struct AppSettings: Codable, Equatable {
    static let allowedIntervalMinutes: [Int] = [1, 10, 15, 30, 60, 120]

    enum PracticeLanguage: String, Codable, CaseIterable, Identifiable {
        case greek
        case spanish
        case french
        case german
        case italian
        case turkish

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .greek: return "Greek"
            case .spanish: return "Spanish"
            case .french: return "French"
            case .german: return "German"
            case .italian: return "Italian"
            case .turkish: return "Turkish"
            }
        }

        var localeIdentifier: String {
            switch self {
            case .greek: return "el-GR"
            case .spanish: return "es-ES"
            case .french: return "fr-FR"
            case .german: return "de-DE"
            case .italian: return "it-IT"
            case .turkish: return "tr-TR"
            }
        }

        var resourceCandidates: [String] {
            switch self {
            case .greek:
                return [
                    "pronunciation-items",
                ]
            case .spanish:
                return ["pronunciation-items-es", "phrases-es"]
            case .french:
                return ["pronunciation-items-fr", "phrases-fr"]
            case .german:
                return ["pronunciation-items-de", "phrases-de"]
            case .italian:
                return ["pronunciation-items-it", "phrases-it"]
            case .turkish:
                return ["pronunciation-items-tr", "phrases-tr"]
            }
        }
    }

    var practiceLanguage: PracticeLanguage = .greek
    var intervalMinutes: Int = Constants.Scheduler.defaultIntervalMinutes
    var activeHoursStart: Int = Constants.Scheduler.defaultActiveHoursStart
    var activeHoursEnd: Int = Constants.Scheduler.defaultActiveHoursEnd
    var snoozeMinutes: Int = Constants.Scheduler.defaultSnoozeMinutes
    var autoPlayAudio: Bool = false
    var launchAtLogin: Bool = false
    var speechMode: SpeechMode = .autoDetect
    var isPaused: Bool = false
    var enabledCategoryIDsByLanguage: [String: [String]] = [:]
    var selectedLevelRawByLanguage: [String: String] = [:]
    var selectedVoiceIDByLanguage: [String: String] = [:]

    enum SpeechMode: String, Codable, CaseIterable {
        case tapToSpeak = "Tap to Speak"
        case autoDetect = "Auto-detect"
    }

    enum PracticeLevelFilter: String, Codable, CaseIterable, Identifiable {
        case all
        case beginner
        case intermediate
        case advanced

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "All Levels"
            case .beginner: return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case practiceLanguage
        case intervalMinutes
        case activeHoursStart
        case activeHoursEnd
        case snoozeMinutes
        case autoPlayAudio
        case launchAtLogin
        case speechMode
        case isPaused
        case enabledCategoryIDsByLanguage
        case selectedLevelRawByLanguage
        case selectedVoiceIDByLanguage
        case enabledCategoryIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        practiceLanguage = try container.decodeIfPresent(PracticeLanguage.self, forKey: .practiceLanguage) ?? .greek
        let savedInterval = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? Constants.Scheduler.defaultIntervalMinutes
        intervalMinutes = Self.allowedIntervalMinutes.contains(savedInterval)
            ? savedInterval
            : Constants.Scheduler.defaultIntervalMinutes
        activeHoursStart = try container.decodeIfPresent(Int.self, forKey: .activeHoursStart) ?? Constants.Scheduler.defaultActiveHoursStart
        activeHoursEnd = try container.decodeIfPresent(Int.self, forKey: .activeHoursEnd) ?? Constants.Scheduler.defaultActiveHoursEnd
        snoozeMinutes = try container.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? Constants.Scheduler.defaultSnoozeMinutes
        autoPlayAudio = try container.decodeIfPresent(Bool.self, forKey: .autoPlayAudio) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        speechMode = try container.decodeIfPresent(SpeechMode.self, forKey: .speechMode) ?? .autoDetect
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        enabledCategoryIDsByLanguage = try container.decodeIfPresent([String: [String]].self, forKey: .enabledCategoryIDsByLanguage) ?? [:]
        selectedLevelRawByLanguage = try container.decodeIfPresent([String: String].self, forKey: .selectedLevelRawByLanguage) ?? [:]
        selectedVoiceIDByLanguage = try container.decodeIfPresent([String: String].self, forKey: .selectedVoiceIDByLanguage) ?? [:]

        // Backward compatibility: migrate legacy single-language category storage.
        if enabledCategoryIDsByLanguage.isEmpty {
            let legacy = try container.decodeIfPresent([String].self, forKey: .enabledCategoryIDs) ?? []
            if !legacy.isEmpty {
                enabledCategoryIDsByLanguage[practiceLanguage.rawValue] = legacy
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(practiceLanguage, forKey: .practiceLanguage)
        try container.encode(intervalMinutes, forKey: .intervalMinutes)
        try container.encode(activeHoursStart, forKey: .activeHoursStart)
        try container.encode(activeHoursEnd, forKey: .activeHoursEnd)
        try container.encode(snoozeMinutes, forKey: .snoozeMinutes)
        try container.encode(autoPlayAudio, forKey: .autoPlayAudio)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(speechMode, forKey: .speechMode)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(enabledCategoryIDsByLanguage, forKey: .enabledCategoryIDsByLanguage)
        try container.encode(selectedLevelRawByLanguage, forKey: .selectedLevelRawByLanguage)
        try container.encode(selectedVoiceIDByLanguage, forKey: .selectedVoiceIDByLanguage)
    }

    private static let key = "AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func enabledCategories(for language: PracticeLanguage, all available: [PhraseCategory]) -> Set<PhraseCategory> {
        let allSet = Set(available)
        guard !allSet.isEmpty else { return [] }

        let storedIDs = enabledCategoryIDsByLanguage[language.rawValue] ?? []
        let storedSet = Set(storedIDs.compactMap { PhraseCategory(rawValue: $0) })
        let filtered = storedSet.intersection(allSet)
        return filtered.isEmpty ? allSet : filtered
    }

    mutating func setEnabledCategories(_ categories: Set<PhraseCategory>, for language: PracticeLanguage, all available: [PhraseCategory]) {
        let allSet = Set(available)
        if allSet.isEmpty || categories.isEmpty || categories == allSet {
            enabledCategoryIDsByLanguage.removeValue(forKey: language.rawValue)
            return
        }
        enabledCategoryIDsByLanguage[language.rawValue] = categories.map(\.rawValue).sorted()
    }

    func selectedLevelFilter(for language: PracticeLanguage) -> PracticeLevelFilter {
        guard let raw = selectedLevelRawByLanguage[language.rawValue],
              let filter = PracticeLevelFilter(rawValue: raw) else {
            return .all
        }
        return filter
    }

    mutating func setSelectedLevelFilter(_ filter: PracticeLevelFilter, for language: PracticeLanguage) {
        if filter == .all {
            selectedLevelRawByLanguage.removeValue(forKey: language.rawValue)
            return
        }
        selectedLevelRawByLanguage[language.rawValue] = filter.rawValue
    }

    func selectedVoiceID(for language: PracticeLanguage) -> String? {
        selectedVoiceIDByLanguage[language.rawValue]
    }

    mutating func setSelectedVoiceID(_ voiceID: String?, for language: PracticeLanguage) {
        guard let voiceID, !voiceID.isEmpty else {
            selectedVoiceIDByLanguage.removeValue(forKey: language.rawValue)
            return
        }
        selectedVoiceIDByLanguage[language.rawValue] = voiceID
    }
}
