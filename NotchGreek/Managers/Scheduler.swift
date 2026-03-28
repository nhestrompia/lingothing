import Foundation
import AppKit

final class Scheduler {
    private var timer: Timer?
    private var snoozeTimer: Timer?
    private let appState: AppState
    private let phraseManager: PhraseManager
    private var isSnoozed = false

    init(appState: AppState, phraseManager: PhraseManager) {
        self.appState = appState
        self.phraseManager = phraseManager

        // Listen for screen sleep/wake
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Listen for snooze
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSnooze),
            name: .snoozeRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .settingsChanged,
            object: nil
        )
    }

    deinit {
        stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        stop()
        let interval = TimeInterval(appState.settings.intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fire()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        snoozeTimer?.invalidate()
        snoozeTimer = nil
    }

    func restart() {
        start()
    }

    private func fire() {
        guard !appState.settings.isPaused else { return }
        guard !isSnoozed else { return }
        guard isWithinActiveHours() else { return }
        guard appState.currentPhase == .idle else { return }

        if let phrase = phraseManager.nextPhrase() {
            appState.currentPhrase = phrase
            appState.currentPhase = .pulse
        }
    }

    private func isWithinActiveHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        let start = appState.settings.activeHoursStart
        let end = appState.settings.activeHoursEnd

        if start <= end {
            return hour >= start && hour < end
        } else {
            // Wraps midnight
            return hour >= start || hour < end
        }
    }

    @objc private func screenDidSleep() {
        stop()
    }

    @objc private func screenDidWake() {
        start()
    }

    @objc private func handleSnooze() {
        isSnoozed = true
        snoozeTimer?.invalidate()
        let minutes = max(1, appState.settings.snoozeMinutes)
        snoozeTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            self?.isSnoozed = false
        }
    }

    @objc private func handleSettingsChanged() {
        restart()
    }
}
