import Foundation

struct Phrase: Codable, Identifiable, Hashable {
    let id: String
    let greek: String
    let transliteration: String
    let english: String
    let category: PhraseCategory
    let difficulty: Int
    let acceptedPronunciations: [String]
    let contextNote: String?
}

extension Phrase {
    var practiceLevel: AppSettings.PracticeLevelFilter {
        switch difficulty {
        case ..<2:
            return .beginner
        case 2:
            return .intermediate
        default:
            return .advanced
        }
    }

    func matches(levelFilter: AppSettings.PracticeLevelFilter) -> Bool {
        switch levelFilter {
        case .all:
            return true
        case .beginner, .intermediate, .advanced:
            return practiceLevel == levelFilter
        }
    }
}

enum PhraseCategory: String, Codable, CaseIterable, Identifiable {
    case adjectives
    case airport
    case animals
    case cafe
    case clothes
    case colors
    case commonPhrases = "common-phrases"
    case countries
    case dailySentences = "daily-sentences"
    case daysMonths = "days-months"
    case directions
    case emergency
    case family
    case foodDrink = "food-drink"
    case furniture
    case greetings
    case groceries
    case gym
    case health
    case hospital
    case instruments
    case introduction
    case kitchenware
    case market
    case numbers
    case occupations
    case problems
    case questions
    case restaurant
    case shopping
    case social
    case time
    case transport
    case verbs
    case weather

    var id: String { rawValue }

    var displayName: String {
        rawValue
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    var icon: String {
        switch self {
        case .adjectives: return "textformat.abc"
        case .airport: return "airplane"
        case .animals: return "pawprint"
        case .cafe: return "cup.and.saucer"
        case .clothes: return "tshirt"
        case .colors: return "paintpalette"
        case .commonPhrases: return "text.quote"
        case .countries: return "globe.europe.africa"
        case .dailySentences: return "text.bubble"
        case .daysMonths: return "calendar"
        case .greetings: return "hand.wave"
        case .restaurant: return "fork.knife"
        case .shopping: return "bag"
        case .directions: return "map"
        case .emergency: return "exclamationmark.triangle"
        case .family: return "person.3"
        case .foodDrink: return "fork.knife.circle"
        case .furniture: return "bed.double"
        case .groceries: return "cart"
        case .gym: return "figure.strengthtraining.traditional"
        case .health: return "cross.case"
        case .hospital: return "cross.vial"
        case .instruments: return "music.note"
        case .introduction: return "person.crop.circle.badge.plus"
        case .kitchenware: return "frying.pan"
        case .market: return "storefront"
        case .social: return "person.2"
        case .numbers: return "number"
        case .occupations: return "briefcase"
        case .problems: return "exclamationmark.bubble"
        case .questions: return "questionmark.circle"
        case .time: return "clock"
        case .transport: return "car"
        case .verbs: return "text.book.closed"
        case .weather: return "cloud.sun"
        }
    }
}
