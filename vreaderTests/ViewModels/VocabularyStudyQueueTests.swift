import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("Vocabulary due queue")
struct VocabularyStudyQueueTests {
    private func persistence() throws -> PersistenceActor {
        let container = try ModelContainer(for: Schema(SchemaV11.models),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return PersistenceActor(modelContainer: container)
    }

    @Test func undefinedCardsStayInBookButNotInStudyQueue() async throws {
        let store = try persistence()
        let undefined = try await store.saveVocabulary(term: "undefined", definition: " \n ")
        let ready = try await store.saveVocabulary(term: "ready", definition: "准备好的")
        let queue = VocabularyStudyQueue.entries(in: [undefined, ready], now: Date())
        #expect(queue.map(\.id) == [ready.id])
    }

    @Test func dueReviewsPrecedeNewCardsAndFutureCardsWait() async throws {
        let store = try persistence()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let known = try await store.saveVocabulary(term: "known", definition: "已知的")
        let fresh = try await store.saveVocabulary(term: "fresh", definition: "新的")
        let reviewed = try await store.reviewVocabulary(id: known.id, expectedRevision: known.revision,
            operationID: UUID(), rating: .good, now: now)
        #expect(VocabularyStudyQueue.entries(in: [fresh, reviewed], now: reviewed.dueAt.addingTimeInterval(-0.1)).map(\.id) == [fresh.id])
        #expect(VocabularyStudyQueue.entries(in: [fresh, reviewed], now: reviewed.dueAt).map(\.id) == [reviewed.id, fresh.id])
    }

    @Test func anotherWindowRatingRemovesFutureCardFromRefreshedQueue() async throws {
        let store = try persistence()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await store.saveVocabulary(term: "first", definition: "第一")
        let second = try await store.saveVocabulary(term: "second", definition: "第二")
        let windowA = first
        let windowB = first
        let reviewed = try await store.reviewVocabulary(id: windowA.id,
            expectedRevision: windowA.revision, operationID: UUID(), rating: .good, now: now)
        #expect(reviewed.dueAt > now)
        do {
            _ = try await store.reviewVocabulary(id: windowB.id,
                expectedRevision: windowB.revision, operationID: UUID(), rating: .good, now: now)
            Issue.record("The stale window must not rate the same revision again")
        } catch VocabularyError.staleRevision {
            let refreshed = try await store.fetchVocabulary()
            let eligible = VocabularyStudyQueue.entries(in: refreshed, now: now)
            #expect(!eligible.contains { $0.id == windowB.id })
            #expect(eligible.first?.id == second.id)
            #expect(refreshed.first { $0.id == first.id }?.revision == reviewed.revision)
        }
    }

}
