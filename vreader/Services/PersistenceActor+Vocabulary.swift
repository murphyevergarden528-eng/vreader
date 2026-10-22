// Vocabulary CRUD. Every mutation uses one actor-isolated, non-suspending save.
import Foundation
import SwiftData

extension PersistenceActor {
    func fetchVocabulary() throws -> [VocabularyRecord] {
        let context = vocabularyContext()
        return try context.fetch(FetchDescriptor<VocabularyEntry>())
            .map { try vocabularyRecord($0, in: context) }
            .sorted { $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
    }

    func saveVocabulary(id: UUID? = nil, term: String, definition: String,
                        source: VocabularySource? = nil) throws -> VocabularyRecord {
        let display = VocabularyNormalization.displayTerm(term)
        let key = VocabularyNormalization.key(term)
        guard !key.isEmpty else { throw VocabularyError.emptyTerm }
        if let source { try validateVocabularySource(source) }
        let context = vocabularyContext()
        do {
            let match = try vocabularyEntry(key: key, in: context)
            let entry: VocabularyEntry
            let created: Bool
            if let id {
                guard let found = try vocabularyEntry(id: id, in: context) else { throw VocabularyError.notFound }
                if let match, match.id != id {
                    throw VocabularyError.termConflict(existing: try vocabularyRecord(match, in: context))
                }
                entry = found
                created = false
            } else if let match {
                entry = match
                created = false
            } else {
                let now = Date()
                entry = VocabularyEntry(term: display, normalizedTerm: key,
                    definition: definition.trimmingCharacters(in: .whitespacesAndNewlines),
                    cardData: try VocabularyScheduler.initialCard(at: now), dueAt: now,
                    createdAt: now, updatedAt: now)
                context.insert(entry)
                created = true
            }
            var changed = false
            // A repeated collection never replaces existing definitions or scheduling state.
            if id != nil {
                let meaning = definition.trimmingCharacters(in: .whitespacesAndNewlines)
                changed = entry.term != display || entry.definition != meaning
                entry.term = display
                entry.normalizedTerm = key
                entry.definition = meaning
            }
            if let source {
                let sourceChanged = try upsertVocabularySource(source, for: entry.id,
                    allowEdit: id != nil, in: context)
                changed = changed || sourceChanged
            }
            if !created && changed {
                guard entry.revision < Int.max else { throw VocabularyError.invalidState }
                entry.revision += 1
                entry.updatedAt = Date()
            }
            try context.save()
            return try vocabularyRecord(entry, in: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteVocabulary(id: UUID) throws {
        let context = vocabularyContext()
        do {
            guard let entry = try vocabularyEntry(id: id, in: context) else { return }
            for source in try vocabularyOccurrences(for: id, in: context) { context.delete(source) }
            let events = try context.fetch(FetchDescriptor<VocabularyReviewEvent>(
                predicate: #Predicate { $0.entryID == id }))
            for event in events { context.delete(event) }
            context.delete(entry)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func vocabularyContext() -> ModelContext {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        return context
    }

    func vocabularyEntry(id: UUID, in context: ModelContext) throws -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func vocabularyEntry(key: String, in context: ModelContext) throws -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(predicate: #Predicate { $0.normalizedTerm == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func vocabularyOccurrences(for id: UUID, in context: ModelContext) throws -> [VocabularyOccurrence] {
        try context.fetch(FetchDescriptor<VocabularyOccurrence>(predicate: #Predicate { $0.entryID == id }))
    }

    func vocabularyRecord(_ entry: VocabularyEntry, in context: ModelContext) throws -> VocabularyRecord {
        let card = try VocabularyScheduler.card(from: entry.cardData)
        guard card.due == entry.dueAt else { throw VocabularyError.invalidState }
        let sources = try vocabularyOccurrences(for: entry.id, in: context).map(\.snapshot)
            .sorted { $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        return VocabularyRecord(id: entry.id, term: entry.term, normalizedTerm: entry.normalizedTerm,
            definition: entry.definition, sources: sources, cardData: entry.cardData,
            dueAt: card.due, isNew: card.state == .new, revision: entry.revision,
            createdAt: entry.createdAt, updatedAt: entry.updatedAt)
    }

    func validateVocabularySource(_ source: VocabularySource) throws {
        guard !source.bookKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.createdAt.timeIntervalSinceReferenceDate.isFinite else { throw VocabularyError.invalidSource }
    }

    private func upsertVocabularySource(_ source: VocabularySource, for entryID: UUID,
                                       allowEdit: Bool, in context: ModelContext) throws -> Bool {
        let sources = try vocabularyOccurrences(for: entryID, in: context)
        if let existing = sources.first(where: { $0.id == source.id }) {
            guard allowEdit, existing.snapshot != source else { return false }
            guard !sources.contains(where: {
                $0.id != source.id && $0.snapshot.identifiesSameOccurrence(as: source)
            }) else { throw VocabularyError.invalidSource }
            existing.bookKey = source.bookKey
            existing.bookTitle = source.bookTitle
            existing.context = source.context
            existing.locatorData = source.locatorData
            existing.createdAt = source.createdAt
            return true
        }
        if sources.contains(where: { $0.snapshot.identifiesSameOccurrence(as: source) }) { return false }
        let sourceID = source.id
        let collisions = try context.fetch(FetchDescriptor<VocabularyOccurrence>(
            predicate: #Predicate { $0.id == sourceID }))
        guard collisions.isEmpty else { throw VocabularyError.invalidSource }
        context.insert(VocabularyOccurrence(entryID: entryID, source: source))
        return true
    }
}
