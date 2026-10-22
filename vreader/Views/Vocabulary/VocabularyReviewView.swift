import SwiftUI

@MainActor
struct VocabularyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceActor) private var persistence
    @State private var records: [VocabularyRecord] = []
    @State private var current: VocabularyRecord?
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var showsAnswer = false
    @State private var isSubmitting = false
    @State private var operationID = UUID()
    @State private var errorMessage: String?

    private var nextDue: Date? {
        guard current == nil else { return nil }
        return records.filter {
            !$0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.dueAt > Date()
        }.map(\.dueAt).min()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        ProgressView("正在读取复习卡…")
                    } else if let current {
                        Text(current.term).font(.system(.largeTitle, design: .serif)).textSelection(.enabled)
                        if let source = current.sources.first, !source.context.isEmpty {
                            Text(source.context).font(.title3).textSelection(.enabled)
                            Text(source.bookTitle).font(.caption).foregroundStyle(.secondary)
                        }
                        if showsAnswer {
                            Divider()
                            Text(current.definition).textSelection(.enabled)
                            ratings
                        } else {
                            Button("显示答案") { showsAnswer = true }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("vocabularyShowAnswerButton")
                        }
                    } else if hasLoaded {
                        Text("本轮复习完成")
                            .font(.title2).accessibilityIdentifier("vocabularyReviewComplete")
                        if let nextDue {
                            Text("下次复习：\(nextDue.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("阅读时继续收集生词；没有释义的词条需先补充释义。")
                                .foregroundStyle(.secondary)
                        }
                        Button("刷新") { Task { await loadNext() } }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("vocabularyReviewError")
                        if current == nil { Button("重试") { Task { await loadNext() } } }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(LibraryCardTokens.shellBackground)
            .tint(LibraryCardTokens.accent)
            .navigationTitle("每日复习")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .task { await loadNext() }
            .task(id: nextDue) {
                guard let date = nextDue else { return }
                do {
                    try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                    guard !Task.isCancelled, current == nil else { return }
                    await loadNext()
                } catch { /* Closing the sheet cancels its local due timer. */ }
            }
        }
    }

    private var ratings: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ratingButtons }
            VStack(alignment: .leading, spacing: 12) { ratingButtons }
        }
        .disabled(isSubmitting)
    }

    private var ratingButtons: some View {
        Group {
            ratingButton("忘记", rating: .again, identifier: "vocabularyRatingAgain")
            ratingButton("困难", rating: .hard, identifier: "vocabularyRatingHard")
            ratingButton("记得", rating: .good, identifier: "vocabularyRatingGood")
            ratingButton("简单", rating: .easy, identifier: "vocabularyRatingEasy")
        }
    }

    private func ratingButton(_ title: String, rating: VocabularyRating, identifier: String) -> some View {
        Button(title) { Task { await submit(rating) } }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(identifier)
    }

    private func loadNext() async {
        defer { isLoading = false }
        guard let persistence else { errorMessage = "生词数据库暂不可用，请重新打开应用。"; return }
        do {
            records = try await persistence.fetchVocabulary()
            hasLoaded = true
            errorMessage = nil
            current = VocabularyStudyQueue.entries(in: records, now: Date()).first
            showsAnswer = false
            operationID = UUID()
        } catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }

    private func submit(_ rating: VocabularyRating) async {
        guard let persistence, let card = current, showsAnswer, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            _ = try await persistence.reviewVocabulary(id: card.id, expectedRevision: card.revision,
                operationID: operationID, rating: rating, now: Date())
            await loadNext()
        } catch {
            errorMessage = "复习记录未更新：\(ErrorMessageAuditor.sanitize(error))"
            // Preserve a failed card only while it remains eligible after another window updates it.
            if let refreshed = try? await persistence.fetchVocabulary() {
                records = refreshed
                hasLoaded = true
                let eligible = VocabularyStudyQueue.entries(in: refreshed, now: Date())
                current = eligible.first { $0.id == card.id } ?? eligible.first
                showsAnswer = false
                operationID = UUID()
            }
        }
    }
}
