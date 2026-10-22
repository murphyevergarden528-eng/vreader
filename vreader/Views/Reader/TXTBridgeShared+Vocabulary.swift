import UIKit

extension TXTBridgeShared {
    @MainActor
    static func vocabularySnapshot(context: VocabularyReaderContext?, sourceText: String?,
                                   range: NSRange, chunkOffset: Int = 0, sourceIsPartial: Bool = false) -> VocabularySelectionSnapshot? {
        guard let context, let sourceText else { return nil }
        let text = sourceText as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= text.length, range.length <= text.length - range.location else { return nil }
        let locator = try? JSONSerialization.data(withJSONObject: [
            "startUTF16": chunkOffset + range.location,
            "endUTF16": chunkOffset + NSMaxRange(range)
        ], options: [.sortedKeys])
        return context.snapshot(term: text.substring(with: range),
            context: VocabularySelectionContext.sentence(in: sourceText, range: range, requireBoundaries: sourceIsPartial), locatorData: locator)
    }
}
