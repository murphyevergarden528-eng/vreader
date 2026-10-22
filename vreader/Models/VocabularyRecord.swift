// Value snapshots for vocabulary. No context-bound models cross actor boundaries.
import Foundation

struct VocabularySource: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let bookKey: String
    let bookTitle: String
    let context: String
    let locatorData: Data?
    let createdAt: Date

    init(id: UUID = UUID(), bookKey: String, bookTitle: String, context: String,
         locatorData: Data? = nil, createdAt: Date = Date()) {
        self.id = id
        self.bookKey = bookKey
        self.bookTitle = bookTitle
        self.context = context
        self.locatorData = locatorData
        self.createdAt = createdAt
    }

    func identifiesSameOccurrence(as other: VocabularySource) -> Bool {
        guard bookKey == other.bookKey else { return false }
        let location = Self.canonicalLocation(locatorData)
        let otherLocation = Self.canonicalLocation(other.locatorData)
        if let location { return location == otherLocation }
        return otherLocation == nil && context == other.context
    }

    private static func canonicalLocation(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        // Readers serialize location JSON independently; key order is not identity.
        // Keep the original bytes in the source snapshot and exported backup.
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return data }
        return canonical
    }
}

struct VocabularyRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let term: String
    let normalizedTerm: String
    let definition: String
    let sources: [VocabularySource]
    let cardData: Data
    let dueAt: Date
    let isNew: Bool
    let revision: Int
    let createdAt: Date
    let updatedAt: Date
}

enum VocabularyRating: Int, Codable, Sendable, CaseIterable {
    case again = 1, hard = 2, good = 3, easy = 4
}

struct VocabularyImportResult: Equatable, Sendable {
    let added: Int
    let skipped: Int
}

enum VocabularyNormalization {
    static func displayTerm(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func key(_ text: String) -> String {
        displayTerm(text).lowercased(with: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }
}

enum VocabularyError: Error, LocalizedError, Sendable {
    case emptyTerm
    case missingDefinition
    case notFound
    case termConflict(existing: VocabularyRecord)
    case staleRevision
    case notDue
    case operationConflict
    case invalidSource
    case invalidState
    case invalidBackup(String)

    var errorDescription: String? {
        switch self {
        case .emptyTerm: return "请输入单词或短语。"
        case .missingDefinition: return "请先补充释义，再开始复习。"
        case .notFound: return "这个词条已不存在，请刷新生词本。"
        case .termConflict: return "这个单词或短语已经存在，请打开已有词条。"
        case .staleRevision: return "词条已经更新，请刷新后再评分。"
        case .notDue: return "这个词条尚未到复习时间。"
        case .operationConflict: return "这次复习操作已用于其他词条。"
        case .invalidSource: return "阅读来源无效或与已有来源冲突。"
        case .invalidState: return "词条的复习状态无效，请从备份恢复。"
        case .invalidBackup(let reason): return "无法导入生词备份：\(reason)"
        }
    }
}
