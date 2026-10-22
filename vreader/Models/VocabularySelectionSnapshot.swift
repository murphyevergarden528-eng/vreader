import Foundation
import SwiftUI

struct VocabularySelectionSnapshot: Equatable, Sendable, Identifiable {
    let id: UUID
    let readerID: UUID
    let term: String
    let source: VocabularySource

    init(id: UUID = UUID(), readerID: UUID, term: String, source: VocabularySource) {
        self.id = id
        self.readerID = readerID
        self.term = term
        self.source = source
    }
}

struct VocabularyReaderContext: Equatable, Sendable {
    let readerID: UUID
    let bookKey: String
    let bookTitle: String

    func snapshot(term: String, context: String, locatorData: Data? = nil) -> VocabularySelectionSnapshot? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !bookKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return VocabularySelectionSnapshot(readerID: readerID, term: term,
            source: VocabularySource(bookKey: bookKey, bookTitle: bookTitle,
                                     context: context, locatorData: locatorData))
    }
}

private struct VocabularyReaderContextKey: EnvironmentKey {
    static let defaultValue: VocabularyReaderContext? = nil
}

extension EnvironmentValues {
    var vocabularyReaderContext: VocabularyReaderContext? {
        get { self[VocabularyReaderContextKey.self] }
        set { self[VocabularyReaderContextKey.self] = newValue }
    }
}

enum VocabularySelectionContext {
    static func readiumContext(before: String?, highlight: String, after: String?) -> String {
        let before = before ?? ""
        let after = after ?? ""
        let range = NSRange(location: before.utf16.count, length: highlight.utf16.count)
        return sentence(in: before + highlight + after, range: range, requireBoundaries: true)
    }

    static func sentence(in text: String, range: NSRange, requireBoundaries: Bool = false) -> String {
        let text = text as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= text.length, range.length <= text.length - range.location else { return "" }
        let boundaries = CharacterSet(charactersIn: ".!?。！？\n\r")
        let before = text.rangeOfCharacter(from: boundaries, options: .backwards,
            range: NSRange(location: 0, length: range.location))
        let start = before.location == NSNotFound ? 0 : NSMaxRange(before)
        let endOfSelection = NSMaxRange(range)
        let after = text.rangeOfCharacter(from: boundaries, options: [],
            range: NSRange(location: endOfSelection, length: text.length - endOfSelection))
        let selectedEndIsBoundary = text.substring(with: NSRange(location: endOfSelection - 1, length: 1))
            .rangeOfCharacter(from: boundaries) != nil
        if requireBoundaries && (before.location == NSNotFound ||
            (!selectedEndIsBoundary && after.location == NSNotFound)) { return "" }
        let end = selectedEndIsBoundary ? endOfSelection
            : (after.location == NSNotFound ? text.length : NSMaxRange(after))
        return text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
