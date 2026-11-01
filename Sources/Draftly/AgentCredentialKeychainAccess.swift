import AgentLocalSecurity

@MainActor extension AgentCredentialKeychain {
    var registryAccess: AgentConnectionRegistry.CredentialAccess {
        .init(read: { [self] in try read($0) }, create: { [self] in try create($0, credential: $1) },
              remove: { [self] in try remove($0) })
    }
}
