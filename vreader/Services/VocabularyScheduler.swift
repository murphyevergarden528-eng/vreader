// Pinned FSRS-6 adapter. Persist the entire Card and ReviewLog, not just a due date.
import Foundation
import FSRS

enum VocabularyCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

enum VocabularyScheduler {
    static let revision = "4fbaf20184d62f82a9f44f343337c61a2c5483e9"
    static let parameters = FSRSParameters(requestRetention: 0.9,
        w: FSRSDefaults.defaultWv6, enableFuzz: false)

    static func initialCard(at date: Date) throws -> Data {
        try VocabularyCoding.encode(Card(due: date))
    }

    static func card(from data: Data) throws -> Card {
        let card = try VocabularyCoding.decode(Card.self, from: data)
        try validate(card)
        return card
    }

    static func review(_ card: Card, rating: VocabularyRating, now: Date) throws -> RecordLogItem {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              card.lastReview.map({ now >= $0 }) ?? true else { throw VocabularyError.invalidState }
        if card.state != .new && card.due > now { throw VocabularyError.notDue }
        let grade: Rating
        switch rating {
        case .again: grade = .again
        case .hard: grade = .hard
        case .good: grade = .good
        case .easy: grade = .easy
        }
        let result = try FSRS(parameters: parameters).next(card: card, now: now, grade: grade)
        try validate(result.card)
        return result
    }

    static func validate(_ card: Card) throws {
        let numbers = [card.stability, card.difficulty, card.elapsedDays, card.scheduledDays]
        guard card.due.timeIntervalSinceReferenceDate.isFinite,
              numbers.allSatisfy({ $0.isFinite && $0 >= 0 }), card.difficulty <= 10,
              card.reps >= 0, card.lapses >= 0, card.lapses <= card.reps,
              card.learningSteps >= 0,
              card.lastReview.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true
        else { throw VocabularyError.invalidState }
        if card.state == .new {
            guard card.reps == 0, card.lapses == 0, card.lastReview == nil,
                  card.stability == 0, card.difficulty == 0, card.learningSteps == 0,
                  card.elapsedDays == 0, card.scheduledDays == 0 else { throw VocabularyError.invalidState }
        } else {
            let stepCount = card.state == .relearning ? parameters.relearningSteps.count : parameters.learningSteps.count
            guard card.state == .review ? card.learningSteps == 0 : card.learningSteps < stepCount
            else { throw VocabularyError.invalidState }
            guard card.reps > 0, card.lastReview != nil, card.stability > 0,
                  card.difficulty >= 1 else { throw VocabularyError.invalidState }
        }
    }
}
