import AVFoundation

final class AudioManager: NSObject {
    struct VoiceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let quality: AVSpeechSynthesisVoiceQuality

        var displayName: String {
            "\(name) • \(language) • \(qualityLabel)"
        }

        private var qualityLabel: String {
            switch quality {
            case .premium:
                return "Premium"
            case .enhanced:
                return "Enhanced"
            default:
                return "Default"
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var preferredVoice: AVSpeechSynthesisVoice?
    private var preferredLocale: String = "el-GR"
    private var preferredVoiceIdentifier: String?

    override init() {
        super.init()
        updatePreferredVoice()
    }

    func setLocale(_ localeIdentifier: String) {
        preferredLocale = localeIdentifier
        updatePreferredVoice()
    }

    func setPreferredVoiceIdentifier(_ identifier: String?) {
        preferredVoiceIdentifier = identifier
        updatePreferredVoice()
    }

    func availableVoices(for localeIdentifier: String) -> [VoiceOption] {
        let prefix = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == localeIdentifier || $0.language.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.language == localeIdentifier
                let rhsExact = rhs.language == localeIdentifier
                if lhsExact != rhsExact {
                    return lhsExact
                }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return voices.map {
            VoiceOption(
                id: $0.identifier,
                name: $0.name,
                language: $0.language,
                quality: $0.quality
            )
        }
    }

    private func updatePreferredVoice() {
        if let preferredVoiceIdentifier,
           let explicitVoice = AVSpeechSynthesisVoice(identifier: preferredVoiceIdentifier) {
            preferredVoice = explicitVoice
            return
        }

        let prefix = preferredLocale.split(separator: "-").first.map(String.init) ?? preferredLocale
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == preferredLocale || $0.language.hasPrefix(prefix) }

        let exactLocaleVoices = voices.filter { $0.language == preferredLocale }
        let candidateVoices = exactLocaleVoices.isEmpty ? voices : exactLocaleVoices

        preferredVoice = candidateVoices.max { lhs, rhs in
            if lhs.quality.rawValue == rhs.quality.rawValue {
                return lhs.name < rhs.name
            }
            return lhs.quality.rawValue < rhs.quality.rawValue
        } ?? AVSpeechSynthesisVoice(language: preferredLocale)
    }

    func play(_ phrase: Phrase) {
        // Stop any current playback
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()

        let utterance = AVSpeechUtterance(string: phrase.greek)
        utterance.voice = preferredVoice
        utterance.rate = Constants.Speech.ttsRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        synthesizer.speak(utterance)
    }

    func playPreview(text: String, localeIdentifier: String, voiceIdentifier: String?) {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()

        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier,
           let explicitVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = explicitVoice
        } else {
            utterance.voice = bestVoice(for: localeIdentifier) ?? preferredVoice
        }
        utterance.rate = Constants.Speech.ttsRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        utterance.postUtteranceDelay = 0.05

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
    }

    private func bestVoice(for localeIdentifier: String) -> AVSpeechSynthesisVoice? {
        let prefix = localeIdentifier.split(separator: "-").first.map(String.init) ?? localeIdentifier
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == localeIdentifier || $0.language.hasPrefix(prefix) }

        let exactLocaleVoices = voices.filter { $0.language == localeIdentifier }
        let candidateVoices = exactLocaleVoices.isEmpty ? voices : exactLocaleVoices

        return candidateVoices.max { lhs, rhs in
            if lhs.quality.rawValue == rhs.quality.rawValue {
                return lhs.name < rhs.name
            }
            return lhs.quality.rawValue < rhs.quality.rawValue
        } ?? AVSpeechSynthesisVoice(language: localeIdentifier)
    }
}
