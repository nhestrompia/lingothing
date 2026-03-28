import SwiftUI

struct PhraseListView: View {
    let phraseManager: PhraseManager
    let audioManager: AudioManager
    @State private var searchText = ""
    @State private var selectedCategory: PhraseCategory?

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search phrases...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Category filter
            HStack {
                Label("Category", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(PhraseCategory?.none)
                    ForEach(PhraseCategory.allCases) { category in
                        Text(category.displayName).tag(PhraseCategory?.some(category))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Phrase list
            List {
                ForEach(filteredPhrases) { phrase in
                    PhraseRow(phrase: phrase, audioManager: audioManager)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredPhrases: [Phrase] {
        var results = phraseManager.phrases

        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter {
                $0.greek.lowercased().contains(query) ||
                $0.english.lowercased().contains(query) ||
                $0.transliteration.lowercased().contains(query)
            }
        }

        return results
    }
}

struct PhraseRow: View {
    let phrase: Phrase
    let audioManager: AudioManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(phrase.greek)
                    .font(.system(size: 14, weight: .medium))
                Text(phrase.english)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(phrase.practiceLevel.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            Spacer()

            Button {
                audioManager.play(phrase)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
