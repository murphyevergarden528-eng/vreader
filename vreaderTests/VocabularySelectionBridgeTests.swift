import Foundation
import Testing
@testable import vreader

@Suite("Vocabulary selection handoff")
@MainActor
struct VocabularySelectionBridgeTests {
    @Test func frozenSnapshotRetainsReaderAndExactContext() {
        let readerID = UUID()
        let context = VocabularyReaderContext(readerID: readerID, bookKey: "book-a", bookTitle: "Book A")
        let snapshot = context.snapshot(term: "echo", context: "The echo returned.", locatorData: Data([1, 2]))
        #expect(snapshot?.readerID == readerID)
        #expect(snapshot?.source.bookKey == "book-a")
        #expect(snapshot?.source.context == "The echo returned.")
        #expect(snapshot?.source.locatorData == Data([1, 2]))
    }

    @Test func missingBookOrEmptyTermCannotProduceCollectableSnapshot() {
        let context = VocabularyReaderContext(readerID: UUID(), bookKey: "", bookTitle: "")
        #expect(context.snapshot(term: "word", context: "", locatorData: nil) == nil)
        let valid = VocabularyReaderContext(readerID: UUID(), bookKey: "book-a", bookTitle: "")
        #expect(valid.snapshot(term: " \n", context: "", locatorData: nil) == nil)
        #expect(valid.snapshot(term: "word", context: "", locatorData: nil)?.source.context == "")
    }

    @Test func contextUsesExactSelectedOccurrenceRatherThanFirstTextMatch() {
        let text = "The echo fades. The echo returned."
        let selected = (text as NSString).range(of: "echo", options: .backwards)
        #expect(VocabularySelectionContext.sentence(in: text, range: selected) == "The echo returned.")
    }

    @Test func contextHandlesUTF16CJKAndInvalidRange() {
        let text = "前句。🙂目标在这里。后句。"
        let selected = (text as NSString).range(of: "目标")
        #expect(VocabularySelectionContext.sentence(in: text, range: selected) == "🙂目标在这里。")
        #expect(VocabularySelectionContext.sentence(in: text, range: NSRange(location: NSNotFound, length: 2)) == "")
        #expect(VocabularySelectionContext.sentence(in: text, range: NSRange(location: 999, length: 2)) == "")
    }

    @Test func selectionEndingAtSentenceBoundaryDoesNotIncludeNextSentence() {
        let text = "🙂echo fades.\nThe echo returned! 后句。"
        let nsText = text as NSString
        #expect(VocabularySelectionContext.sentence(in: text,
            range: nsText.range(of: "echo fades.")) == "🙂echo fades.")
        #expect(VocabularySelectionContext.sentence(in: text,
            range: nsText.range(of: "echo fades.\n")) == "🙂echo fades.")
        #expect(VocabularySelectionContext.sentence(in: text,
            range: nsText.range(of: "echo returned!")) == "The echo returned!")
    }

    @Test func vocabularyActionWithoutFrozenSnapshotIsDeferred() {
        let payload = SelectionPopoverRequestPayload(
            selection: TextSelectionInfo(selectedText: "word", startUTF16: 0, endUTF16: 4), requestToken: nil
        )
        #expect(SelectionPopoverActionRouter.route(action: .saveVocabulary, payload: payload, notificationCenter: NotificationCenter()) == .deferredNotYetWired(.saveVocabulary))
    }

    @Test func vocabularyRouteDispatchesFrozenObjectAndPreservesLegacyPayload() throws {
        let context = VocabularyReaderContext(readerID: UUID(), bookKey: "book-a", bookTitle: "A")
        let snapshot = try #require(context.snapshot(term: "word", context: "A word.", locatorData: nil))
        let info = TextSelectionInfo(selectedText: "word", startUTF16: 2, endUTF16: 6)
        let payload = SelectionPopoverRequestPayload(selection: info, requestToken: nil, vocabularySnapshot: snapshot)
        let center = NotificationCenter()
        let received = VocabularyNotificationBox()
        let observer = center.addObserver(forName: Notification.Name("vreader.vocabulary.collect"), object: nil, queue: nil) { note in
            received.value = note.object as? VocabularySelectionSnapshot
        }
        defer { center.removeObserver(observer) }
        #expect(SelectionPopoverActionRouter.route(action: .saveVocabulary, payload: payload, notificationCenter: center) == .dispatched(Notification.Name("vreader.vocabulary.collect")))
        #expect(received.value == snapshot)
        #expect(SelectionPopoverRequest.payload(from: Notification(name: .readerSelectionPopoverRequested, object: info))?.vocabularySnapshot == nil)
    }
}

private final class VocabularyNotificationBox: @unchecked Sendable {
    var value: VocabularySelectionSnapshot?
}
