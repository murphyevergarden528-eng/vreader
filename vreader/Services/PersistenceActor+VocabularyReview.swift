// Revision and operation identity protect against stale pages and repeated submissions.
import Foundation
import SwiftData

extension PersistenceActor {
    func reviewVocabulary(id: UUID, expectedRevision: Int, operationID: UUID,
                          rating: VocabularyRating, now: Date) throws -> VocabularyRecord {
        let context = vocabularyContext()
        do {
            guard let entry = try vocabularyEntry(id: id, in: context) else { throw VocabularyError.notFound }
            let operations = try context.fetch(FetchDescriptor<VocabularyReviewEvent>(
                predicate: #Predicate { $0.id == operationID }))
            if let operation = operations.first {
                guard operation.entryID == id else { throw VocabularyError.operationConflict }
                return try vocabularyRecord(entry, in: context)
            }
            guard entry.revision == expectedRevision else { throw VocabularyError.staleRevision }
            guard entry.revision < Int.max else { throw VocabularyError.invalidState }
            guard !entry.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw VocabularyError.missingDefinition }
            let before = try VocabularyScheduler.card(from: entry.cardData)
            let result = try VocabularyScheduler.review(before, rating: rating, now: now)
            let nextData = try VocabularyCoding.encode(result.card)
            let event = VocabularyReviewEvent(id: operationID, entryID: id, rating: rating.rawValue,
                reviewedAt: now, revisionBefore: entry.revision, revisionAfter: entry.revision + 1,
                beforeCardData: entry.cardData, afterCardData: nextData,
                logData: try VocabularyCoding.encode(result.log))
            entry.cardData = nextData
            entry.dueAt = result.card.due
            entry.revision += 1
            entry.updatedAt = now
            context.insert(event)
            // There is no await between checking revision and saving the event and card.
            try context.save()
            return try vocabularyRecord(entry, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
