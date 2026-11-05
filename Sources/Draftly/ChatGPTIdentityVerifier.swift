import Foundation
import JWTKit

struct ChatGPTIdentity: Codable, Equatable, Sendable {
    let issuer: String
    let clientID: String
    let subject: String
    let email: String?
    let name: String?
}

/// Trust only signed claims from the official issuer. Never expose raw JWT errors.
actor ChatGPTIdentityVerifier {
    enum Failure: Error, Equatable { case invalidToken, invalidConfiguration, unavailable }
    typealias Load = @Sendable (URL) async throws -> Data
    private static let issuer = "https://auth.openai.com"
    private static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    private let load: Load
    private let now: @Sendable () -> Date
    private var cache: KeySet?
    private var pending: Task<KeySet, any Error>?
    private var lastRotationRefresh: Date?

    init(load: @escaping Load = ChatGPTIdentityVerifier.loadDocument,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.load = load; self.now = now
    }

    func verify(_ token: String, nonce: String, clientID: String,
                expectedSubject: String? = nil) async throws -> ChatGPTIdentity {
        guard !nonce.isEmpty else { throw Failure.invalidToken }
        return try await verifyToken(token, nonce: nonce, clientID: clientID, expectedSubject: expectedSubject)
    }

    func verifyRenewed(_ token: String, identity: ChatGPTIdentity) async throws -> ChatGPTIdentity {
        try await verifyToken(token, nonce: nil, clientID: identity.clientID, expectedSubject: identity.subject)
    }

    private func verifyToken(_ token: String, nonce: String?, clientID: String,
                             expectedSubject: String?) async throws -> ChatGPTIdentity {
        do {
            try Task.checkCancellation()
            guard clientID.hasPrefix("oaiapp_"), token.utf8.count <= 65536 else { throw Failure.invalidToken }
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, let headerBytes = Self.decodeBase64URL(String(parts[0])) else { throw Failure.invalidToken }
            let header = try JSONDecoder().decode(Header.self, from: headerBytes)
            guard header.alg == "RS256", let kid = header.kid, !kid.isEmpty, kid.count <= 256,
                  header.crit?.isEmpty != false, header.b64 != false else { throw Failure.invalidToken }
            let hadCache = cache != nil
            var keySet = try await keys()
            if !keySet.keys.contains(where: { $0.kid == kid }), hadCache,
               now().timeIntervalSince(lastRotationRefresh ?? .distantPast) >= 30 {
                lastRotationRefresh = now()
                keySet = try await keys(force: true)
            }
            let matches = keySet.keys.filter { $0.kid == kid }
            guard matches.count == 1, let key = matches.first, key.kty == "RSA",
                  key.alg == nil || key.alg == "RS256", key.use == nil || key.use == "sig",
                  key.key_ops == nil || key.key_ops?.contains("verify") == true else { throw Failure.invalidToken }
            // Use only the exact selected key. Do not fall back to a default key.
            let collection = JWTKeyCollection()
            let jwks = try JSONEncoder().encode(JWKSRecord(keys: [key]))
            try await collection.add(jwksJSON: String(decoding: jwks, as: UTF8.self))
            let claims = try await collection.verify(token, as: Claims.self)
            let instant = now().timeIntervalSince1970
            guard claims.iss == Self.issuer, !claims.sub.isEmpty,
                  claims.aud.value.contains(clientID), nonce == nil || claims.nonce == nonce,
                  claims.exp.isFinite, claims.iat.isFinite,
                  claims.exp > instant - 5, claims.iat <= instant + 5, claims.exp > claims.iat,
                  claims.nbf == nil || (claims.nbf!.isFinite && claims.nbf! <= instant + 5),
                  claims.azp == nil || claims.azp == clientID,
                  claims.aud.value.count <= 1 || claims.azp == clientID,
                  expectedSubject == nil || claims.sub == expectedSubject else { throw Failure.invalidToken }
            try Task.checkCancellation()
            return ChatGPTIdentity(issuer: claims.iss, clientID: clientID, subject: claims.sub,
                                   email: claims.email, name: claims.name)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as Failure { throw failure }
        catch { throw Failure.invalidToken }
    }

    private func keys(force: Bool = false) async throws -> KeySet {
        if !force, let cache, now().timeIntervalSince(cache.loaded) < 600 { return cache }
        if let pending { return try await pending.value }
        let task = Task { [load, now] in
            let discoveryData = try await load(Self.discoveryURL)
            guard discoveryData.count <= 1048576 else { throw Failure.invalidConfiguration }
            let discovery = try JSONDecoder().decode(Discovery.self, from: discoveryData)
            guard discovery.issuer == Self.issuer,
                  let url = URL(string: discovery.jwks_uri), url.scheme == "https",
                  url.host == "auth.openai.com", url.port == nil, url.user == nil,
                  url.password == nil, url.query == nil, url.fragment == nil else { throw Failure.invalidConfiguration }
            let data = try await load(url)
            guard data.count <= 1048576 else { throw Failure.invalidConfiguration }
            let record = try JSONDecoder().decode(JWKSRecord.self, from: data)
            guard !record.keys.isEmpty, record.keys.count <= 64,
                  Set(record.keys.map(\.kid)).count == record.keys.count else { throw Failure.invalidConfiguration }
            return KeySet(keys: record.keys, loaded: now())
        }
        pending = task
        do {
            let result = try await task.value
            cache = result; pending = nil
            return result
        } catch {
            pending = nil
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? Failure { throw failure }
            throw Failure.unavailable
        }
    }

    private static func decodeBase64URL(_ text: String) -> Data? {
        guard text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        let base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4))
    }

    static func loadDocument(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == url, response.expectedContentLength <= 1048576 else { throw Failure.unavailable }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1048576 else { throw Failure.invalidConfiguration }
            data.append(byte)
        }
        return data
    }

    private struct Header: Decodable { let alg: String; let kid: String?; let crit: [String]?; let b64: Bool? }
    private struct Discovery: Decodable { let issuer: String; let jwks_uri: String }
    private struct KeySet: Sendable { let keys: [Key]; let loaded: Date }
    private struct JWKSRecord: Codable { let keys: [Key] }
    private struct Key: Codable, Sendable {
        let kty: String
        let kid: String
        let alg: String?
        let use: String?
        let key_ops: [String]?
        let n: String?
        let e: String?
    }
    private struct Claims: JWTPayload {
        let iss: String
        let sub: String
        let aud: AudienceClaim
        let nonce: String?
        let exp: Double
        let iat: Double
        let nbf: Double?
        let azp: String?
        let email: String?
        let name: String?

        func verify(using algorithm: some JWTAlgorithm) async throws {
            guard algorithm.name == "RS256" else { throw Failure.invalidToken }
        }
    }
}
