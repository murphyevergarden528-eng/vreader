// Full-file validation precedes a single all-or-nothing import save.
import Foundation
import SwiftData

extension PersistenceActor {
    func exportVocabulary() throws -> Data {
        let context = vocabularyContext()
        let entries = try context.fetch(FetchDescriptor<VocabularyEntry>())
        let events = try context.fetch(FetchDescriptor<VocabularyReviewEvent>())
        let byEntry = Dictionary(grouping: events, by: \.entryID)
        let knownIDs = Set(entries.map(\.id))
        guard events.allSatisfy({ knownIDs.contains($0.entryID) }) else { throw VocabularyError.invalidState }
        var cards: [VocabularyBackupCard] = []
        for entry in entries {
            var reviews: [VocabularyBackupReview] = []
            for event in byEntry[entry.id] ?? [] { reviews.append(try VocabularyBackupReview(event)) }
            reviews.sort { left, right in
                if left.revisionAfter == right.revisionAfter { return left.id.uuidString < right.id.uuidString }
                return left.revisionAfter < right.revisionAfter
            }
            let record = try vocabularyRecord(entry, in: context)
            cards.append(VocabularyBackupCard(record: record, reviews: reviews))
        }
        cards.sort { $0.record.id.uuidString < $1.record.id.uuidString }
        let backup = VocabularyBackup(version: 1, algorithm: .current, cards: cards)
        try backup.validate()
        return try VocabularyCoding.encode(backup)
    }

    func importVocabulary(_ data: Data) throws -> VocabularyImportResult {
        let backup: VocabularyBackup
        do {
            backup = try VocabularyCoding.decode(VocabularyBackup.self, from: data)
            try backup.validate()
        } catch let error as VocabularyError {
            throw error
        } catch {
            throw VocabularyError.invalidBackup("文件不是有效的生词 JSON 备份。")
        }
        let context = vocabularyContext()
        do {
            var added = 0
            var skipped = 0
            let localSources = Set(try context.fetch(FetchDescriptor<VocabularyOccurrence>()).map(\.id))
            let localEvents = Set(try context.fetch(FetchDescriptor<VocabularyReviewEvent>()).map(\.id))
            for item in backup.cards {
                let record = item.record
                let sameID = try vocabularyEntry(id: record.id, in: context)
                let sameTerm = try vocabularyEntry(key: record.normalizedTerm, in: context)
                if sameID != nil || sameTerm != nil {
                    skipped += 1
                    continue
                }
                // Child identifiers cannot silently replace another local card's history.
                guard record.sources.allSatisfy({ !localSources.contains($0.id) }),
                      item.reviews.allSatisfy({ !localEvents.contains($0.id) })
                else { throw VocabularyError.invalidBackup("来源或复习记录与本机其他词条冲突。") }
                let entry = VocabularyEntry(id: record.id, term: record.term,
                    normalizedTerm: record.normalizedTerm, definition: record.definition,
                    cardData: record.cardData, dueAt: record.dueAt, revision: record.revision,
                    createdAt: record.createdAt, updatedAt: record.updatedAt)
                context.insert(entry)
                for source in record.sources {
                    context.insert(VocabularyOccurrence(entryID: record.id, source: source))
                }
                for event in item.reviews {
                    context.insert(VocabularyReviewEvent(id: event.id, entryID: event.entryID,
                        rating: event.rating.rawValue, reviewedAt: event.reviewedAt,
                        revisionBefore: event.revisionBefore, revisionAfter: event.revisionAfter,
                        beforeCardData: event.beforeCardData, afterCardData: event.afterCardData,
                        logData: event.logData))
                }
                added += 1
            }
            try context.save()
            return VocabularyImportResult(added: added, skipped: skipped)
        } catch {
            context.rollback()
            throw error
        }
    }
}
