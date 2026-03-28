import SwiftUI

struct SpeakingIndicatorView: View {
    let levels: [CGFloat]
    let isListening: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(displayLevels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Constants.Colors.accentBlue)
                    .frame(width: 4, height: 8 + displayLevels[index] * 20)
            }
        }
        .frame(height: 32)
    }

    private var displayLevels: [CGFloat] {
        if isListening {
            let recent = Array(levels.suffix(6))
            if recent.count < 6 {
                return Array(repeating: 0.05, count: 6 - recent.count) + recent
            }
            return recent
        }
        return Array(repeating: 0.08, count: 6)
    }
}
