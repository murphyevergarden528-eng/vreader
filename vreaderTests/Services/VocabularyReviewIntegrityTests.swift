import Foundation
import SwiftData
import XCTest
@testable import vreader

final class VocabularyReviewIntegrityTests: XCTestCase {
    private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    func testTwoConcurrentSubmissionsAdvanceOnlyOnce() async throws {
        let actor = PersistenceActor(modelContainer: try memoryContainer())
        let card = try await actor.saveVocabulary(term: "concurrent", definition: "并发的")
        let now = Date()
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                            operationID: UUID(), rating: .good, now: now)
                        return true
                    } catch { return false }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        XCTAssertEqual(successes, 1)
        let records = try await actor.fetchVocabulary()
        XCTAssertEqual(records.first?.revision, card.revision + 1)
    }

    func testReviewCannotAdvanceBeforeDueTime() async throws {
        let actor = PersistenceActor(modelContainer: try memoryContainer())
        let card = try await actor.saveVocabulary(term: "due", definition: "到期的")
        let now = card.dueAt
        let reviewed = try await actor.reviewVocabulary(id: card.id, expectedRevision: card.revision,
            operationID: UUID(), rating: .good, now: now)
        do {
            _ = try await actor.reviewVocabulary(id: card.id, expectedRevision: reviewed.revision,
                operationID: UUID(), rating: .good, now: reviewed.dueAt.addingTimeInterval(-1))
            XCTFail("Future review was scheduled early")
        } catch {}
        let records = try await actor.fetchVocabulary()
        XCTAssertEqual(records, [reviewed])
        _ = try await actor.reviewVocabulary(id: card.id, expectedRevision: reviewed.revision,
            operationID: UUID(), rating: .good, now: reviewed.dueAt)
    }

    func testReadOnlyStoreSaveFailureKeepsCardAndHistoryUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-readonly-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let saved: VocabularyRecord
        let before: Data
        do {
            let writable = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(url: url)])
            let writer = PersistenceActor(modelContainer: writable)
            saved = try await writer.saveVocabulary(term: "atomic", definition: "原子的")
            before = try await writer.exportVocabulary()
        }
        let readonly = try ModelContainer(for: Schema(SchemaV11.models), configurations: [ModelConfiguration(url: url, allowsSave: false)])
        let actor = PersistenceActor(modelContainer: readonly)
        do {
            _ = try await actor.reviewVocabulary(id: saved.id, expectedRevision: saved.revision,
                operationID: UUID(), rating: .good, now: Date())
            XCTFail("Read-only persistence accepted review")
        } catch {}
        let records = try await actor.fetchVocabulary()
        XCTAssertEqual(records, [saved])
        let after = try await actor.exportVocabulary()
        XCTAssertEqual(after, before)
    }
}
