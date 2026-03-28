import SwiftUI
import ServiceManagement
import Foundation
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import Speech

struct SettingsView: View {
    @Bindable var appState: AppState
    let phraseManager: PhraseManager
    let audioManager: AudioManager

    @State private var selectedSection: SettingsSection = .general
    @State private var categoryLanguage: AppSettings.PracticeLanguage
    @State private var levelLanguage: AppSettings.PracticeLanguage
    @State private var showVoicePreviewOptions = false
    @State private var microphoneStatus: AVAuthorizationStatus = Permissions.microphoneStatus
    @State private var speechStatus: SFSpeechRecognizerAuthorizationStatus = Permissions.speechStatus

    init(appState: AppState, phraseManager: PhraseManager, audioManager: AudioManager) {
        self._appState = Bindable(appState)
        self.phraseManager = phraseManager
        self.audioManager = audioManager
        self._categoryLanguage = State(initialValue: appState.settings.practiceLanguage)
        self._levelLanguage = State(initialValue: appState.settings.practiceLanguage)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    generalSettings
                case .categories:
                    categorySettings
                case .levels:
                    levelsSettings
                case .schedule:
                    scheduleSettings
                case .system:
                    systemSettings
                }
            }
            .navigationTitle(selectedSection.title)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appState.settings) { _, newSettings in
            newSettings.save()
            NotificationCenter.default.post(name: .settingsChanged, object: nil)
        }
        .onAppear {
            refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Practice") {
                Picker("Language", selection: $appState.settings.practiceLanguage) {
                    ForEach(languageOptions) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Picker(
                    "Level",
                    selection: Binding(
                        get: { appState.settings.selectedLevelFilter(for: appState.settings.practiceLanguage) },
                        set: { appState.settings.setSelectedLevelFilter($0, for: appState.settings.practiceLanguage) }
                    )
                ) {
                    ForEach(AppSettings.PracticeLevelFilter.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }

                Text("\(phraseManager.activePhraseCount()) items currently eligible for prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-play on open", isOn: $appState.settings.autoPlayAudio)
            }

            speechSection

            Section {
                Text("Set your default learning language and basic behavior here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var categorySettings: some View {
        Form {
            Section("Language") {
                Picker("Edit categories for", selection: $categoryLanguage) {
                    ForEach(languageOptions) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("Categories") {
                Toggle("All categories", isOn: Binding(
                    get: {
                        let available = availablePracticeCategories(for: categoryLanguage)
                        return selectedCategories(for: categoryLanguage) == Set(available) && !available.isEmpty
                    },
                    set: { enabled in
                        let available = availablePracticeCategories(for: categoryLanguage)
                        if enabled {
                            appState.settings.setEnabledCategories(Set(available), for: categoryLanguage, all: available)
                        } else if let first = available.first {
                            appState.settings.setEnabledCategories([first], for: categoryLanguage, all: available)
                        }
                    }
                ))

                ForEach(availablePracticeCategories(for: categoryLanguage)) { category in
                    Toggle(category.displayName, isOn: Binding(
                        get: { selectedCategories(for: categoryLanguage).contains(category) },
                        set: { enabled in
                            setCategory(category, enabled: enabled, for: categoryLanguage)
                        }
                    ))
                }
            }

            Section {
                Text("Selections are saved separately for each language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var levelsSettings: some View {
        Form {
            Section("Language") {
                Picker("Review language", selection: $levelLanguage) {
                    ForEach(languageOptions) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section("To Review") {
                let weakCount = WeakPhraseStore.shared.count(for: levelLanguage)
                Text("\(weakCount) items saved for review in \(levelLanguage.displayName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export To Review CSV") {
                    exportWeakPhrasesCSV(language: levelLanguage)
                }
                .disabled(weakCount == 0)
            }
        }
        .formStyle(.grouped)
    }

    private var scheduleSettings: some View {
        Form {
            Section("Timing") {
                Picker("Frequency", selection: $appState.settings.intervalMinutes) {
                    Text("Every min").tag(1)
                    Text("Every 10 min").tag(10)
                    Text("Every 15 min").tag(15)
                    Text("Every 30 min").tag(30)
                    Text("Every hour").tag(60)
                    Text("Every 2 hours").tag(120)
                }

                Picker("Snooze", selection: $appState.settings.snoozeMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            }

            Section("Active Hours") {
                HStack(spacing: 10) {
                    Text("From")
                        .foregroundStyle(.secondary)
                    HourMenu(
                        selectedHour: appState.settings.activeHoursStart,
                        onSelect: { appState.settings.activeHoursStart = $0 },
                        hourLabel: hourLabel
                    )

                    Text("to")
                        .foregroundStyle(.secondary)
                    HourMenu(
                        selectedHour: appState.settings.activeHoursEnd,
                        onSelect: { appState.settings.activeHoursEnd = $0 },
                        hourLabel: hourLabel
                    )
                }

                Toggle("Pause prompts", isOn: $appState.settings.isPaused)
            }
        }
        .formStyle(.grouped)
    }

    private var speechSection: some View {
        let language = appState.settings.practiceLanguage
        let localeIdentifier = language.localeIdentifier
        let options = audioManager.availableVoices(for: localeIdentifier)
        let automaticVoiceID = "__automatic__"
        let previewSample = voicePreviewSample(for: language)
        let selectedVoiceTag: String = {
            guard let stored = appState.settings.selectedVoiceID(for: language) else {
                return automaticVoiceID
            }
            return options.contains(where: { $0.id == stored }) ? stored : automaticVoiceID
        }()

        return Section("Speech") {
            Picker("Mode", selection: $appState.settings.speechMode) {
                ForEach(AppSettings.SpeechMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Picker(
                "Voice (\(language.displayName))",
                selection: Binding(
                    get: { selectedVoiceTag },
                    set: { newValue in
                        appState.settings.setSelectedVoiceID(
                            newValue == automaticVoiceID ? nil : newValue,
                            for: language
                        )
                    }
                )
            ) {
                Text("Automatic (Best Available)").tag(automaticVoiceID)
                ForEach(options) { option in
                    Text(option.displayName).tag(option.id)
                }
            }

            Button {
                audioManager.playPreview(
                    text: previewSample,
                    localeIdentifier: localeIdentifier,
                    voiceIdentifier: selectedVoiceTag == automaticVoiceID ? nil : selectedVoiceTag
                )
            } label: {
                Label("Preview selected voice", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.link)

            DisclosureGroup("Try all voices", isExpanded: $showVoicePreviewOptions) {
                VStack(alignment: .leading, spacing: 8) {
                    voicePreviewRow(
                        label: "Automatic (Best Available)",
                        isSelected: selectedVoiceTag == automaticVoiceID,
                        onPreview: {
                            audioManager.playPreview(
                                text: previewSample,
                                localeIdentifier: localeIdentifier,
                                voiceIdentifier: nil
                            )
                        }
                    )

                    ForEach(options) { option in
                        voicePreviewRow(
                            label: option.displayName,
                            isSelected: selectedVoiceTag == option.id,
                            onPreview: {
                                audioManager.playPreview(
                                    text: previewSample,
                                    localeIdentifier: localeIdentifier,
                                    voiceIdentifier: option.id
                                )
                            }
                        )
                    }
                }
                .padding(.top, 4)
            }

            Text("Preview phrase: \"\(previewSample)\"")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(appState.settings.speechMode == .autoDetect
                 ? "Listening starts automatically when you choose Practice. You can also tap the center microphone."
                 : "Tap the center microphone button on the phrase card to start listening.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !microphoneAuthorized || !speechAuthorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Microphone and speech recognition permissions are required for listening")
                        .font(.caption)
                }

                Button("Open Permissions") {
                    selectedSection = .system
                }
                .buttonStyle(.link)
            }
        }
    }

    private var systemSettings: some View {
        Form {
            Section("System") {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
                    .onChange(of: appState.settings.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Permissions") {
                permissionRow(
                    title: "Microphone",
                    status: microphoneStatusText,
                    isGranted: microphoneAuthorized,
                    actionTitle: microphonePermissionActionTitle,
                    action: handleMicrophonePermissionAction
                )

                permissionRow(
                    title: "Speech Recognition",
                    status: speechStatusText,
                    isGranted: speechAuthorized,
                    actionTitle: speechPermissionActionTitle,
                    action: handleSpeechPermissionAction
                )

                if !allListeningPermissionsGranted {
                    Button("Request Missing Permissions") {
                        requestMissingPermissions()
                    }
                } else {
                    Label("All listening permissions granted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Constants.Colors.successGreen)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
        }
    }

    private func exportWeakPhrasesCSV(language: AppSettings.PracticeLanguage) {
        let csv = WeakPhraseStore.shared.exportCSV(language: language)
        guard !csv.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "lingothing-weak-phrases-\(language.rawValue).csv"
        panel.allowedContentTypes = [UTType.commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSLog("Failed to export weak phrases CSV: \(error.localizedDescription)")
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private var microphoneAuthorized: Bool {
        microphoneStatus == .authorized
    }

    private var speechAuthorized: Bool {
        speechStatus == .authorized
    }

    private var allListeningPermissionsGranted: Bool {
        microphoneAuthorized && speechAuthorized
    }

    private var microphoneStatusText: String {
        switch microphoneStatus {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unavailable"
        }
    }

    private var speechStatusText: String {
        switch speechStatus {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unavailable"
        }
    }

    private var microphonePermissionActionTitle: String {
        microphoneStatus == .notDetermined ? "Request" : "Open Settings"
    }

    private var speechPermissionActionTitle: String {
        speechStatus == .notDetermined ? "Request" : "Open Settings"
    }

    private func refreshPermissionStatuses() {
        microphoneStatus = Permissions.microphoneStatus
        speechStatus = Permissions.speechStatus
    }

    private func handleMicrophonePermissionAction() {
        switch microphoneStatus {
        case .authorized:
            return
        case .notDetermined:
            Permissions.requestMicrophone { _ in
                refreshPermissionStatuses()
            }
        case .denied, .restricted:
            Permissions.openMicrophonePrivacySettings()
        @unknown default:
            Permissions.openMicrophonePrivacySettings()
        }
    }

    private func handleSpeechPermissionAction() {
        switch speechStatus {
        case .authorized:
            return
        case .notDetermined:
            Permissions.requestSpeechRecognition { _ in
                refreshPermissionStatuses()
            }
        case .denied, .restricted:
            Permissions.openSpeechPrivacySettings()
        @unknown default:
            Permissions.openSpeechPrivacySettings()
        }
    }

    private func requestMissingPermissions() {
        if microphoneStatus == .notDetermined || speechStatus == .notDetermined {
            Permissions.requestAll { _ in
                refreshPermissionStatuses()
            }
        }

        if microphoneStatus == .denied || microphoneStatus == .restricted {
            Permissions.openMicrophonePrivacySettings()
        }
        if speechStatus == .denied || speechStatus == .restricted {
            Permissions.openSpeechPrivacySettings()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        status: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isGranted ? Constants.Colors.successGreen : .secondary)
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Constants.Colors.successGreen)
            } else {
                Button(actionTitle, action: action)
            }
        }
    }

    @ViewBuilder
    private func voicePreviewRow(label: String, isSelected: Bool, onPreview: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Constants.Colors.successGreen)
                    .font(.system(size: 12))
            }
            Button(action: onPreview) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Play voice sample")
        }
    }

    private func voicePreviewSample(for language: AppSettings.PracticeLanguage) -> String {
        switch language {
        case .greek:
            return "Καλημέρα, τι κάνεις;"
        case .spanish:
            return "Hola, ¿cómo estás?"
        case .french:
            return "Bonjour, comment allez-vous ?"
        case .german:
            return "Hallo, wie geht es dir?"
        case .italian:
            return "Ciao, come stai?"
        case .turkish:
            return "Merhaba, nasılsın?"
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case categories
    case levels
    case schedule
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .categories: return "Practice Categories"
        case .levels: return "Review"
        case .schedule: return "Schedule"
        case .system: return "System"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .categories: return "square.grid.2x2"
        case .levels: return "line.3.horizontal.decrease.circle"
        case .schedule: return "clock"
        case .system: return "gearshape"
        }
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("LingoThing.settingsChanged")
}

private struct HourMenu: View {
    let selectedHour: Int
    let onSelect: (Int) -> Void
    let hourLabel: (Int) -> String

    var body: some View {
        Menu {
            ForEach(0..<24, id: \.self) { hour in
                Button(hourLabel(hour)) {
                    onSelect(hour)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(hourLabel(selectedHour))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 84)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.18))
            )
        }
        .menuStyle(.borderlessButton)
    }
}

private extension SettingsView {
    var languageOptions: [AppSettings.PracticeLanguage] {
        let available = phraseManager.availableLanguages()
        let preferredOrder = AppSettings.PracticeLanguage.allCases

        if available.isEmpty {
            return preferredOrder
        }

        var ordered = preferredOrder.filter { available.contains($0) }
        if !ordered.contains(appState.settings.practiceLanguage) {
            ordered.insert(appState.settings.practiceLanguage, at: 0)
        }
        if !ordered.contains(categoryLanguage) {
            ordered.insert(categoryLanguage, at: 0)
        }
        if !ordered.contains(levelLanguage) {
            ordered.insert(levelLanguage, at: 0)
        }
        return ordered
    }

    func availablePracticeCategories(for language: AppSettings.PracticeLanguage) -> [PhraseCategory] {
        let categories = phraseManager.availableCategories(for: language)
        if categories.isEmpty {
            return PhraseCategory.allCases
                .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        }
        return categories
    }

    func selectedCategories(for language: AppSettings.PracticeLanguage) -> Set<PhraseCategory> {
        appState.settings.enabledCategories(for: language, all: availablePracticeCategories(for: language))
    }

    func setCategory(_ category: PhraseCategory, enabled: Bool, for language: AppSettings.PracticeLanguage) {
        let available = availablePracticeCategories(for: language)
        var selected = selectedCategories(for: language)
        if enabled {
            selected.insert(category)
        } else {
            selected.remove(category)
            if selected.isEmpty {
                selected.insert(category)
            }
        }
        appState.settings.setEnabledCategories(selected, for: language, all: available)
    }
}
