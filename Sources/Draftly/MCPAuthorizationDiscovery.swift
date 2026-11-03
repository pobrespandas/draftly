import Foundation

struct MCPAuthorizationServer: Equatable {
    let resource: URL
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let scopesSupported: Set<String>
}

struct MCPAuthorizationDiscovery {
    enum Failure: Error { case invalidURL, unavailable, invalidMetadata, chooseAuthorizationServer, unsupportedPKCE }
    typealias Fetch = @Sendable (URLRequest) async throws -> ChatGPTHTTP.Response
    private let fetch: Fetch

    init(fetch: @escaping Fetch = ChatGPTHTTP.perform) { self.fetch = fetch }

    func discover(endpoint: URL, metadataURL: URL? = nil, issuer: URL? = nil) async throws -> MCPAuthorizationServer {
        let resource = try Self.resource(endpoint)
        let candidates: [URL]
        if let metadataURL {
            guard Self.secure(metadataURL) else { throw Failure.invalidURL }
            candidates = [metadataURL]
        } else {
            candidates = Self.urls(resource, paths: ["/.well-known/oauth-protected-resource" + resource.path,
                                                     "/.well-known/oauth-protected-resource"])
        }
        let metadata: ResourceMetadata = try await document(candidates)
        guard try Self.resource(metadata.resource) == resource, !metadata.authorization_servers.isEmpty,
              metadata.authorization_servers.allSatisfy({ Self.validIssuer($0) }) else { throw Failure.invalidMetadata }
        let selected: URL
        if let issuer {
            guard metadata.authorization_servers.contains(issuer) else { throw Failure.invalidMetadata }
            selected = issuer
        } else {
            guard metadata.authorization_servers.count == 1 else { throw Failure.chooseAuthorizationServer }
            selected = metadata.authorization_servers[0]
        }
        let path = selected.path == "/" ? "" : selected.path
        var paths = ["/.well-known/oauth-authorization-server" + path,
                     "/.well-known/openid-configuration" + path]
        if !path.isEmpty { paths.append(path + "/.well-known/openid-configuration") }
        let server: ServerMetadata = try await document(Self.urls(selected, paths: paths))
        guard server.issuer == selected, Self.secure(server.authorization_endpoint), Self.secure(server.token_endpoint),
              server.registration_endpoint.map(Self.secure) ?? true else { throw Failure.invalidMetadata }
        guard server.code_challenge_methods_supported?.contains("S256") == true else { throw Failure.unsupportedPKCE }
        return MCPAuthorizationServer(resource: resource, issuer: selected,
            authorizationEndpoint: server.authorization_endpoint, tokenEndpoint: server.token_endpoint,
            registrationEndpoint: server.registration_endpoint, scopesSupported: Set(metadata.scopes_supported ?? []))
    }

    private func document<T: Decodable>(_ urls: [URL]) async throws -> T {
        for url in urls {
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await fetch(request)
            if response.status == 404 { continue }
            guard response.status == 200, response.data.count <= 1048576 else { throw Failure.unavailable }
            do { return try JSONDecoder().decode(T.self, from: response.data) }
            catch { throw Failure.invalidMetadata }
        }
        throw Failure.unavailable
    }

    static func resource(_ url: URL) throws -> URL {
        guard secure(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidURL
        }
        components.query = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        guard let result = components.url else { throw Failure.invalidURL }
        return result
    }

    private static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil && url.fragment == nil
    }

    private static func validIssuer(_ url: URL) -> Bool { secure(url) && url.query == nil }

    private static func urls(_ origin: URL, paths: [String]) -> [URL] {
        var components = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        components.query = nil
        var results: [URL] = []
        for path in paths {
            components.path = path
            if let url = components.url, !results.contains(url) { results.append(url) }
        }
        return results
    }

    private struct ResourceMetadata: Decodable {
        let resource: URL
        let authorization_servers: [URL]
        let scopes_supported: [String]?
    }
    private struct ServerMetadata: Decodable {
        let issuer: URL
        let authorization_endpoint: URL
        let token_endpoint: URL
        let registration_endpoint: URL?
        let code_challenge_methods_supported: [String]?
    }
}
