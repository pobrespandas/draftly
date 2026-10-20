import Foundation
import Testing
@testable import DraftlyCore

@Suite("Worker promise step lifetime")
struct WorkerPromiseEpochTests {
    private func worker() -> ActionScriptWorker {
        ActionScriptWorker(executionID: UUID(), stepID: UUID(), hostTimeout: 1) { request in
            request.operation == "device" ? "{\"value\":{}}" : "{\"value\":null}"
        }
    }

    @Test(arguments: [
        "setTimeout(function(){Promise.reject(new Error('Old timer rejection'));},1);script.complete();",
        "void (async function(){await new Promise(function(resolve){setTimeout(resolve,1);});throw new Error('Old intrinsic rejection');})();script.complete();"
    ])
    func completedStepCannotRejectDuringTheNextWaitingStep(source: String) async throws {
        let worker = worker()
        try await worker.start("")
        do {
            #expect(try await worker.run(source: source, stepID: UUID(), asynchronous: true, timeout: 1, synchronousTimeout: 1))
            let next = "setTimeout(function(){script.complete();},30);"
            #expect(try await worker.run(source: next, stepID: UUID(), asynchronous: true, timeout: 1, synchronousTimeout: 1))
            await worker.close()
        } catch {
            await worker.close()
            throw error
        }
    }

    @Test func caughtIntrinsicRejectionDoesNotLeakIntoTheNextStep() async throws {
        let worker = worker()
        try await worker.start("")
        do {
            let source = "void (async function(){throw new Error('Caught');})().catch(function(){script.complete();});"
            #expect(try await worker.run(source: source, stepID: UUID(), asynchronous: true, timeout: 1, synchronousTimeout: 1))
            #expect(try await worker.run(source: "script.complete();", stepID: UUID(), asynchronous: true, timeout: 1, synchronousTimeout: 1))
            await worker.close()
        } catch {
            await worker.close()
            throw error
        }
    }
}
