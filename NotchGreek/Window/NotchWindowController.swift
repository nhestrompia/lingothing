import AppKit
import SwiftUI
import Observation

final class NotchWindowController {
    private var window: NotchWindow?
    private var hostingView: NotchHostingView?
    private let appState: AppState
    private let phraseManager: PhraseManager
    private let audioManager: AudioManager
    private let speechManager: SpeechManager
    private var pulseTimer: Timer?
    private var completionDismissWorkItem: DispatchWorkItem?
    private var observation: Any?
    private var renderedPhase: AppPhase = .idle
    private var activeScreen: NSScreen?

    init(appState: AppState, phraseManager: PhraseManager, audioManager: AudioManager, speechManager: SpeechManager) {
        self.appState = appState
        self.phraseManager = phraseManager
        self.audioManager = audioManager
        self.speechManager = speechManager

        setupObservation()
    }

    private func setupObservation() {
        observation = withObservationTracking {
            _ = self.appState.currentPhase
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.handlePhaseChange()
                self?.setupObservation()
            }
        }
    }

    private func handlePhaseChange() {
        let previousPhase = renderedPhase
        renderedPhase = appState.currentPhase

        if case .completion = appState.currentPhase {
            // Keep current completion timer logic.
        } else {
            completionDismissWorkItem?.cancel()
            completionDismissWorkItem = nil
        }

        switch appState.currentPhase {
        case .idle:
            dismissWindow(from: previousPhase)
        case .pulse:
            showPulse()
        case .expanded:
            expandToCard(height: Constants.Layout.cardHeight)
        case .listening:
            resizeCard(height: Constants.Layout.cardHeight)
            updateContent()
        case .completion:
            resizeCard(height: Constants.Layout.cardHeight)
            updateContent()
        }
    }

    // MARK: - Pulse

    private func showPulse() {
        if appState.currentPhrase == nil {
            appState.currentPhrase = phraseManager.nextPhrase()
        }

        let geometryScreen = activeScreen ?? window?.screen ?? ScreenGeometry.targetScreen()
        let targetFrame = ScreenGeometry.pulseFrame(for: geometryScreen)
        let compactFrame = ScreenGeometry.pulseCompactFrame(for: geometryScreen)
        let isNewWindow = window == nil
        let window = ensureWindow(frame: isNewWindow ? compactFrame : targetFrame)
        activeScreen = window.screen ?? geometryScreen

        if isNewWindow {
            window.alphaValue = 0
            window.setFrame(compactFrame, display: false)
            window.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.Animation.pulseMorphInDuration
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.86, 0.2, 1.0)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1
            }
        }

        // Auto-dismiss after timeout
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: Constants.Animation.pulseTimeoutSeconds, repeats: false) { [weak self] _ in
            guard self?.appState.currentPhase == .pulse else { return }
            self?.appState.currentPhase = .idle
        }
    }

    // MARK: - Expand

    private func expandToCard(height: CGFloat) {
        if window == nil {
            showPulse()
        }
        guard let window else { return }

        pulseTimer?.invalidate()
        pulseTimer = nil

        let geometryScreen = window.screen ?? activeScreen
        let targetFrame = ScreenGeometry.expandedCardFrame(for: geometryScreen, height: height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.2, 1.0)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func resizeCard(height: CGFloat) {
        guard let window else { return }
        let geometryScreen = window.screen ?? activeScreen
        let targetFrame = ScreenGeometry.expandedCardFrame(for: geometryScreen, height: height)
        let frameChanged = abs(window.frame.height - targetFrame.height) > 0.5
            || abs(window.frame.origin.y - targetFrame.origin.y) > 0.5
        guard frameChanged else { return }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Update Content

    private func updateContent() {
        // SwiftUI view updates reactively via appState observation
        // Just ensure window is visible
        window?.makeKeyAndOrderFront(nil)

        if case .completion = appState.currentPhase {
            // Auto-dismiss after delay
            completionDismissWorkItem?.cancel()

            let expectedPhraseID = appState.currentPhrase?.id
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard case .completion = self.appState.currentPhase else { return }
                guard self.appState.currentPhrase?.id == expectedPhraseID else { return }
                self.appState.reset()
            }
            completionDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Constants.Animation.completionAutoDismissSeconds,
                execute: workItem
            )
        }
    }

    // MARK: - Dismiss

    private func dismissWindow(from previousPhase: AppPhase) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        completionDismissWorkItem?.cancel()
        completionDismissWorkItem = nil

        guard let window else { return }

        if case .pulse = previousPhase {
            let compactFrame = ScreenGeometry.pulseCompactFrame(for: window.screen ?? activeScreen)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.Animation.pulseMorphOutDuration
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.78, 0.0)
                window.animator().setFrame(compactFrame, display: true)
                window.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                window.orderOut(nil)
                window.alphaValue = 1
                self?.window = nil
                self?.hostingView = nil
                self?.activeScreen = nil
            }
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Constants.Animation.collapseDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.orderOut(nil)
            window.alphaValue = 1
            self?.window = nil
            self?.hostingView = nil
            self?.activeScreen = nil
        }
    }

    func triggerManualPractice(phrase: Phrase) {
        appState.currentPhrase = phrase
        appState.currentPhase = .expanded
    }

    private func ensureWindow(frame: NSRect) -> NotchWindow {
        if let existing = window {
            return existing
        }

        let window = NotchWindow(contentRect: frame)
        let content = NotchContentView(
            appState: appState,
            audioManager: audioManager,
            speechManager: speechManager,
            phraseManager: phraseManager
        )
        let hostingView = NotchHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        self.hostingView = hostingView
        self.window = window
        return window
    }
}
