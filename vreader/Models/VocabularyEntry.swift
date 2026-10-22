// Vocabulary is independent of Book's lifetime; child records reference its UUID.
import Foundation
import SwiftData

@Model
final class VocabularyEntry {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var normalizedTerm: String
    var term: String
    var definition: String
    var cardData: Data
    var dueAt: Date
    var revision: Int
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), term: String, normalizedTerm: String, definition: String,
         cardData: Data, dueAt: Date, revision: Int = 0, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.definition = definition
        self.cardData = cardData
        self.dueAt = dueAt
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class VocabularyOccurrence {
    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var bookKey: String
    var bookTitle: String
    var context: String
    var locatorData: Data?
    var createdAt: Date

    init(entryID: UUID, source: VocabularySource) {
        self.id = source.id
        self.entryID = entryID
        self.bookKey = source.bookKey
        self.bookTitle = source.bookTitle
        self.context = source.context
        self.locatorData = source.locatorData
        self.createdAt = source.createdAt
    }

    var snapshot: VocabularySource {
        VocabularySource(id: id, bookKey: bookKey, bookTitle: bookTitle, context: context,
                         locatorData: locatorData, createdAt: createdAt)
    }
}

@Model
final class VocabularyReviewEvent {
    @Attribute(.unique) var id: UUID
    var entryID: UUID
    var rating: Int
    var reviewedAt: Date
    var revisionBefore: Int
    var revisionAfter: Int
    var beforeCardData: Data
    var afterCardData: Data
    var logData: Data

    init(id: UUID, entryID: UUID, rating: Int, reviewedAt: Date,
         revisionBefore: Int, revisionAfter: Int, beforeCardData: Data,
         afterCardData: Data, logData: Data) {
        self.id = id
        self.entryID = entryID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.revisionBefore = revisionBefore
        self.revisionAfter = revisionAfter
        self.beforeCardData = beforeCardData
        self.afterCardData = afterCardData
        self.logData = logData
    }
}
