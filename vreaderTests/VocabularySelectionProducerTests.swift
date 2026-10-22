import Foundation
import Testing
import UIKit
@testable import vreader

@Suite("Vocabulary selection producers")
@MainActor
struct VocabularySelectionProducerTests {
    @Test func bilingualSelectionFreezesOriginalTermAndSourceOffsets() throws {
        let context = VocabularyReaderContext(readerID: UUID(), bookKey: "book", bookTitle: "Book")
        let view = UITextView()
        view.text = "First.译文 Second."
        let map = BilingualDisplaySegmentMap(sourceLength: 14, segments: [
            .source(sourceRange: 0..<6, displayRange: 0..<6),
            .synthetic(displayRange: 6..<8),
            .source(sourceRange: 6..<14, displayRange: 8..<16)
        ])
        let box = VocabularyPayloadBox()
        let observer = NotificationCenter.default.addObserver(forName: .readerSelectionPopoverRequested,
            object: nil, queue: nil) { note in
                let payload = note.object as? SelectionPopoverRequestPayload
                if payload?.vocabularySnapshot?.readerID == context.readerID { box.value = payload }
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        TXTBridgeShared.postSelectionNotification(.readerSelectionPopoverRequested, from: view,
            range: NSRange(location: 9, length: 6), chunkOffset: 100,
            vocabularyReaderContext: context, vocabularySourceText: "First. Second.",
            bilingualSegmentMap: map)
        let payload = try #require(box.value)
        #expect(payload.selection.startUTF16 == 107)
        #expect(payload.vocabularySnapshot?.term == "Second")
        #expect(payload.vocabularySnapshot?.source.context == "Second.")
        let locator = try JSONSerialization.jsonObject(with: #require(payload.vocabularySnapshot?.source.locatorData)) as? [String: Int]
        #expect(locator?["startUTF16"] == 107)
        // Replacing the UIKit selection after menu presentation cannot change the frozen payload.
        view.text = "Replaced"
        #expect(payload.vocabularySnapshot?.term == "Second")
    }

    @Test func chunkedSourceContextHandlesEmojiAndRepeatedWord() throws {
        let source = "🙂echo fades. The echo returned."
        let range = (source as NSString).range(of: "echo", options: .backwards)
        let context = VocabularyReaderContext(readerID: UUID(), bookKey: "book", bookTitle: "Book")
        let snapshot = try #require(TXTBridgeShared.vocabularySnapshot(context: context,
            sourceText: source, range: range, chunkOffset: 500))
        #expect(snapshot.source.context == "The echo returned.")
        let locator = try JSONSerialization.jsonObject(with: #require(snapshot.source.locatorData)) as? [String: Int]
        #expect(locator?["startUTF16"] == 500 + range.location)
        #expect(VocabularySelectionContext.sentence(in: source,
            range: (source as NSString).range(of: "echo fades.")) == "🙂echo fades.")
    }

    @Test func incompleteContextPreservesTermAndLocationButRequestsManualSentence() throws {
        #expect(VocabularySelectionContext.readiumContext(before: nil, highlight: "echo", after: nil) == "")
        #expect(VocabularySelectionContext.readiumContext(before: "", highlight: "echo", after: "") == "")
        #expect(VocabularySelectionContext.readiumContext(before: "ith an ", highlight: "echo", after: " ret") == "")
        #expect(VocabularySelectionContext.readiumContext(before: ". Before ", highlight: "echo", after: " ended.") == "Before echo ended.")
        #expect(VocabularySelectionContext.readiumContext(before: ". 🙂Before ", highlight: "echo", after: " ended.") == "🙂Before echo ended.")
        let context = VocabularyReaderContext(readerID: UUID(), bookKey: "book", bookTitle: "Book")
        for text in ["An echo crosses", "echo crosses. Next.", "Previous. An echo crosses"] {
            let range = (text as NSString).range(of: "echo")
            let snapshot = try #require(TXTBridgeShared.vocabularySnapshot(context: context,
                sourceText: text, range: range, chunkOffset: 500, sourceIsPartial: true))
            #expect(snapshot.term == "echo")
            #expect(snapshot.source.context == "")
            #expect(snapshot.source.locatorData != nil)
        }
        let text = "Previous. An echo returns. Next."
        #expect(VocabularySelectionContext.sentence(in: text,
            range: (text as NSString).range(of: "echo"), requireBoundaries: true) == "An echo returns.")
    }

    @Test func epubAndFoliateParsersRetainContextFromSelectedRange() throws {
        let epub = try #require(EPUBHighlightBridge.parseSelectionMessage([
            "selectedText": "echo", "startPath": "/p[2]/text()[1]", "endPath": "/p[2]/text()[1]",
            "startOffset": 4, "endOffset": 8, "context": "The echo returned.", "sectionHref": "two.xhtml"
        ]))
        #expect(epub.context == "The echo returned.")
        #expect(epub.sectionHref == "two.xhtml")
        let foliate = try #require(FoliateMessageParser.parseSelection([
            "text": "echo", "cfi": "epubcfi(/6/4!/4/2:4)", "index": 1,
            "context": "The echo returned."
        ]))
        #expect(foliate.context == "The echo returned.")
        #expect(foliate.sectionIndex == 1)
    }
}

private final class VocabularyPayloadBox: @unchecked Sendable {
    var value: SelectionPopoverRequestPayload?
}
