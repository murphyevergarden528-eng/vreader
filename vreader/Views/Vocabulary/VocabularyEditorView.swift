import SwiftUI

@MainActor
struct VocabularyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceActor) private var persistence
    @State private var draft: VocabularyEditorViewModel
    @State private var record: VocabularyRecord?
    @State private var source: VocabularySource?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var conflict: VocabularyRecord?
    @State private var showsReadiness = false
    private let selection: VocabularySelectionSnapshot?

    init(record: VocabularyRecord? = nil, selection: VocabularySelectionSnapshot? = nil) {
        self.selection = selection
        let source = selection?.source ?? record?.sources.first
        _record = State(initialValue: record)
        _source = State(initialValue: source)
        _draft = State(initialValue: VocabularyEditorViewModel(
            term: record?.term ?? selection?.term ?? "", definition: record?.definition ?? "",
            context: source?.context ?? ""))
    }

    private var sources: [VocabularySource] {
        var result = record?.sources ?? []
        if let source, !result.contains(where: { $0.id == source.id }) { result.append(source) }
        return result
    }

    private var sourceIsUnsaved: Bool {
        guard let source else { return false }
        return !(record?.sources.contains { $0.id == source.id } ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("单词或短语") {
                    TextField("词条", text: $draft.term, axis: .vertical)
                        .font(.title2).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("vocabularyTermField")
                }
                Section("中文释义") {
                    TextEditor(text: $draft.definition).frame(minHeight: 120)
                        .accessibilityIdentifier("vocabularyDefinitionField")
                    if draft.isGenerating {
                        HStack {
                            ProgressView("正在生成释义…")
                            Spacer()
                            Button("取消生成") { draft.cancelDefinition() }
                        }
                    } else {
                        Button("AI 解释", systemImage: "sparkles", action: explain)
                            .disabled(draft.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let message = draft.errorMessage { Text(message).foregroundStyle(.red) }
                }
                sourceSection
                if isLoading { ProgressView("正在检查已有词条…") }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                        if loadFailed { Button("重新读取") { Task { await initialize() } } }
                    }
                }
            }
            .disabled(isLoading || isSaving)
            .scrollContentBackground(.hidden)
            .background(LibraryCardTokens.shellBackground)
            .tint(LibraryCardTokens.accent)
            .navigationTitle(record == nil ? "加入生词本" : "编辑生词")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .accessibilityIdentifier("vocabularySaveButton")
                        .disabled(isLoading || loadFailed || isSaving || VocabularyNormalization.key(draft.term).isEmpty)
                }
            }
            .task { await initialize() }
            .onDisappear { draft.cancelDefinition() }
            .sheet(isPresented: $showsReadiness) {
                ReaderAIReadinessSheet(theme: .paper) { showsReadiness = false }
            }
            .alert("已有同名词条", isPresented: Binding(
                get: { conflict != nil }, set: { if !$0 { conflict = nil } }
            )) {
                Button("打开已有词条") { openConflict() }
                Button("取消", role: .cancel) { conflict = nil }
            } message: { Text("该词条已有独立的复习记录。可打开查看，本次修改不会自动合并。") }
        }
    }

    private var sourceSection: some View {
        Section("阅读原句与来源") {
            if sources.count > 1 {
                Picker("阅读来源", selection: Binding(
                    get: { source?.id }, set: { id in
                        guard let chosen = sources.first(where: { $0.id == id }) else { return }
                        source = chosen
                        draft.context = chosen.context
                    }
                )) {
                    ForEach(sources) { item in
                        Text("\(item.bookTitle) · \(item.context.prefix(28))").tag(Optional(item.id))
                    }
                }
                .disabled(draft.context != (source?.context ?? "") || sourceIsUnsaved)
                if draft.context != (source?.context ?? "") || sourceIsUnsaved {
                    Text("先保存当前原句后，再切换来源。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let source { Text(source.bookTitle).foregroundStyle(.secondary) }
            TextEditor(text: $draft.context).frame(minHeight: 100)
                .accessibilityIdentifier("vocabularyContextField")
            if draft.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("未取得完整原句，可在这里补充。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func initialize() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        guard record == nil, selection != nil else { return }
        guard let persistence else { loadFailed = true; errorMessage = "生词数据库暂不可用，请重新打开应用。"; return }
        do {
            let entries = try await persistence.fetchVocabulary()
            if let existing = entries.first(where: { $0.normalizedTerm == VocabularyNormalization.key(draft.term) }) {
                record = existing
                if let source, let saved = existing.sources.first(where: { $0.identifiesSameOccurrence(as: source) }) {
                    self.source = VocabularySource(id: saved.id, bookKey: source.bookKey,
                        bookTitle: source.bookTitle, context: source.context,
                        locatorData: source.locatorData, createdAt: saved.createdAt)
                }
                draft.term = existing.term
                draft.definition = existing.definition
            }
            errorMessage = nil
        } catch {
            loadFailed = true
            errorMessage = ErrorMessageAuditor.sanitize(error)
        }
    }

    private func explain() {
        guard AIReaderAvailability.isAvailable(featureFlags: .shared,
            keychainService: KeychainService(), consentManager: AIConsentManager()) else {
            showsReadiness = true
            return
        }
        Task { await draft.generateDefinition() }
    }

    private func save() async {
        guard let persistence, !isSaving, !isLoading, !loadFailed else { return }
        draft.cancelDefinition()
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let updatedSource = source.map {
            VocabularySource(id: $0.id, bookKey: $0.bookKey, bookTitle: $0.bookTitle,
                context: draft.context, locatorData: $0.locatorData, createdAt: $0.createdAt)
        }
        do {
            _ = try await persistence.saveVocabulary(id: record?.id, term: draft.term,
                definition: draft.definition, source: updatedSource)
            dismiss()
        } catch VocabularyError.termConflict(let existing) {
            conflict = existing
        } catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }

    private func openConflict() {
        guard let existing = conflict else { return }
        draft.cancelDefinition()
        record = existing
        source = existing.sources.first
        draft.term = existing.term
        draft.definition = existing.definition
        draft.context = source?.context ?? ""
        conflict = nil
        errorMessage = nil
    }
}
