// Additive vocabulary entities. Historical schema model lists stay unchanged.
import SwiftData

enum SchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        SchemaV10.models + [VocabularyEntry.self, VocabularyOccurrence.self, VocabularyReviewEvent.self]
    }
}
