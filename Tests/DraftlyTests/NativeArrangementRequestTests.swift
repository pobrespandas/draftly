import Foundation
import Testing
@testable import Draftly

@Suite("Async arrangement requests") @MainActor
struct NativeArrangementRequestTests {
    @Test func acceptanceReturnsTheArrangedUnicodeText() async throws {
        let original = "🐼 café\nTail\n"
        let arranged = "Tail\n🐼 café\n"
        let result = try await NativeArrangementRequest.arrange(original) { source in
            #expect(source == original)
            return arranged
        }
        #expect(result == arranged)
    }

    @Test func userCancellationReturnsTheExactOriginalText() async throws {
        let original = "🐼 café\r\nTail\n"
        #expect(try await NativeArrangementRequest.arrange(original) { _ in nil } == original)
    }

    @Test func taskCancellationRejectsAnAcceptedLateResult() async throws {
        let gate = ArrangementTestGate()
        let task = Task { try await NativeArrangementRequest.arrange("Original") { await gate.present($0) } }
        await gate.waitForStart()
        task.cancel()
        gate.finish("Late")
        do {
            _ = try await task.value
            Issue.record("A cancelled task must not accept the late result.")
        } catch { #expect(error is CancellationError) }
    }
}

@MainActor final class ArrangementTestGate {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var text: String?
    func present(_ text: String) async -> String? {
        self.text = text
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(true)
        }
    }
    func waitForStart() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func finish(_ text: String?) {
        continuation?.resume(returning: text)
        continuation = nil
    }
}
