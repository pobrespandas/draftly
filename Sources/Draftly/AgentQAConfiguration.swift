import Foundation

/// QA-only startup. Production builds cannot activate this adapter.
@MainActor enum AgentQAConfiguration {
    static var isActive: Bool {
        #if DRAFTLY_AGENT_QA
        let bundle = Bundle.main
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing") || bundle.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true
        return testing && (arguments.contains("--agent-isolated-qa")
            || bundle.object(forInfoDictionaryKey: "DraftlyAgentIsolatedQA") as? Bool == true)
        #else
        return false
        #endif
    }

    private static let fallbackID = UUID()
    static var chatNamespace: String? {
        guard isActive else { return nil }
        let id = (Bundle.main.object(forInfoDictionaryKey: "DraftlyUITestingLibraryID") as? String)
            .flatMap(UUID.init(uuidString:)) ?? fallbackID
        return "com.pobrespandas.draftly.agent-chat-qa." + id.uuidString.lowercased()
    }

    static var chatDefaults: UserDefaults? { chatNamespace.flatMap(UserDefaults.init(suiteName:)) }
}
