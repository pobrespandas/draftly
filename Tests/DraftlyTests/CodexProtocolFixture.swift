import Foundation
@testable import Draftly

@MainActor extension CodexAppServerClient {
    static func protocolFixture() -> CodexAppServerClient {
        CodexAppServerClient(makeLaunchPlan: { executable, _ in
            CodexLaunchPlan(executable: executable,
                arguments: ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"keyring\""])
        })
    }
}
