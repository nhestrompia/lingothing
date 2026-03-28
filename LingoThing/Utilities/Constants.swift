import SwiftUI

enum Constants {
    enum Animation {
        static let expandDuration: Double = 0.25
        static let collapseDuration: Double = 0.2
        static let pulseMorphInDuration: Double = 0.34
        static let pulseMorphOutDuration: Double = 0.26
        static let pulseDuration: Double = 1.5
        static let pulseTimeoutSeconds: Double = 30
        static let completionAutoDismissSeconds: Double = 8
    }

    enum Layout {
        static let pulseWidth: CGFloat = 430
        static let pulseHeight: CGFloat = 88
        static let cardWidth: CGFloat = 364
        static let expandedCardHeight: CGFloat = 216
        static let listeningCardHeight: CGFloat = 224
        static let completionCardHeight: CGFloat = 286
        static let cardHeight: CGFloat = completionCardHeight
        static let cardCornerRadius: CGFloat = 28
        static let cardVerticalLift: CGFloat = -50
        static let cardTopMorphExtension: CGFloat = 72
        static let pulseTopOverlap: CGFloat = 12

        static let notchCutoutHeight: CGFloat = 30
        static let notchCutoutOffsetY: CGFloat = -24
        static let notchCutoutBottomInset: CGFloat = notchCutoutHeight + notchCutoutOffsetY
    }

    enum Colors {
        static let cardBackground = Color.black.opacity(0.995)
        static let pulseColor = Color.white.opacity(0.6)
        static let accentBlue = Color(red: 0.35, green: 0.6, blue: 1.0)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)
        static let successGreen = Color(red: 0.3, green: 0.85, blue: 0.5)
        static let warningOrange = Color(red: 1.0, green: 0.7, blue: 0.3)
    }

    enum Speech {
        static let silenceThresholdDB: Float = -50
        static let silenceTimeoutSeconds: Double = 1.4
        static let matchThreshold: Double = 0.7
        static let ttsRate: Float = 0.45
    }

    enum Scheduler {
        static let defaultIntervalMinutes: Int = 30
        static let defaultActiveHoursStart: Int = 9
        static let defaultActiveHoursEnd: Int = 21
        static let defaultSnoozeMinutes: Int = 15
    }
}
