// Self-contained, versioned backups. API credentials and book bytes are never included.
import Foundation
import FSRS

struct VocabularyBackupAlgorithm: Codable, Equatable, Sendable {
    let name: String
    let revision: String
    let parameters: FSRSParameters

    static let current = VocabularyBackupAlgorithm(name: "FSRS-6",
        revision: VocabularyScheduler.revision, parameters: VocabularyScheduler.parameters)
}

struct VocabularyBackupReview: Codable, Equatable, Sendable {
    let id: UUID
    let entryID: UUID
    let rating: VocabularyRating
    let reviewedAt: Date
    let revisionBefore: Int
    let revisionAfter: Int
    let beforeCardData: Data
    let afterCardData: Data
    let logData: Data

    init(_ event: VocabularyReviewEvent) throws {
        guard let grade = VocabularyRating(rawValue: event.rating) else { throw VocabularyError.invalidState }
        id = event.id
        entryID = event.entryID
        rating = grade
        reviewedAt = event.reviewedAt
        revisionBefore = event.revisionBefore
        revisionAfter = event.revisionAfter
        beforeCardData = event.beforeCardData
        afterCardData = event.afterCardData
        logData = event.logData
    }
}

struct VocabularyBackupCard: Codable, Equatable, Sendable {
    let record: VocabularyRecord
    let reviews: [VocabularyBackupReview]
}

struct VocabularyBackup: Codable, Sendable {
    let version: Int
    let algorithm: VocabularyBackupAlgorithm
    let cards: [VocabularyBackupCard]

    func validate() throws {
        guard version == 1 else { throw VocabularyError.invalidBackup("不支持的文件版本。") }
        guard algorithm == .current else { throw VocabularyError.invalidBackup("复习算法版本不匹配。") }
        var entryIDs = Set<UUID>()
        var terms = Set<String>()
        var sourceIDs = Set<UUID>()
        var operationIDs = Set<UUID>()
        do {
            for item in cards {
                let record = item.record
                guard entryIDs.insert(record.id).inserted, terms.insert(record.normalizedTerm).inserted,
                      !record.normalizedTerm.isEmpty,
                      VocabularyNormalization.key(record.term) == record.normalizedTerm,
                      record.revision >= 0, record.revision < Int.max,
                      record.createdAt.timeIntervalSinceReferenceDate.isFinite,
                      record.updatedAt.timeIntervalSinceReferenceDate.isFinite
                else { throw VocabularyError.invalidState }
                let card = try VocabularyScheduler.card(from: record.cardData)
                guard card.due == record.dueAt, record.isNew == (card.state == .new),
                      card.reps == item.reviews.count else { throw VocabularyError.invalidState }
                for (index, source) in record.sources.enumerated() {
                    guard sourceIDs.insert(source.id).inserted,
                          !source.bookKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          source.createdAt.timeIntervalSinceReferenceDate.isFinite,
                          !record.sources.prefix(index).contains(where: { $0.identifiesSameOccurrence(as: source) })
                    else { throw VocabularyError.invalidSource }
                }
                try validateHistory(item, operationIDs: &operationIDs)
            }
        } catch {
            throw VocabularyError.invalidBackup("词条、来源或复习记录不完整。")
        }
    }

    private func validateHistory(_ item: VocabularyBackupCard, operationIDs: inout Set<UUID>) throws {
        var previous = Card(due: item.record.createdAt)
        var lastRevision = 0
        let ordered = item.reviews.sorted { $0.revisionAfter < $1.revisionAfter }
        for (index, event) in ordered.enumerated() {
            guard operationIDs.insert(event.id).inserted, event.entryID == item.record.id,
                  event.revisionBefore >= lastRevision, event.revisionBefore < Int.max,
                  event.revisionAfter == event.revisionBefore + 1,
                  event.revisionAfter <= item.record.revision,
                  event.reviewedAt.timeIntervalSinceReferenceDate.isFinite
            else { throw VocabularyError.invalidState }
            let before = try VocabularyScheduler.card(from: event.beforeCardData)
            let after = try VocabularyScheduler.card(from: event.afterCardData)
            guard before == previous, before.reps == index, after.reps == index + 1
            else { throw VocabularyError.invalidState }
            let expected = try VocabularyScheduler.review(before, rating: event.rating, now: event.reviewedAt)
            let log = try VocabularyCoding.decode(ReviewLog.self, from: event.logData)
            guard expected.card == after, expected.log == log else { throw VocabularyError.invalidState }
            previous = after
            lastRevision = event.revisionAfter
        }
        guard previous == (try VocabularyScheduler.card(from: item.record.cardData))
        else { throw VocabularyError.invalidState }
    }
}
