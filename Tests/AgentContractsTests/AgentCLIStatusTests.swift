import Testing
import AgentContracts

@Suite("Agent CLI failure exit status")
struct AgentCLIStatusTests {
    @Test func failuresUseTheApprovedCategoriesWithoutReportingSuccess() {
        let expected: [AgentErrorCode: Int32] = [.invalidInput: 2, .permissionDenied: 3, .interactionRequired: 3,
            .versionConflict: 4, .editorConflict: 4, .busy: 4, .unavailable: 5,
            .notFound: 1, .storageError: 1, .executionError: 1, .cancelled: 1,
            .timeout: 1, .outcomeUnknown: 1, .retryWindowExpired: 1]
        #expect(Set(expected.keys) == Set(AgentErrorCode.allCases))
        for (error, status) in expected { #expect(AgentCLIStatus.exitCode(error) == status) }
    }
}
