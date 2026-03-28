import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState
    let phraseManager: PhraseManager
    let audioManager: AudioManager
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("LingoThing")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if appState.settings.isPaused {
                    Label("Paused", systemImage: "pause.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Phrases").tag(0)
                Text("Settings").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Content
            Group {
                switch selectedTab {
                case 0:
                    PhraseListView(
                        phraseManager: phraseManager,
                        audioManager: audioManager
                    )
                case 1:
                    SettingsView(appState: appState, phraseManager: phraseManager, audioManager: audioManager)
                default:
                    EmptyView()
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(phraseManager.activePhraseCount()) \(appState.settings.practiceLanguage.displayName) phrases")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 420)
    }
}
