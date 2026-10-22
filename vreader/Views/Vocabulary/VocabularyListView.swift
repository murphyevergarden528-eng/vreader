import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct VocabularyListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.persistenceActor) private var persistence
    @State private var records: [VocabularyRecord] = []
    @State private var query = ""
    @State private var dueOnly = false
    @State private var isLoading = true
    @State private var editing: VocabularyRecord?
    @State private var deleting: VocabularyRecord?
    @State private var isReviewing = false
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var isBusy = false
    @State private var document = VocabularyBackupDocument(data: Data())
    @State private var errorMessage: String?
    @State private var importMessage: String?

    private var due: [VocabularyRecord] { VocabularyStudyQueue.entries(in: records, now: Date()) }
    private var displayed: [VocabularyRecord] {
        let base = dueOnly ? due : records
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.filter { record in
            search.isEmpty || record.term.localizedCaseInsensitiveContains(search)
                || record.definition.localizedCaseInsensitiveContains(search)
                || record.sources.contains { $0.context.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("筛选", selection: $dueOnly) {
                        Text("全部").tag(false)
                        Text("待复习").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Button { isReviewing = true } label: {
                        Label("开始复习（\(due.count)）", systemImage: "rectangle.on.rectangle")
                    }
                    .accessibilityIdentifier("vocabularyStartReviewButton")
                    .disabled(due.isEmpty || isBusy)
                }
                if isLoading {
                    ProgressView("正在读取生词本…")
                } else if records.isEmpty {
                    Section {
                        Text("还没有生词").font(.headline).accessibilityIdentifier("vocabularyEmptyState")
                        Text("阅读时选中单词或短语，点击“加入生词本”。")
                            .foregroundStyle(.secondary)
                    }
                } else if displayed.isEmpty {
                    Text(query.isEmpty ? "暂时没有待复习的词条" : "没有找到匹配的词条")
                        .foregroundStyle(.secondary)
                }
                ForEach(displayed) { record in
                    Button { editing = record } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.term).font(.title3.weight(.semibold)).foregroundStyle(LibraryCardTokens.ink)
                            Text(record.definition.isEmpty ? "待补充释义" : record.definition)
                                .foregroundStyle(.secondary).lineLimit(2)
                            if let title = record.sources.first?.bookTitle, !title.isEmpty {
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) { deleting = record }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryCardTokens.shellBackground)
            .tint(LibraryCardTokens.accent)
            .navigationTitle("生词本")
            .searchable(text: $query, prompt: "搜索单词、释义或原句")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { isImporting = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("vocabularyImportButton")
                        .disabled(isBusy)
                    Button { Task { await export() } } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("vocabularyExportButton")
                        .disabled(isLoading || isBusy)
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(item: $editing, onDismiss: { Task { await reload() } }) { record in
                VocabularyEditorView(record: record)
            }
            .sheet(isPresented: $isReviewing, onDismiss: { Task { await reload() } }) {
                VocabularyReviewView()
            }
            .confirmationDialog("删除这个词条及其复习记录？", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible) {
                if let deleting {
                    Button("删除", role: .destructive) { Task { await remove(deleting) } }
                }
                Button("取消", role: .cancel) { deleting = nil }
            }
            .alert("操作未完成", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
            .alert("导入完成", isPresented: Binding(
                get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
            )) { Button("好") { importMessage = nil } } message: { Text(importMessage ?? "") }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                Task { await importBackup(result) }
            }
            .fileExporter(isPresented: $isExporting, document: document, contentType: .json,
                          defaultFilename: "VReader生词本") { result in
                if case .failure(let error) = result { errorMessage = ErrorMessageAuditor.sanitize(error) }
            }
        }
    }

    private func reload() async {
        defer { isLoading = false }
        guard let persistence else { errorMessage = "生词数据库暂不可用，请重新打开应用。"; return }
        do { records = try await persistence.fetchVocabulary() }
        catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }

    private func remove(_ record: VocabularyRecord) async {
        guard let persistence, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await persistence.deleteVocabulary(id: record.id)
            deleting = nil
            await reload()
        } catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }

    private func export() async {
        guard let persistence, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            document = VocabularyBackupDocument(data: try await persistence.exportVocabulary())
            isExporting = true
        } catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }

    private func importBackup(_ result: Result<URL, Error>) async {
        guard let persistence, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            let report = try await persistence.importVocabulary(data)
            await reload()
            importMessage = "新增 \(report.added) 个词条，跳过 \(report.skipped) 个已有词条。已有复习进度已保留。"
        } catch { errorMessage = ErrorMessageAuditor.sanitize(error) }
    }
}
