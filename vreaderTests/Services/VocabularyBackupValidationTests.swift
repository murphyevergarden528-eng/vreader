// Exercise import through the persistence API, including duplicate-card validation order.
import Foundation
import SwiftData
import XCTest
@testable import vreader

final class VocabularyBackupValidationTests: XCTestCase {
    private func makeActor() throws -> PersistenceActor {
        let container = try ModelContainer(for: Schema(SchemaV11.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return PersistenceActor(modelContainer: container)
    }

    private func populatedTarget() async throws -> (Data, PersistenceActor, Data) {
        let source = try makeActor()
        let saved = try await source.saveVocabulary(term: "source", definition: "来源")
        _ = try await source.reviewVocabulary(id: saved.id, expectedRevision: saved.revision,
            operationID: UUID(), rating: .good, now: saved.dueAt)
        let valid = try await source.exportVocabulary()
        let target = try makeActor()
        _ = try await target.saveVocabulary(term: "sentinel", definition: "必须保留")
        _ = try await target.importVocabulary(valid)
        let before = try await target.exportVocabulary()
        return (valid, target, before)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assertRejected(_ data: Data, by target: PersistenceActor,
                                preserving before: Data, file: StaticString = #filePath,
                                line: UInt = #line) async throws {
        do {
            _ = try await target.importVocabulary(data)
            XCTFail("Malformed backup was accepted even though its card already exists", file: file, line: line)
        } catch let error as VocabularyError {
            guard case .invalidBackup = error else {
                XCTFail("Unexpected import error: \(error)", file: file, line: line)
                return
            }
        }
        let after = try await target.exportVocabulary()
        XCTAssertEqual(after, before, "Rejected import changed local card or history", file: file, line: line)
    }

    func testOrphanReviewReferenceRejectedBeforeDuplicateCardSkip() async throws {
        let (valid, target, before) = try await populatedTarget()
        var backup = try object(valid)
        var cards = try XCTUnwrap(backup["cards"] as? [[String: Any]])
        var reviews = try XCTUnwrap(cards[0]["reviews"] as? [[String: Any]])
        XCTAssertEqual(reviews.count, 1)
        reviews[0]["entryID"] = UUID().uuidString
        cards[0]["reviews"] = reviews
        backup["cards"] = cards
        let corrupt = try JSONSerialization.data(withJSONObject: backup, options: [.sortedKeys])
        try await assertRejected(corrupt, by: target, preserving: before)
    }

    func testNegativeFSRSStabilityRejectedBeforeDuplicateCardSkip() async throws {
        let (valid, target, before) = try await populatedTarget()
        var backup = try object(valid)
        var cards = try XCTUnwrap(backup["cards"] as? [[String: Any]])
        var record = try XCTUnwrap(cards[0]["record"] as? [String: Any])
        let encoded = try XCTUnwrap(record["cardData"] as? String)
        var card = try object(XCTUnwrap(Data(base64Encoded: encoded)))
        card["stability"] = -1.0
        record["cardData"] = try JSONSerialization.data(withJSONObject: card, options: [.sortedKeys])
            .base64EncodedString()
        cards[0]["record"] = record
        backup["cards"] = cards
        let corrupt = try JSONSerialization.data(withJSONObject: backup, options: [.sortedKeys])
        try await assertRejected(corrupt, by: target, preserving: before)
    }

    func testUnsupportedAlgorithmParametersPreserveExistingCardsAndHistory() async throws {
        let (valid, target, before) = try await populatedTarget()
        var backup = try object(valid)
        var algorithm = try XCTUnwrap(backup["algorithm"] as? [String: Any])
        var parameters = try XCTUnwrap(algorithm["parameters"] as? [String: Any])
        parameters["requestRetention"] = 0.5
        algorithm["parameters"] = parameters
        backup["algorithm"] = algorithm
        let unsupported = try JSONSerialization.data(withJSONObject: backup, options: [.sortedKeys])
        try await assertRejected(unsupported, by: target, preserving: before)
    }
}
