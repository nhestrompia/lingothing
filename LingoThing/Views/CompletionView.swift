import SwiftUI

struct CompletionView: View {
    let phrase: Phrase
    let result: MatchResult
    var onListen: () -> Void
    var onRetry: () -> Void
    var onNext: () -> Void
    var onSnooze: () -> Void
    var onClose: () -> Void

    @State private var showMeaning = false
    @State private var timerStart = Date()

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                AutoDismissCountdownView(
                    startedAt: timerStart,
                    duration: Constants.Animation.completionAutoDismissSeconds
                )
                .padding(.trailing, 10)
            }

            // Result indicator
            HStack(spacing: 8) {
                Image(systemName: resultIcon)
                    .foregroundStyle(resultColor)
                Text(resultText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(resultColor)
            }

            // Greek phrase
            Text(phrase.greek)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Constants.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            // English meaning reveal
            if showMeaning {
                VStack(spacing: 4) {
                    Text(phrase.english)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Constants.Colors.accentBlue)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Text(phrase.transliteration)
                        .font(.system(size: 13))
                        .foregroundStyle(Constants.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }

            // Actions
            HStack(spacing: 8) {
                ActionButton(icon: "headphones", label: "Listen", action: onListen)
                ActionButton(icon: "moon.zzz", label: "Snooze", action: onSnooze)
                ActionButton(icon: "forward", label: "Next", isPrimary: true, action: onNext)
                ActionButton(icon: "arrow.counterclockwise", label: "Retry", action: onRetry)
                ActionButton(icon: "xmark", label: "Close", action: onClose)
            }
        }
        .padding(20)
        .onAppear {
            timerStart = Date()
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                showMeaning = true
            }
        }
    }

    private var resultIcon: String {
        switch result {
        case .good: return "checkmark.circle.fill"
        case .close: return "hand.thumbsup.fill"
        case .tryAgain: return "arrow.clockwise"
        case .skipped: return "eye.fill"
        }
    }

    private var resultColor: Color {
        switch result {
        case .good: return Constants.Colors.successGreen
        case .close: return Constants.Colors.warningOrange
        case .tryAgain: return .red.opacity(0.8)
        case .skipped: return Constants.Colors.textSecondary
        }
    }

    private var resultText: String {
        switch result {
        case .good: return "Nice!"
        case .close: return "Close enough"
        case .tryAgain: return "Try again"
        case .skipped: return "Revealed"
        }
    }
}

private struct AutoDismissCountdownView: View {
    let startedAt: Date
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let clampedElapsed = min(duration, elapsed)
            let progress = duration > 0 ? clampedElapsed / duration : 1
            let remaining = max(0, Int(ceil(duration - clampedElapsed)))

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, 1 - progress))
                    .stroke(
                        Constants.Colors.accentBlue,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(remaining)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Constants.Colors.textPrimary)
            }
            .frame(width: 28, height: 28)
        }
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 52, height: 44)
            .foregroundStyle(isPrimary ? .white : Constants.Colors.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPrimary ? Constants.Colors.accentBlue.opacity(0.3) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
