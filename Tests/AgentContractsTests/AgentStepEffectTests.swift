import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent Action effect review")
struct AgentStepEffectTests {
    @Test func everyExecutorStepNeedsAnExplicitClassification() {
        #expect(AgentStepEffectCatalog.stepTypes == DraftAction.supportedSteps)
        for type in DraftAction.supportedSteps {
            guard case .requiresRuntimeChecks(let checks) = AgentStepEffectCatalog.review(type: type, isEnabled: nil) else {
                Issue.record("An enabled executor step has no runtime review: \(type)"); continue
            }
            #expect(!checks.isEmpty)
        }
    }

    @Test func unknownEnabledStepsNeverBecomeSafeButDisabledImportsStaySkipped() {
        #expect(AgentStepEffectCatalog.review(type: "futureStep", isEnabled: nil) == .unsupported)
        #expect(AgentStepEffectCatalog.review(type: "futureStep", isEnabled: true) == .unsupported)
        #expect(AgentStepEffectCatalog.review(type: "futureStep", isEnabled: false) == .skipped)
        #expect(AgentStepEffectCatalog.review(type: "script", isEnabled: false) == .skipped)
    }

    @Test func scriptAndIncludedActionReviewsCannotSubstituteForDynamicChecks() {
        #expect(AgentStepEffectCatalog.review(type: "script", isEnabled: true) == .requiresRuntimeChecks([.scriptRuntime]))
        #expect(AgentStepEffectCatalog.review(type: "includeAction", isEnabled: true) == .requiresRuntimeChecks([.includedAction, .templateRead]))
        #expect(AgentStepEffectCatalog.executionChecks == [.initialConfiguration, .finalDisposition, .queuedAction])
    }

    @Test func clipboardReviewCoversReadsAndWritesWithoutChangingStepDefaults() {
        #expect(AgentStepEffectCatalog.review(type: "clipboard", isEnabled: nil) == .requiresRuntimeChecks([
            .clipboardRead, .clipboardWrite, .templateRead
        ]))
    }

    @Test func schemaQueryEnumsStayCompatibleWithExistingDomainNames() throws {
        let shape = try #require(AgentReadSchemas.schema(for: "drafts.list"))
        guard case .string(_, _, let folders) = shape.parameters.fields["folder"]?.shape,
              case .string(_, _, let sorts) = shape.parameters.fields["sort"]?.shape else {
            Issue.record("Query enum shapes are missing"); return
        }
        #expect(Set(folders ?? []) == Set(NoteFolder.allCases.map(\.rawValue)))
        #expect(Set(sorts ?? []) == Set(NoteSort.allCases.map(\.rawValue)))
    }
}
