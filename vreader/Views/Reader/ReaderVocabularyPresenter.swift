import SwiftUI

/// Presents only the immutable selection belonging to this reader window.
struct ReaderVocabularyPresenter: ViewModifier {
    let readerID: UUID
    let bookKey: String
    @State private var selection: VocabularySelectionSnapshot?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("vreader.vocabulary.collect"))) { event in
                guard let snapshot = event.object as? VocabularySelectionSnapshot,
                      snapshot.readerID == readerID,
                      snapshot.source.bookKey == bookKey else { return }
                selection = snapshot
            }
            .sheet(item: $selection) { snapshot in
                VocabularyEditorView(selection: snapshot)
            }
    }
}
