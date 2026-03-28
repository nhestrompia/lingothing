import SwiftUI

struct NotchCardView: View {
    let phrase: Phrase
    let isListening: Bool
    let transcript: String
    var highlightCharacters: Int = 0
    var audioLevels: [CGFloat] = []
    var onPlayAudio: () -> Void
    var onFinishSpeaking: () -> Void
    var onStartListening: (() -> Void)? = nil
    var onReveal: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Category badge
            HStack {
                Label("\(phrase.category.displayName) • \(phrase.practiceLevel.displayName)", systemImage: phrase.category.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Constants.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            // Greek phrase
            highlightedPhraseText
                .font(.system(size: 24, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)

            // Transliteration
            Text(phrase.transliteration)
                .font(.system(size: 13))
                .foregroundStyle(Constants.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            // Transcript (when listening)
            if isListening || !transcript.isEmpty {
                Text(transcript.isEmpty ? "Listening..." : transcript)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(transcript.isEmpty ? Constants.Colors.textSecondary : Constants.Colors.accentBlue)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(minHeight: 20, alignment: .center)
            }

            // Speaking indicator
            if isListening {
                SpeakingIndicatorView(levels: audioLevels, isListening: true)
                    .frame(height: 20)
            }

            if !isListening, let note = phrase.contextNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Constants.Colors.textSecondary.opacity(0.7))
            }

            Spacer(minLength: 4)

            // Action buttons
            HStack(spacing: 16) {
                // Play audio
                Button(action: onPlayAudio) {
                    Image(systemName: "headphones")
                        .font(.system(size: 16))
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle().fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)

                if isListening {
                    Button(action: onFinishSpeaking) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Constants.Colors.successGreen))
                    }
                    .buttonStyle(.plain)
                } else if let onStartListening {
                    Button(action: onStartListening) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Constants.Colors.textPrimary)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Constants.Colors.accentBlue.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }

                // Reveal meaning
                Button(action: onReveal) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Constants.Colors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle().fill(Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 15)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var highlightedPhraseText: Text {
        let chars = Array(phrase.greek)
        let safeCount = max(0, min(highlightCharacters, chars.count))
        let prefix = String(chars.prefix(safeCount))
        let suffix = String(chars.dropFirst(safeCount))

        return Text(prefix).foregroundStyle(Constants.Colors.accentBlue)
        + Text(suffix).foregroundStyle(Constants.Colors.textPrimary)
    }
}
