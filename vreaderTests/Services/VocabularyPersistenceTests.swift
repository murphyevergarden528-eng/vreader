import Foundation
import SwiftData
import XCTest
@testable import vreader

final class VocabularyPersistenceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(SchemaV11.models),
                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func testCollectionNormalizesUnicodeWhitespaceAndPreservesDefinitionAndSchedule() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let source = VocabularySource(bookKey: "book-a", bookTitle: "A", context: "A café.")
        let first = try await actor.saveVocabulary(term: "  Café \n noir ", definition: "coffee", source: source)
        let second = try await actor.saveVocabulary(term: "CAFE\u{301}\tNOIR", definition: "overwrite",
            source: VocabularySource(bookKey: "book-b", bookTitle: "B", context: "Another café."))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.normalizedTerm, "café noir")
        XCTAssertEqual(second.definition, "coffee")
        XCTAssertEqual(second.dueAt, first.dueAt)
        XCTAssertEqual(second.sources.count, 2)
        _ = try await actor.saveVocabulary(term: "Café noir", definition: "", source: source)
        let all = try await actor.fetchVocabulary()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sources.count, 2)
    }

    func testActorRecreationKeepsVocabularyWithNoBookRecord() async throws {
        let container = try makeContainer()
        let writer = PersistenceActor(modelContainer: container)
        let saved = try await writer.saveVocabulary(term: "独立", definition: "independent",
            source: VocabularySource(bookKey: "deleted-book", bookTitle: "Gone", context: "独立"))
        let reader = PersistenceActor(modelContainer: container)
        let fetched = try await reader.fetchVocabulary()
        XCTAssertEqual(fetched, [saved])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Book>()).isEmpty)
    }

    func testRenameConflictLeavesBothRecordsUnchanged() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let first = try await actor.saveVocabulary(term: "one", definition: "1")
        _ = try await actor.saveVocabulary(term: "two", definition: "2")
        let before = try await actor.fetchVocabulary()
        do {
            _ = try await actor.saveVocabulary(id: first.id, term: " TWO ", definition: "changed")
            XCTFail("A rename must not merge separate review histories")
        } catch {}
        let after = try await actor.fetchVocabulary()
        XCTAssertEqual(after, before)
    }

    func testBlankTermRejectedAndBlankDefinitionCannotBeReviewed() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        do {
            _ = try await actor.saveVocabulary(term: " \n\t ", definition: "meaning")
            XCTFail("Blank term accepted")
        } catch {}
        let card = try await actor.saveVocabulary(term: "word", definition: " \n ")
        do {
            _ = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                operationID: UUID(), rating: .good, now: Date())
            XCTFail("Undefined vocabulary entered review")
        } catch {}
        let fetched = try await actor.fetchVocabulary()
        XCTAssertEqual(fetched, [card])
    }

    func testEachGradeSchedulesAndDuplicateOperationIsIdempotent() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for rating in VocabularyRating.allCases {
            let actor = PersistenceActor(modelContainer: try makeContainer())
            let card = try await actor.saveVocabulary(term: "word", definition: "meaning")
            let operation = UUID()
            let reviewed = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                operationID: operation, rating: rating, now: now)
            XCTAssertFalse(reviewed.isNew)
            XCTAssertEqual(reviewed.revision, card.revision + 1)
            XCTAssertGreaterThan(reviewed.dueAt, now)
            let repeated = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                operationID: operation, rating: rating, now: now.addingTimeInterval(100))
            XCTAssertEqual(repeated, reviewed)
            do {
                _ = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                    operationID: UUID(), rating: .easy, now: now)
                XCTFail("Stale revision accepted")
            } catch {}
            let fetched = try await actor.fetchVocabulary()
            XCTAssertEqual(fetched, [reviewed])
        }
    }

    func testBackupRoundTripAndRepeatedImportPreserveLocalProgress() async throws {
        let source = PersistenceActor(modelContainer: try makeContainer())
        let saved = try await source.saveVocabulary(term: "word", definition: "meaning",
            source: VocabularySource(bookKey: "book", bookTitle: "Title", context: "word in context"))
        let reviewed = try await source.reviewVocabulary(id: saved.id, expectedRevision: saved.revision,
            operationID: UUID(), rating: .good, now: Date(timeIntervalSince1970: 1_800_000_000))
        let backup = try await source.exportVocabulary()
        let target = PersistenceActor(modelContainer: try makeContainer())
        let imported = try await target.importVocabulary(backup)
        XCTAssertEqual(imported.added, 1)
        let restored = try await target.fetchVocabulary()
        XCTAssertEqual(restored, [reviewed])
        let restoredBackup = try await target.exportVocabulary()
        XCTAssertEqual(restoredBackup, backup, "Restore must retain complete scheduling state and review history")
        let advanced = try await target.reviewVocabulary(id: reviewed.id, expectedRevision: reviewed.revision,
            operationID: UUID(), rating: .easy, now: reviewed.dueAt)
        let repeated = try await target.importVocabulary(backup)
        XCTAssertEqual(repeated.added, 0)
        XCTAssertEqual(repeated.skipped, 1)
        let after = try await target.fetchVocabulary()
        XCTAssertEqual(after, [advanced])
    }

    func testInvalidAndFutureBackupsLeaveExistingDataUntouched() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let saved = try await actor.saveVocabulary(term: "existing", definition: "keep")
        let valid = try await actor.exportVocabulary()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["version"] = 999
        for corrupt in [Data("bad json".utf8), try JSONSerialization.data(withJSONObject: object)] {
            do {
                _ = try await actor.importVocabulary(corrupt)
                XCTFail("Invalid backup accepted")
            } catch {}
            let after = try await actor.fetchVocabulary()
            XCTAssertEqual(after, [saved])
        }
    }

    func testRepeatedReaderCollectionDeduplicatesFreshSourceIDsByLocationOrContext() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let original = VocabularySource(bookKey: "book-a", bookTitle: "A", context: "The word is here.",
            locatorData: Data([10, 20]), createdAt: Date(timeIntervalSince1970: 100))
        let saved = try await actor.saveVocabulary(term: "word", definition: "词", source: original)
        let selectedAgain = VocabularySource(bookKey: "book-a", bookTitle: "A", context: "The word is here.",
            locatorData: Data([10, 20]), createdAt: Date(timeIntervalSince1970: 200))
        let duplicate = try await actor.saveVocabulary(term: "WORD", definition: "overwrite", source: selectedAgain)
        XCTAssertEqual(duplicate.sources, [original])
        XCTAssertEqual(duplicate.definition, saved.definition)
        XCTAssertEqual(duplicate.cardData, saved.cardData)

        let noLocator = VocabularySource(bookKey: "book-b", bookTitle: "B", context: "Another word appears.")
        _ = try await actor.saveVocabulary(term: "word", definition: "", source: noLocator)
        let noLocatorAgain = VocabularySource(bookKey: "book-b", bookTitle: "B", context: "Another word appears.")
        let repeated = try await actor.saveVocabulary(term: "word", definition: "", source: noLocatorAgain)
        XCTAssertEqual(repeated.sources.count, 2)
        XCTAssertTrue(repeated.sources.contains { $0.id == noLocator.id })
        XCTAssertFalse(repeated.sources.contains { $0.id == noLocatorAgain.id })

        let differentContext = VocabularySource(bookKey: "book-b", bookTitle: "B", context: "The word has another use.")
        let distinct = try await actor.saveVocabulary(term: "word", definition: "", source: differentContext)
        XCTAssertEqual(distinct.sources.count, 3)
    }


    func testEditingOriginalSentenceUpdatesSameSourceWithoutResettingSchedule() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let source = VocabularySource(bookKey: "book", bookTitle: "Source", context: "Original quote.")
        let saved = try await actor.saveVocabulary(term: "quote", definition: "引文", source: source)
        let replacement = VocabularySource(id: source.id, bookKey: source.bookKey, bookTitle: source.bookTitle,
            context: "Corrected original quote.", locatorData: source.locatorData, createdAt: source.createdAt)
        let edited = try await actor.saveVocabulary(id: saved.id, term: saved.term,
            definition: saved.definition, source: replacement)
        XCTAssertEqual(edited.sources, [replacement])
        XCTAssertEqual(edited.cardData, saved.cardData)
        XCTAssertEqual(edited.dueAt, saved.dueAt)
    }


    func testLocationJSONKeyOrderDoesNotDuplicateSourceOrResetReview() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let firstLocation = Data(#"{"page":3,"range":{"start":10,"end":14}}"#.utf8)
        let reorderedLocation = Data(#"{"range":{"end":14,"start":10},"page":3}"#.utf8)
        let original = VocabularySource(bookKey: "book", bookTitle: "Book", context: "A word.",
                                        locatorData: firstLocation)
        let saved = try await actor.saveVocabulary(term: "word", definition: "词", source: original)
        let reviewed = try await actor.reviewVocabulary(id: saved.id, expectedRevision: saved.revision,
            operationID: UUID(), rating: .good, now: saved.dueAt)
        let repeated = VocabularySource(bookKey: "book", bookTitle: "Book", context: "A word.",
                                        locatorData: reorderedLocation)
        let collected = try await actor.saveVocabulary(term: "WORD", definition: "overwrite", source: repeated)
        XCTAssertEqual(collected.id, reviewed.id)
        XCTAssertEqual(collected.definition, reviewed.definition)
        XCTAssertEqual(collected.cardData, reviewed.cardData)
        XCTAssertEqual(collected.dueAt, reviewed.dueAt)
        XCTAssertEqual(collected.sources, [original])
        XCTAssertEqual(collected.sources.first?.locatorData, firstLocation)
    }

}
