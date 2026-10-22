import SwiftData
import Testing
@testable import vreader

@Suite("Vocabulary migration registration")
struct VocabularyMigrationRegistrationTests {
    @Test func vocabularySchemaIsLatestRegisteredVersion() throws {
        let latest = try #require(VReaderMigrationPlan.schemas.last)
        #expect(latest.versionIdentifier == Schema.Version(11, 0, 0))
    }
}
