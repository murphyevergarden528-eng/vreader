import Foundation

/// Shared by the list's pending filter and the review session, with an explicit test clock.
enum VocabularyStudyQueue {
    static func entries(in records: [VocabularyRecord], now: Date) -> [VocabularyRecord] {
        records.filter {
            !$0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.dueAt <= now
        }.sorted {
            if $0.isNew != $1.isNew { return !$0.isNew }
            if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
