import SwiftUI

struct NotchContentView: View {
    @Bindable var appState: AppState
    let audioManager: AudioManager
    let speechManager: SpeechManager
    let phraseManager: PhraseManager
    @State private var didAutoStartForCurrentExpansion = false
    @State private var skipNextAutoStart = false
    @State private var autoStartWorkItem: DispatchWorkItem?
    @State private var audioLevels: [CGFloat] = Array(repeating: 0, count: 12)

    var body: some View {
        ZStack {
            // Background
            if appState.currentPhase != .pulse {
                islandBackground
            }

            // Content
            Group {
                switch appState.currentPhase {
                case .pulse:
                    NotchPulseView(
                        practiceLanguageDisplayName: appState.settings.practiceLanguage.displayName,
                        onPractice: {
                            beginPracticeFromPulse()
                        },
                        onLater: {
                            snoozeFromPulse()
                        }
                    )

                case .expanded:
                    if let phrase = appState.currentPhrase {
                        NotchCardView(
                            phrase: phrase,
                            isListening: false,
                            transcript: "",
                            highlightCharacters: 0,
                            audioLevels: audioLevels,
                            onPlayAudio: { playPhraseAudio(phrase) },
                            onFinishSpeaking: {},
                            onStartListening: { startListening() },
                            onReveal: { revealMeaning() },
                            onDismiss: { appState.reset() }
                        )
                    }

                case .listening:
                    if let phrase = appState.currentPhrase {
                        NotchCardView(
                            phrase: phrase,
                            isListening: true,
                            transcript: appState.transcript,
                            highlightCharacters: phraseManager.spokenProgressCharacters(
                                transcript: appState.transcript,
                                phrase: phrase
                            ),
                            audioLevels: audioLevels,
                            onPlayAudio: { playPhraseAudio(phrase) },
                            onFinishSpeaking: { stopListening() },
                            onReveal: { revealMeaning() },
                            onDismiss: {
                                speechManager.stopListening()
                                resetAudioLevels()
                                appState.reset()
                            }
                        )
                    }

                case .completion(let result):
                    if let phrase = appState.currentPhrase {
                        CompletionView(
                            phrase: phrase,
                            result: result,
                            onListen: { playPhraseAudio(phrase) },
                            onRetry: {
                                appState.transcript = ""
                                appState.currentPhase = .expanded
                            },
                            onNext: { nextPhrase() },
                            onSnooze: { snooze() },
                            onClose: { appState.reset() }
                        )
                    }

                case .idle:
                    EmptyView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: appState.currentPhase == .pulse ? .center : .top
            )
            .padding(.top, contentTopPadding)
        }
        .onChange(of: appState.currentPhase) { _, phase in
            if phase == .expanded {
                if let phrase = appState.currentPhrase {
                    maybeStartListeningAutomatically(for: phrase)
                }
            } else {
                autoStartWorkItem?.cancel()
                autoStartWorkItem = nil
                didAutoStartForCurrentExpansion = false
            }
        }
    }

    // MARK: - Actions

    private func startListening() {
        autoStartWorkItem?.cancel()
        autoStartWorkItem = nil
        guard let phrase = appState.currentPhrase else { return }
        let launchListening = {
            // If phrase audio is currently playing, stop it before opening mic.
            audioManager.stop()
            appState.currentPhase = .listening
            appState.transcript = ""

            speechManager.onResult = { transcript, isFinal in
                DispatchQueue.main.async {
                    let cleaned = cleanedTranscript(transcript, targetWordCount: phrase.greek.split(separator: " ").count)
                    appState.transcript = cleaned

                    // Fast-path completion: if partial result already matches enough of the phrase,
                    // finish immediately instead of waiting for a long finalization pause.
                    if !isFinal {
                        let progress = phraseManager.spokenProgressCharacters(transcript: cleaned, phrase: phrase)
                        let progressRatio = phrase.greek.isEmpty ? 0 : Double(progress) / Double(phrase.greek.count)
                        let liveScore = phraseManager.matchScore(transcript: cleaned, phrase: phrase)
                        let hasEnoughContent = cleaned.count >= max(6, phrase.greek.count / 2)

                        if hasEnoughContent && (progressRatio >= 0.95 || liveScore >= liveCompletionThreshold) {
                            speechManager.stopListening()
                            resetAudioLevels()
                            appState.currentPhase = .completion(completeAndRecordAttempt(transcript: cleaned, phrase: phrase))
                            return
                        }
                    }

                    guard isFinal else { return }
                    appState.currentPhase = .completion(completeAndRecordAttempt(transcript: cleaned, phrase: phrase))
                }
            }

            speechManager.onError = { _ in
                DispatchQueue.main.async {
                    guard case .listening = appState.currentPhase else { return }
                    resetAudioLevels()
                    appState.lastMatchScore = 0
                    WeakPhraseStore.shared.recordAttempt(
                        phrase: phrase,
                        language: appState.settings.practiceLanguage,
                        score: 0,
                        result: .skipped,
                        transcript: appState.transcript
                    )
                    appState.currentPhase = .completion(.skipped)
                }
            }

            speechManager.onAudioLevels = { levels in
                DispatchQueue.main.async {
                    guard case .listening = appState.currentPhase else { return }
                    audioLevels = levels
                }
            }

            do {
                try speechManager.startListening()
            } catch {
                resetAudioLevels()
                WeakPhraseStore.shared.recordAttempt(
                    phrase: phrase,
                    language: appState.settings.practiceLanguage,
                    score: 0,
                    result: .skipped,
                    transcript: appState.transcript
                )
                appState.currentPhase = .completion(.skipped)
            }
        }

        if Permissions.hasUndeterminedPermissions {
            // Dismiss overlay before system permission alert so it's not hidden behind the notch window.
            appState.currentPhase = .idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.activate(ignoringOtherApps: true)
                Permissions.requestAll { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            appState.lastMatchScore = 0
                            appState.currentPhase = .idle
                            return
                        }
                        appState.currentPhrase = phrase
                        appState.currentPhase = .expanded
                    }
                }
            }
            return
        }

        guard Permissions.microphoneAuthorized && Permissions.speechAuthorized else {
            resetAudioLevels()
            appState.currentPhase = .completion(.skipped)
            return
        }

        launchListening()
    }

    private func playPhraseAudio(_ phrase: Phrase) {
        // "Listen" should always mean app pronunciation, not microphone capture.
        autoStartWorkItem?.cancel()
        autoStartWorkItem = nil
        speechManager.stopListening()
        resetAudioLevels()
        appState.transcript = ""
        skipNextAutoStart = true
        appState.currentPhase = .expanded

        // Give AVAudioEngine a brief moment to release audio route before TTS starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard appState.currentPhrase?.id == phrase.id else { return }
            audioManager.play(phrase)
        }
    }

    private func stopListening() {
        speechManager.stopListening()
        resetAudioLevels()
        // If we have a transcript, evaluate it
        if !appState.transcript.isEmpty, let phrase = appState.currentPhrase {
            appState.currentPhase = .completion(completeAndRecordAttempt(transcript: appState.transcript, phrase: phrase))
        } else {
            appState.lastMatchScore = 0
            if let phrase = appState.currentPhrase {
                WeakPhraseStore.shared.recordAttempt(
                    phrase: phrase,
                    language: appState.settings.practiceLanguage,
                    score: 0,
                    result: .skipped,
                    transcript: appState.transcript
                )
            }
            appState.currentPhase = .completion(.skipped)
        }
    }

    private func revealMeaning() {
        speechManager.stopListening()
        resetAudioLevels()
        appState.lastMatchScore = 0
        if let phrase = appState.currentPhrase {
            WeakPhraseStore.shared.recordAttempt(
                phrase: phrase,
                language: appState.settings.practiceLanguage,
                score: 0,
                result: .skipped,
                transcript: appState.transcript
            )
        }
        appState.currentPhase = .completion(.skipped)
    }

    private func nextPhrase() {
        if let phrase = phraseManager.nextPhrase() {
            appState.currentPhrase = phrase
            appState.transcript = ""
            appState.currentPhase = .expanded
        } else {
            appState.reset()
        }
    }

    private func snooze() {
        appState.reset()
        // The scheduler will handle the snooze delay
        NotificationCenter.default.post(name: .snoozeRequested, object: nil)
    }

    private func maybeStartListeningAutomatically(for phrase: Phrase) {
        guard appState.settings.speechMode == .autoDetect else { return }
        if skipNextAutoStart {
            skipNextAutoStart = false
            return
        }
        guard !didAutoStartForCurrentExpansion else { return }

        didAutoStartForCurrentExpansion = true
        autoStartWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard appState.currentPhase == .expanded else { return }
            guard appState.currentPhrase?.id == phrase.id else { return }
            startListening()
        }
        autoStartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func completionResult(for transcript: String, phrase: Phrase) -> MatchResult {
        let score = phraseManager.matchScore(transcript: transcript, phrase: phrase)
        appState.lastMatchScore = score
        if score >= goodMatchThreshold { return .good }
        if score >= closeMatchThreshold { return .close }
        return .tryAgain
    }

    private func completeAndRecordAttempt(transcript: String, phrase: Phrase) -> MatchResult {
        let result = completionResult(for: transcript, phrase: phrase)
        WeakPhraseStore.shared.recordAttempt(
            phrase: phrase,
            language: appState.settings.practiceLanguage,
            score: appState.lastMatchScore,
            result: result,
            transcript: transcript
        )
        return result
    }

    private var goodMatchThreshold: Double {
        switch appState.settings.practiceLanguage {
        case .french:
            return 0.86
        default:
            return 0.9
        }
    }

    private var closeMatchThreshold: Double {
        switch appState.settings.practiceLanguage {
        case .french:
            return 0.62
        default:
            return Constants.Speech.matchThreshold
        }
    }

    private var liveCompletionThreshold: Double {
        switch appState.settings.practiceLanguage {
        case .french:
            return 0.88
        default:
            return 0.93
        }
    }

    private func resetAudioLevels() {
        audioLevels = Array(repeating: 0, count: 12)
    }

    private func snoozeFromPulse() {
        appState.reset()
        NotificationCenter.default.post(name: .snoozeRequested, object: nil)
    }

    private func beginPracticeFromPulse() {
        if appState.currentPhrase == nil {
            appState.currentPhrase = phraseManager.nextPhrase()
        }

        guard appState.currentPhrase != nil else {
            appState.currentPhase = .idle
            return
        }

        withAnimation(.spring(duration: 0.25)) {
            appState.currentPhase = .expanded
        }
    }

    private func cleanedTranscript(_ transcript: String, targetWordCount: Int) -> String {
        let words = transcript
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var deduped: [String] = []
        deduped.reserveCapacity(words.count)

        for word in words {
            let normalized = normalizedWord(word)
            if let last = deduped.last, normalizedWord(last) == normalized, !normalized.isEmpty {
                continue
            }
            deduped.append(word)
        }

        let maxWords = max(4, targetWordCount + 4)
        if deduped.count > maxWords {
            deduped = Array(deduped.prefix(maxWords))
        }
        return deduped.joined(separator: " ")
    }

    private func normalizedWord(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private var islandBackground: some View {
        let shape = NotchedPanelShape(
            cornerRadius: 30,
            notchWidth: notchCutoutWidth,
            notchHeight: Constants.Layout.notchCutoutHeight,
            notchYOffset: Constants.Layout.notchCutoutOffsetY,
            notchCornerRadius: 12
        )

        return shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.995),
                        Color.black.opacity(0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                style: FillStyle(eoFill: true)
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.06), lineWidth: 0.8)
            )
            .overlay(alignment: .top) {
                // Fill part of the notch cutout with a darker top bridge so the card
                // appears to merge into the hardware notch area.
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.995))
                    .frame(width: notchCutoutWidth + 24, height: Constants.Layout.notchCutoutHeight + 14)
                    .offset(y: Constants.Layout.notchCutoutOffsetY - 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                    )
            }
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private var notchCutoutWidth: CGFloat {
        ScreenGeometry.notchCutoutWidth()
    }

    private var contentTopPadding: CGFloat {
        switch appState.currentPhase {
        case .pulse, .idle:
            return 0
        case .expanded, .listening:
            return 16
        case .completion:
            return 24
        }
    }
}

private struct NotchedPanelShape: Shape {
    let cornerRadius: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchYOffset: CGFloat
    let notchCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )

        let cutout = CGRect(
            x: rect.midX - notchWidth / 2,
            y: notchYOffset,
            width: notchWidth,
            height: notchHeight
        )
        path.addRoundedRect(
            in: cutout,
            cornerSize: CGSize(width: notchCornerRadius, height: notchCornerRadius),
            style: .continuous
        )

        return path
    }
}

extension Notification.Name {
    static let snoozeRequested = Notification.Name("LingoThing.snoozeRequested")
}
