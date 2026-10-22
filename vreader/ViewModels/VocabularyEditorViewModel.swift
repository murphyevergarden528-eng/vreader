import Foundation
import Observation

/// The draft is independent of persistence so failed saves and AI requests cannot erase it.
@MainActor
@Observable
final class VocabularyEditorViewModel {
    typealias DefinitionLoader = @Sendable (String, String) async throws -> String

    var term: String { didSet { editRevision += 1 } }
    var definition: String { didSet { editRevision += 1 } }
    var context: String { didSet { editRevision += 1 } }
    private(set) var isGenerating = false
    var errorMessage: String?
    @ObservationIgnored private var editRevision = 0
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var requestTask: Task<String, Error>?
    @ObservationIgnored private let definitionLoader: DefinitionLoader

    init(term: String, definition: String = "", context: String = "",
         definitionLoader: DefinitionLoader? = nil) {
        self.term = term
        self.definition = definition
        self.context = context
        if let definitionLoader {
            self.definitionLoader = definitionLoader
        } else {
            let service = AIService(featureFlags: .shared, consentManager: AIConsentManager(),
                                    keychainService: KeychainService())
            self.definitionLoader = { term, context in
                let config = try await service.resolveActiveProviderConfig()
                let request = AIRequest(
                    actionType: .vocabulary, bookFingerprint: nil, locator: nil,
                    contextText: context,
                    userPrompt: "请用中文解释词条“\(term)”在所给原句中的含义。给出简洁释义和必要的用法说明，不要解释其他词。没有原句时说明常见含义。",
                    targetLanguage: "zh-Hans", promptVersion: "vocabulary-definition-v1"
                )
                return try await service.sendRequest(request, using: config).content
            }
        }
    }

    func generateDefinition() async {
        let selectedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedTerm.isEmpty, !isGenerating else { return }
        let generation = UUID()
        let revision = editRevision
        let selectedContext = context
        let loader = definitionLoader
        let job = Task { try await loader(selectedTerm, selectedContext) }
        requestTask = job
        requestID = generation
        isGenerating = true
        errorMessage = nil
        defer {
            if requestID == generation {
                isGenerating = false
                requestID = nil
                requestTask = nil
            }
        }
        do {
            let response = try await withTaskCancellationHandler {
                try await job.value
            } onCancel: {
                job.cancel()
            }
            guard requestID == generation, editRevision == revision, !Task.isCancelled else { return }
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "AI 未返回释义，请重试或手动填写。"
                return
            }
            definition = response
        } catch {
            guard requestID == generation, editRevision == revision, !Task.isCancelled else { return }
            if !(error is CancellationError) {
                errorMessage = "AI 解释失败：\(ErrorMessageAuditor.sanitize(error))"
            }
        }
    }

    func cancelDefinition() {
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        isGenerating = false
    }
}
