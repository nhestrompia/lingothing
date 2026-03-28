import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum OnboardingKeys {
        static let didRequestPermissions = "LingoThing.didRequestOnboardingPermissions"
    }

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var notchWindowController: NotchWindowController!
    private var settingsWindowController: NSWindowController?
    private var settingsObserver: NSObjectProtocol?

    let appState = AppState()
    lazy var phraseManager = PhraseManager()
    lazy var scheduler = Scheduler(appState: appState, phraseManager: phraseManager)
    lazy var audioManager = AudioManager()
    lazy var speechManager = SpeechManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupNotchWindow()
        applyPracticeLanguageSettings()
        observeSettingsChanges()
        requestOnboardingPermissionsIfNeeded { [weak self] in
            self?.scheduler.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe.europe.africa", accessibilityDescription: "LingoThing")
        }
        statusMenu = NSMenu()

        let openSettingsItem = NSMenuItem(
            title: "Open Settings",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        openSettingsItem.target = self

        let restartItem = NSMenuItem(
            title: "Restart LingoThing",
            action: #selector(restartApplication),
            keyEquivalent: "r"
        )
        restartItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit LingoThing",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self

        statusMenu.addItem(openSettingsItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(restartItem)
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    private func observeSettingsChanges() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPracticeLanguageSettings()
        }
    }

    private func applyPracticeLanguageSettings() {
        let language = appState.settings.practiceLanguage
        phraseManager.reload(for: language)
        let availableCategories = phraseManager.availableCategories()
        let enabledCategories = appState.settings.enabledCategories(for: language, all: availableCategories)
        phraseManager.setActiveCategories(enabledCategories)
        phraseManager.setActiveLevelFilter(appState.settings.selectedLevelFilter(for: language))
        audioManager.setLocale(language.localeIdentifier)
        audioManager.setPreferredVoiceIdentifier(appState.settings.selectedVoiceID(for: language))
        speechManager.setLocale(language.localeIdentifier)
    }

    private func setupNotchWindow() {
        notchWindowController = NotchWindowController(
            appState: appState,
            phraseManager: phraseManager,
            audioManager: audioManager,
            speechManager: speechManager
        )
    }

    @objc private func openSettingsWindow() {
        let hostingController = NSHostingController(
            rootView: SettingsView(appState: appState, phraseManager: phraseManager, audioManager: audioManager)
        )

        if settingsWindowController == nil {
            let window = NSWindow(contentViewController: hostingController)
            window.title = "LingoThing Settings"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 780, height: 540))
            window.minSize = NSSize(width: 680, height: 500)
            window.contentMinSize = NSSize(width: 680, height: 500)
            window.center()
            window.isReleasedWhenClosed = true
            window.delegate = self
            settingsWindowController = NSWindowController(window: window)
        } else {
            settingsWindowController?.window?.contentViewController = hostingController
        }

        if let window = settingsWindowController?.window {
            window.minSize = NSSize(width: 680, height: 500)
            window.contentMinSize = NSSize(width: 680, height: 500)
            var frame = window.frame
            frame.size.width = max(frame.size.width, 780)
            frame.size.height = max(frame.size.height, 540)
            window.setFrame(frame, display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func restartApplication() {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            if let error {
                NSLog("Failed to restart LingoThing: \(error.localizedDescription)")
                return
            }
            NSApp.terminate(nil)
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func requestOnboardingPermissionsIfNeeded(completion: @escaping () -> Void) {
        let defaults = UserDefaults.standard
        let didRequestBefore = defaults.bool(forKey: OnboardingKeys.didRequestPermissions)
        if didRequestBefore && !Permissions.hasUndeterminedPermissions {
            completion()
            return
        }
        guard Permissions.hasUndeterminedPermissions else {
            defaults.set(true, forKey: OnboardingKeys.didRequestPermissions)
            completion()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
            Permissions.requestForOnboarding { _ in
                defaults.set(true, forKey: OnboardingKeys.didRequestPermissions)
                completion()
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == settingsWindowController?.window else {
            return
        }
        settingsWindowController = nil
    }
}
