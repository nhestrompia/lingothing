import Foundation

final class PhraseManager {
    private(set) var phrases: [Phrase] = []
    private(set) var activeCategories: Set<PhraseCategory> = []
    private(set) var activeLevelFilter: AppSettings.PracticeLevelFilter = .all
    private var recentlyShown: [String] = []
    private let maxRecent = 10
    private(set) var selectedLanguage: AppSettings.PracticeLanguage = .greek
    private var phraseCache: [AppSettings.PracticeLanguage: [Phrase]] = [:]

    init() {
        reload(for: .greek)
    }

    func reload(for language: AppSettings.PracticeLanguage) {
        selectedLanguage = language
        phrases = phrasesForLanguage(language)
        activeCategories = Set(phrases.map(\.category))
        recentlyShown.removeAll()
    }

    func availableLanguages() -> [AppSettings.PracticeLanguage] {
        AppSettings.PracticeLanguage.allCases.filter { !phrasesForLanguage($0).isEmpty }
    }

    func availableCategories(for language: AppSettings.PracticeLanguage) -> [PhraseCategory] {
        Array(Set(phrasesForLanguage(language).map(\.category)))
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    private func phrasesForLanguage(_ language: AppSettings.PracticeLanguage) -> [Phrase] {
        if let cached = phraseCache[language] {
            return cached
        }

        let loaded = loadPhrases(for: language)
        phraseCache[language] = loaded
        return loaded
    }

    private func loadPhrases(for language: AppSettings.PracticeLanguage) -> [Phrase] {
        for resourceName in language.resourceCandidates {
            guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([Phrase].self, from: data),
                  !decoded.isEmpty else {
                continue
            }
            return decoded.map(sanitizedPhrase)
        }
        return []
    }

    func nextPhrase(excluding: Set<String> = []) -> Phrase? {
        let candidates = phrases.filter { phrase in
            activeCategories.contains(phrase.category)
                && phrase.matches(levelFilter: activeLevelFilter)
                && !recentlyShown.contains(phrase.id)
                && !excluding.contains(phrase.id)
        }

        let fallback = phrases.filter {
            activeCategories.contains($0.category)
                && $0.matches(levelFilter: activeLevelFilter)
        }
        let chosen = candidates.isEmpty ? fallback.randomElement() : candidates.randomElement()

        if let chosen {
            recentlyShown.append(chosen.id)
            if recentlyShown.count > maxRecent {
                recentlyShown.removeFirst()
            }
        }

        return chosen
    }

    func setActiveCategories(_ categories: Set<PhraseCategory>) {
        let available = Set(phrases.map(\.category))
        if categories.isEmpty {
            activeCategories = available
        } else {
            let filtered = categories.intersection(available)
            activeCategories = filtered.isEmpty ? available : filtered
        }
        recentlyShown.removeAll()
    }

    func setActiveLevelFilter(_ filter: AppSettings.PracticeLevelFilter) {
        activeLevelFilter = filter
        recentlyShown.removeAll()
    }

    func availableCategories() -> [PhraseCategory] {
        Array(Set(phrases.map(\.category)))
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    func activePhraseCount() -> Int {
        phrases.filter {
            activeCategories.contains($0.category)
                && $0.matches(levelFilter: activeLevelFilter)
        }.count
    }

    func phrases(for category: PhraseCategory) -> [Phrase] {
        phrases.filter {
            $0.category == category
                && $0.matches(levelFilter: activeLevelFilter)
        }
    }

    private func sanitizedPhrase(_ phrase: Phrase) -> Phrase {
        Phrase(
            id: phrase.id,
            greek: cleanedSurfaceText(phrase.greek),
            transliteration: cleanedSurfaceText(phrase.transliteration),
            english: cleanedMeaningText(phrase.english),
            category: phrase.category,
            difficulty: phrase.difficulty,
            acceptedPronunciations: phrase.acceptedPronunciations
                .map(cleanedSurfaceText)
                .filter { !$0.isEmpty },
            contextNote: phrase.contextNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func cleanedMeaningText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedSurfaceText(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)

        // Drop regional variant suffixes like ", Spain: vegetales".
        if let markerRange = text.range(
            of: #",\s*[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ\s\-]{1,24}:\s*"#,
            options: .regularExpression
        ) {
            let head = text[..<markerRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !head.isEmpty {
                text = String(head)
            }
        }

        return text
    }

    func matchScore(transcript: String, phrase: Phrase) -> Double {
        let normalized = normalize(transcript)
        let target = normalize(phrase.greek)

        if normalized == target { return 1.0 }

        for accepted in phrase.acceptedPronunciations {
            if normalized == normalize(accepted) { return 1.0 }
        }

        return levenshteinSimilarity(normalized, target)
    }

    func spokenProgressCharacters(transcript: String, phrase: Phrase) -> Int {
        let spokenWords = normalize(transcript)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !spokenWords.isEmpty else { return 0 }

        let phraseWords = phrase.greek
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard !phraseWords.isEmpty else { return 0 }

        var phraseIndex = 0
        var spokenIndex = 0
        var highlightedChars = 0

        while phraseIndex < phraseWords.count, spokenIndex < spokenWords.count {
            let phraseWord = normalizeWord(phraseWords[phraseIndex])
            let spokenWord = normalizeWord(spokenWords[spokenIndex])

            if phraseWord.isEmpty {
                highlightedChars += phraseWords[phraseIndex].count
                if phraseIndex < phraseWords.count - 1 { highlightedChars += 1 }
                phraseIndex += 1
                continue
            }

            if phraseWord == spokenWord || levenshteinSimilarity(phraseWord, spokenWord) >= 0.72 {
                highlightedChars += phraseWords[phraseIndex].count
                if phraseIndex < phraseWords.count - 1 { highlightedChars += 1 }
                phraseIndex += 1
                spokenIndex += 1
                continue
            }

            if spokenIndex + 1 < spokenWords.count {
                let nextSpoken = normalizeWord(spokenWords[spokenIndex + 1])
                if phraseWord == nextSpoken || levenshteinSimilarity(phraseWord, nextSpoken) >= 0.72 {
                    spokenIndex += 1
                    continue
                }
            }

            break
        }

        return min(highlightedChars, phrase.greek.count)
    }

    private func normalize(_ text: String) -> String {
        let locale = Locale(identifier: selectedLanguage.localeIdentifier)
        let folded = text.lowercased()
            .folding(options: .diacriticInsensitive, locale: locale)
        let sanitized = String(folded.map { char in
            (char.isLetter || char.isNumber) ? char : " "
        })

        return sanitized
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func normalizeWord(_ text: String) -> String {
        normalize(text).filter { $0.isLetter || $0.isNumber }
    }

    private func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 && n == 0 { return 1.0 }
        if m == 0 || n == 0 { return 0.0 }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        let distance = Double(matrix[m][n])
        let maxLen = Double(max(m, n))
        return 1.0 - (distance / maxLen)
    }
}
