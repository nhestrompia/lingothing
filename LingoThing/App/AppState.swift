import SwiftUI
import Observation
import Foundation

enum AppPhase: Equatable {
    case idle
    case pulse
    case expanded
    case listening
    case completion(MatchResult)
}

enum MatchResult: Equatable {
    case good
    case close
    case tryAgain
    case skipped
}

@Observable
final class AppState {
    var currentPhase: AppPhase = .idle
    var currentPhrase: Phrase?
    var transcript: String = ""
    var lastMatchScore: Double = 0
    var settings: AppSettings = AppSettings.load()

    var isActive: Bool {
        currentPhase != .idle
    }

    func reset() {
        currentPhase = .idle
        currentPhrase = nil
        transcript = ""
        lastMatchScore = 0
    }
}

struct WeakPhraseEntry: Codable, Identifiable, Hashable {
    let id: String
    let language: String
    let phraseID: String
    let phraseText: String
    let transliteration: String
    let english: String
    let category: String
    let level: String
    let difficulty: Int
    var attempts: Int
    var lastScore: Double
    var bestScore: Double
    var lastResult: String
    var lastTranscript: String
    var updatedAt: Date
}

final class WeakPhraseStore {
    static let shared = WeakPhraseStore()

    private let key = "WeakPhraseStore.entries"
    private var entriesByID: [String: WeakPhraseEntry] = [:]
    private let iso = ISO8601DateFormatter()

    private init() {
        load()
    }

    func allEntries() -> [WeakPhraseEntry] {
        entriesByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func count(for language: AppSettings.PracticeLanguage? = nil) -> Int {
        guard let language else { return entriesByID.count }
        return entriesByID.values.filter { $0.language == language.rawValue }.count
    }

    func recordAttempt(
        phrase: Phrase,
        language: AppSettings.PracticeLanguage,
        score: Double,
        result: MatchResult,
        transcript: String
    ) {
        guard result != .good else { return }

        let key = "\(language.rawValue):\(phrase.id)"
        let now = Date()
        var entry = entriesByID[key] ?? WeakPhraseEntry(
            id: key,
            language: language.rawValue,
            phraseID: phrase.id,
            phraseText: phrase.greek,
            transliteration: phrase.transliteration,
            english: phrase.english,
            category: phrase.category.rawValue,
            level: phrase.practiceLevel.rawValue,
            difficulty: phrase.difficulty,
            attempts: 0,
            lastScore: 0,
            bestScore: 0,
            lastResult: "\(result)",
            lastTranscript: "",
            updatedAt: now
        )

        entry.attempts += 1
        entry.lastScore = score
        entry.bestScore = max(entry.bestScore, score)
        entry.lastResult = "\(result)"
        entry.lastTranscript = transcript
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        entry.updatedAt = now

        entriesByID[key] = entry
        save()
    }

    func exportCSV(language: AppSettings.PracticeLanguage? = nil) -> String {
        let rows = allEntries().filter { entry in
            guard let language else { return true }
            return entry.language == language.rawValue
        }

        let headers = [
            "language",
            "phrase_id",
            "phrase",
            "transliteration",
            "english",
            "category",
            "level",
            "difficulty",
            "attempts",
            "last_score",
            "best_score",
            "last_result",
            "last_transcript",
            "updated_at"
        ]

        var lines: [String] = [headers.joined(separator: ",")]
        lines.reserveCapacity(rows.count + 1)

        for row in rows {
            let fields: [String] = [
                row.language,
                row.phraseID,
                row.phraseText,
                row.transliteration,
                row.english,
                row.category,
                row.level,
                "\(row.difficulty)",
                "\(row.attempts)",
                String(format: "%.4f", row.lastScore),
                String(format: "%.4f", row.bestScore),
                row.lastResult,
                row.lastTranscript,
                iso.string(from: row.updatedAt)
            ]
            lines.append(fields.map(csvEscaped).joined(separator: ","))
        }

        return lines.joined(separator: "\n")
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WeakPhraseEntry].self, from: data) else {
            entriesByID = [:]
            return
        }
        entriesByID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func save() {
        let entries = Array(entriesByID.values)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
