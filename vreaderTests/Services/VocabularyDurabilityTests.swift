import Foundation
import SwiftData
import XCTest
@testable import vreader

final class VocabularyDurabilityTests: XCTestCase {
    private func temporaryStore() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.sqlite")
    }

    func testVocabularySurvivesDiskContainerRecreation() async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original: VocabularyRecord
        do {
            let container = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(url: url)])
            let actor = PersistenceActor(modelContainer: container)
            original = try await actor.saveVocabulary(term: "durable", definition: "持久的")
        }
        let reopened = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(url: url)])
        let records = try await PersistenceActor(modelContainer: reopened).fetchVocabulary()
        XCTAssertEqual(records, [original])
    }

    func testV10DiskMigrationPreservesBookBookmarkAndPosition() async throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fingerprint = DocumentFingerprint(contentSHA256: String(repeating: "a", count: 64), fileByteCount: 100, format: .txt)
        let locator = Locator(bookFingerprint: fingerprint, charOffsetUTF16: 12, textQuote: "original")
        do {
            let old = try ModelContainer(for: Schema(SchemaV10.models), configurations: [ModelConfiguration(url: url)])
            let context = ModelContext(old)
            let book = Book(fingerprint: fingerprint, title: "Original book", provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil))
            let bookmark = Bookmark(locator: locator, title: "Keep bookmark")
            bookmark.book = book
            let position = ReadingPosition(locator: locator)
            position.book = book
            book.bookmarks.append(bookmark)
            book.readingPosition = position
            context.insert(book)
            try context.save()
        }
        let migrated = try ModelContainer(for: Schema(SchemaV11.models), migrationPlan: VReaderMigrationPlan.self,
                                         configurations: [ModelConfiguration(url: url)])
        let context = ModelContext(migrated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Book>()).first?.title, "Original book")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Bookmark>()).first?.title, "Keep bookmark")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReadingPosition>()).first?.locator, locator)
        let actor = PersistenceActor(modelContainer: migrated)
        _ = try await actor.saveVocabulary(term: "new", definition: "新的")
        let newVocabulary = try await actor.fetchVocabulary()
        XCTAssertEqual(newVocabulary.count, 1)
    }

    func testDeletingSourceBookDoesNotDeleteVocabulary() async throws {
        let container = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let fingerprint = DocumentFingerprint(contentSHA256: String(repeating: "b", count: 64), fileByteCount: 30, format: .txt)
        let context = ModelContext(container)
        context.insert(Book(fingerprint: fingerprint, title: "Source", provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil)))
        try context.save()
        let actor = PersistenceActor(modelContainer: container)
        let vocabulary = try await actor.saveVocabulary(term: "keep", definition: "保留",
            source: VocabularySource(bookKey: fingerprint.canonicalKey, bookTitle: "Source", context: "Keep the word."))
        try await actor.deleteBook(fingerprintKey: fingerprint.canonicalKey)
        let remaining = try await actor.fetchVocabulary()
        XCTAssertEqual(remaining, [vocabulary])
    }

    func testDeletingVocabularyRemovesItsSourcesAndReviewEvents() async throws {
        let container = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let actor = PersistenceActor(modelContainer: container)
        let word = try await actor.saveVocabulary(term: "gone", definition: "消失",
            source: VocabularySource(bookKey: "book", bookTitle: "Source", context: "It is gone."))
        _ = try await actor.reviewVocabulary(id: word.id, expectedRevision: word.revision, operationID: UUID(), rating: .good, now: Date())
        try await actor.deleteVocabulary(id: word.id)
        let records = try await actor.fetchVocabulary()
        XCTAssertTrue(records.isEmpty)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VocabularyOccurrence>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<VocabularyReviewEvent>()).isEmpty)
    }
}

