import SwiftUI

struct NotchPulseView: View {
    let practiceLanguageDisplayName: String
    var onPractice: () -> Void
    var onLater: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onLater) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.15, blue: 0.2),
                                    Color(red: 0.09, green: 0.1, blue: 0.14)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("\(practiceLanguageDisplayName) Practice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                Text("Quick 20-second drill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.66))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onPractice) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Practice")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.white.opacity(0.97))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.29, green: 0.56, blue: 1.0),
                                Color(red: 0.23, green: 0.72, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.3), lineWidth: 0.7)
                )
                .shadow(color: Color(red: 0.24, green: 0.56, blue: 1.0).opacity(0.2), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
