import Speech
import AVFoundation
import CoreGraphics
import Foundation

final class SpeechManager: NSObject, SFSpeechRecognizerDelegate {
    private var recognizer: SFSpeechRecognizer?
    private var localeIdentifier: String = "el-GR"
    private var audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer: Timer?
    private var configurationChangeObserver: NSObjectProtocol?
    private var pendingRestartWorkItem: DispatchWorkItem?
    private var latestTranscript = ""
    private var ignoreRecognitionCallbacks = false
    private var isListeningSessionActive = false
    private var retryCount = 0
    private let maxRetries = 6
    private var audioLevels: [CGFloat] = Array(repeating: 0, count: 12)
    private var lastAudioPublishAt: TimeInterval = 0
    private var lastPartialResultPublishAt: TimeInterval = 0

    var onResult: ((String, Bool) -> Void)?
    var onError: ((Error?) -> Void)?
    var onAudioLevels: (([CGFloat]) -> Void)?

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    override init() {
        super.init()
        configureRecognizer(for: localeIdentifier)
    }

    func setLocale(_ identifier: String) {
        if localeIdentifier == identifier { return }
        localeIdentifier = identifier
        stopListening()
        configureRecognizer(for: identifier)
    }

    private func configureRecognizer(for identifier: String) {
        let requestedLocale = Locale(identifier: identifier)
        var chosenRecognizer = SFSpeechRecognizer(locale: requestedLocale)

        if chosenRecognizer == nil {
            let requestedLanguageCode = requestedLocale.language.languageCode?.identifier
                ?? identifier.split(separator: "-").first.map(String.init)

            if let languageCode = requestedLanguageCode {
                let fallbackLocale = SFSpeechRecognizer.supportedLocales()
                    .sorted { $0.identifier < $1.identifier }
                    .first { locale in
                        let localeID = locale.identifier.lowercased()
                        let code = languageCode.lowercased()
                        return localeID == code || localeID.hasPrefix("\(code)-")
                    }

                if let fallbackLocale {
                    chosenRecognizer = SFSpeechRecognizer(locale: fallbackLocale)
                }
            }
        }

        chosenRecognizer?.delegate = self
        self.recognizer = chosenRecognizer
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    completion(true)
                default:
                    completion(false)
                }
            }
        }
    }

    func startListening() throws {
        stopListening()
        isListeningSessionActive = true
        latestTranscript = ""
        ignoreRecognitionCallbacks = false
        retryCount = 0
        lastAudioPublishAt = 0
        lastPartialResultPublishAt = 0
        resetAudioLevels()
        try beginRecognition()
    }

    func stopListening() {
        isListeningSessionActive = false
        ignoreRecognitionCallbacks = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil
        cleanupRecognitionResources()
        resetAudioLevels()
    }

    private func beginRecognition() throws {
        cleanupRecognitionResources()
        audioEngine = AVAudioEngine()

        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.unavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        observeAudioConfigurationChanges()

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw SpeechError.audioInputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.trackAudio(buffer: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw error
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            guard !self.ignoreRecognitionCallbacks else { return }

            if let result {
                let transcript = result.bestTranscription.formattedString
                self.latestTranscript = transcript
                let now = Date().timeIntervalSinceReferenceDate
                if result.isFinal || now - self.lastPartialResultPublishAt >= 0.12 {
                    self.lastPartialResultPublishAt = now
                    self.onResult?(transcript, result.isFinal)
                }

                // Reset silence timer on new results
                self.resetSilenceTimer()

                if result.isFinal {
                    self.stopListening()
                }
            }

            if let error {
                self.handleRecognitionFailure(error)
            }
        }

        recognitionRequest = request
        startSilenceTimer()
    }

    private func cleanupRecognitionResources() {
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationChangeObserver = nil
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.reset()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func observeAudioConfigurationChanges() {
        if let observer = configurationChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard self.isListeningSessionActive else { return }
            self.scheduleRestart(after: 0.35)
        }
    }

    // MARK: - Audio Tracking

    private var silentFrameCount = 0
    private let silentFrameThreshold = 24

    private func trackAudio(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0
        for i in 0..<frameLength {
            rms += channelData[i] * channelData[i]
        }
        rms = sqrtf(rms / Float(frameLength))
        let db = 20 * log10f(max(rms, 1e-10))
        let normalized = CGFloat(min(max((db + 60) / 60, 0), 1))

        if db < Constants.Speech.silenceThresholdDB {
            silentFrameCount += 1
        } else {
            silentFrameCount = 0
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = Date().timeIntervalSinceReferenceDate
            guard now - self.lastAudioPublishAt >= 0.05 else { return } // cap UI updates to ~20fps
            self.lastAudioPublishAt = now
            self.audioLevels.removeFirst()
            self.audioLevels.append(normalized)
            self.onAudioLevels?(self.audioLevels)
        }
    }

    private func startSilenceTimer() {
        silentFrameCount = 0
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: Constants.Speech.silenceTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.silentFrameCount > self.silentFrameThreshold {
                self.handleSilenceTimeout()
            } else {
                self.resetSilenceTimer()
            }
        }
    }

    private func resetAudioLevels() {
        audioLevels = Array(repeating: 0, count: 12)
        onAudioLevels?(audioLevels)
    }

    private func handleSilenceTimeout() {
        let transcript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if transcript.isEmpty {
            stopListening()
            onError?(SpeechError.noInput)
            return
        }

        stopListening()
        onResult?(transcript, true)
    }

    // MARK: - Failure Handling

    private func handleRecognitionFailure(_ error: Error) {
        guard isListeningSessionActive else { return }
        scheduleRestartOrFail(lastError: error)
    }

    private func scheduleRestartOrFail(lastError: Error) {
        guard retryCount < maxRetries else {
            stopListening()
            onError?(lastError)
            return
        }

        retryCount += 1
        let delay = min(0.25 * Double(retryCount), 1.2)
        scheduleRestart(after: delay)
    }

    private func scheduleRestart(after delay: TimeInterval) {
        pendingRestartWorkItem?.cancel()
        cleanupRecognitionResources()
        silentFrameCount = 0

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isListeningSessionActive else { return }
            self.ignoreRecognitionCallbacks = false
            do {
                try self.beginRecognition()
            } catch {
                self.scheduleRestartOrFail(lastError: error)
            }
        }

        pendingRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            stopListening()
            onError?(SpeechError.unavailable)
        }
    }
}

enum SpeechError: Error, LocalizedError {
    case unavailable
    case notAuthorized
    case noInput
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Speech recognition unavailable (network required)"
        case .notAuthorized: return "Speech recognition not authorized"
        case .noInput: return "No microphone input detected"
        case .audioInputUnavailable: return "Audio input unavailable"
        }
    }
}
