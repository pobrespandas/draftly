import Foundation
import Testing
@testable import DraftlyCore

@Suite("Suspending template builders") @MainActor
struct ActionTemplateBuilderTests {
    @Test func repeatedSourcesKeepTheirOwnResultsAndRenderInCallOrder() async throws {
        var sources: [String] = []
        let values = try await ActionTemplateBuilder.build(render: { source in
            sources.append(source)
            await Task.yield()
            return String(sources.count)
        }) { render in [try render("Same"), try render("Same"), try render("Last")] }
        #expect(sources == ["Same", "Same", "Last"])
        #expect(values == ["1", "2", "3"])
    }

    @Test func validationBeforeRenderingDoesNotRequestNativeData() async {
        enum Failure: Error { case invalid }
        do {
            let _: String = try await ActionTemplateBuilder.build(render: { _ in
                Issue.record("An invalid builder requested native data."); return "Unexpected"
            }) { _ in throw Failure.invalid }
            Issue.record("Invalid input succeeded.")
        } catch { #expect(error is Failure) }
    }

    @Test func renderFailureStopsBeforeTheNextField() async {
        enum Failure: Error { case denied }
        var sources: [String] = []
        do {
            let _: [String] = try await ActionTemplateBuilder.build(render: { text in
                sources.append(text)
                throw Failure.denied
            }) { render in [try render("First"), try render("Later")] }
            Issue.record("A failed render succeeded.")
        } catch { #expect(error is Failure) }
        #expect(sources == ["First"])
    }
}
