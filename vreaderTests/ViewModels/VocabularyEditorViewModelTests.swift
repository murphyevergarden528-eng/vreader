import Foundation
import Testing
@testable import vreader

@Suite("Vocabulary editor asynchronous drafts")
struct VocabularyEditorViewModelTests {
    @Test @MainActor func aiIsExplicitAndDoesNotRunOnInitialization() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        #expect(vm.definition.isEmpty)
        #expect(!vm.isGenerating)
        #expect(await gate.count == 0)
    }

    @Test @MainActor func editedDefinitionRejectsLateAIResponse() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        let request = Task { await vm.generateDefinition() }
        await gate.waitForRequest()
        vm.definition = "我自己的释义"
        await gate.finish("迟到的释义")
        await request.value
        #expect(vm.definition == "我自己的释义")
        #expect(!vm.isGenerating)
    }

    @Test @MainActor func changedTermRejectsLateAIResponseEvenWhenChangedBack() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        let request = Task { await vm.generateDefinition() }
        await gate.waitForRequest()
        vm.term = "other"
        vm.term = "word"
        await gate.finish("迟到的释义")
        await request.value
        #expect(vm.definition.isEmpty)
    }

    @Test @MainActor func editedContextRejectsLateAIResponse() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", context: "original", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        let request = Task { await vm.generateDefinition() }
        await gate.waitForRequest()
        vm.context = "corrected context"
        await gate.finish("旧语境释义")
        await request.value
        #expect(vm.definition.isEmpty)
        #expect(!vm.isGenerating)
    }

    @Test @MainActor func canceledRequestCannotWriteDraft() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        let request = Task { await vm.generateDefinition() }
        await gate.waitForRequest()
        vm.cancelDefinition()
        #expect(!vm.isGenerating)
        await gate.finish("已取消的释义")
        await request.value
        #expect(vm.definition.isEmpty)
    }

    @Test @MainActor func cancelledOldRequestCannotFinishNewRequest() async {
        let oldGate = VocabularyDefinitionGate()
        let newGate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            if await oldGate.count == 0 {
                return try await oldGate.request(term: term, context: context)
            }
            return try await newGate.request(term: term, context: context)
        })
        let oldRequest = Task { await vm.generateDefinition() }
        await oldGate.waitForRequest()
        vm.cancelDefinition()
        let newRequest = Task { await vm.generateDefinition() }
        await newGate.waitForRequest()
        await oldGate.finish("旧请求")
        await oldRequest.value
        #expect(vm.isGenerating)
        #expect(vm.definition.isEmpty)
        await newGate.finish("新请求")
        await newRequest.value
        #expect(!vm.isGenerating)
        #expect(vm.definition == "新请求")
    }

    @Test @MainActor func successfulResponseBecomesEditableDraft() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: "word", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        let request = Task { await vm.generateDefinition() }
        await gate.waitForRequest()
        #expect(vm.isGenerating)
        await gate.finish("词语：表达含义的语言单位。")
        await request.value
        #expect(vm.definition == "词语：表达含义的语言单位。")
        vm.definition = "修订后的释义"
        #expect(vm.definition == "修订后的释义")
    }

    @Test @MainActor func networkFailureKeepsDraftAndAllowsRetry() async {
        let vm = VocabularyEditorViewModel(term: "word", definition: "已有释义", definitionLoader: { _, _ in
            throw URLError(.notConnectedToInternet)
        })
        await vm.generateDefinition()
        #expect(vm.definition == "已有释义")
        #expect(vm.errorMessage != nil)
        #expect(!vm.isGenerating)
    }

    @Test @MainActor func emptyTermDoesNotRequestAI() async {
        let gate = VocabularyDefinitionGate()
        let vm = VocabularyEditorViewModel(term: " \n ", definitionLoader: { term, context in
            try await gate.request(term: term, context: context)
        })
        await vm.generateDefinition()
        #expect(await gate.count == 0)
        #expect(!vm.isGenerating)
    }
}

private actor VocabularyDefinitionGate {
    private var continuation: CheckedContinuation<String, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var count = 0

    func request(term: String, context: String) async throws -> String {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForRequest() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func finish(_ value: String) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
