import Foundation
import Security
import JWTKit
import Testing
@testable import Draftly

@Suite("ChatGPT identity verification") @MainActor
struct ChatGPTIdentityVerifierTests {
    private static let instant = Date(timeIntervalSince1970: 1700000000)

    private struct SigningKey {
        let privateKey: SecKey
        let jwk: [String: String]

        init(kid: String = "neutral-key") throws {
            // Ephemeral test keys never enter Keychain or files.
            privateKey = try #require(SecKeyCreateRandomKey([
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 2048
            ] as CFDictionary, nil))
            let raw = try #require(SecKeyCopyExternalRepresentation(privateKey, nil)) as Data
            let pem = "-----BEGIN RSA PRIVATE KEY-----\n" + raw.base64EncodedString() + "\n-----END RSA PRIVATE KEY-----"
            let key = try JWTKit.Insecure.RSA.PrivateKey(pem: pem)
            let primitives = try key.publicKey.getKeyPrimitives()
            jwk = ["kty": "RSA", "kid": kid, "alg": "RS256", "use": "sig",
                   "n": Self.base64(primitives.modulus), "e": Self.base64(primitives.publicExponent)]
        }

        func token(_ claims: [String: Any], header: [String: Any]? = nil) throws -> String {
            let header = header ?? ["alg": "RS256", "kid": jwk["kid"]!, "typ": "JWT"]
            let input = Self.base64(try JSONSerialization.data(withJSONObject: header)) + "." +
                Self.base64(try JSONSerialization.data(withJSONObject: claims))
            let signature = try #require(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                                                               Data(input.utf8) as CFData, nil)) as Data
            return input + "." + Self.base64(signature)
        }

        static func base64(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
    }

    private actor Documents {
        let sets: [Data]
        let issuer: String
        let jwksURI: String
        var requests = 0
        private var keyRequests = 0

        init(_ sets: [Data], issuer: String = "https://auth.openai.com",
             jwksURI: String = "https://auth.openai.com/.well-known/jwks.json") {
            self.sets = sets; self.issuer = issuer; self.jwksURI = jwksURI
        }

        func load(_ url: URL) throws -> Data {
            requests += 1
            if url.path == "/.well-known/openid-configuration" {
                return try JSONSerialization.data(withJSONObject: ["issuer": issuer, "jwks_uri": jwksURI])
            }
            let result = sets[min(keyRequests, sets.count - 1)]
            keyRequests += 1
            return result
        }
    }

    private func claims() -> [String: Any] {
        ["iss": "https://auth.openai.com", "sub": "neutral-subject", "aud": "oaiapp_test",
         "nonce": "neutral-nonce", "iat": Self.instant.timeIntervalSince1970,
         "exp": Self.instant.timeIntervalSince1970 + 60, "email": "neutral@example.invalid"]
    }

    private func keySet(_ keys: [SigningKey]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["keys": keys.map(\.jwk)])
    }

    private func verifier(_ documents: Documents) -> ChatGPTIdentityVerifier {
        let instant = Self.instant
        return ChatGPTIdentityVerifier(load: { try await documents.load($0) }, now: { instant })
    }

    @Test func independentlySignedTokenAndCachedKeys() async throws {
        let key = try SigningKey(), documents = try Documents([keySet([key])])
        var arrayAudience = claims(); arrayAudience["aud"] = ["oaiapp_test"]
        let verifier = verifier(documents), token = try key.token(arrayAudience)
        let identity = try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
        #expect(identity.subject == "neutral-subject" && identity.clientID == "oaiapp_test")
        #expect(identity.email == "neutral@example.invalid")
        #expect(try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test") == identity)
        #expect(try await verifier.verify(key.token(claims()), nonce: "neutral-nonce", clientID: "oaiapp_test") == identity)
        #expect(await documents.requests == 2)
    }

    @Test func rejectsSignatureAndEveryIdentityBoundary() async throws {
        let key = try SigningKey(), other = try SigningKey()
        let documents = try Documents([keySet([key])]), verifier = verifier(documents)
        let forged = try other.token(claims())
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verify(forged, nonce: "neutral-nonce", clientID: "oaiapp_test")
        }
        let changes: [(String, Any?)] = [("iss", "https://other.invalid"), ("sub", ""), ("sub", nil),
            ("exp", nil), ("iat", nil), ("aud", nil),
            ("aud", "oaiapp_other"), ("nonce", "wrong"), ("exp", Self.instant.timeIntervalSince1970 - 6),
            ("iat", Self.instant.timeIntervalSince1970 + 6), ("nbf", Self.instant.timeIntervalSince1970 + 6),
            ("azp", "oaiapp_other"), ("aud", ["oaiapp_test", "oaiapp_other"])]
        for (name, value) in changes {
            var payload = claims(); payload[name] = value
            let token = try key.token(payload)
            await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
                try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
            }
        }
        let token = try key.token(claims())
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test", expectedSubject: "other-account")
        }
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verify(token, nonce: "different-attempt", clientID: "oaiapp_test")
        }
    }

    @Test func renewedTokenWithoutLoginNonceRequiresThePreviouslyVerifiedAccount() async throws {
        let key = try SigningKey(), documents = try Documents([keySet([key])]), verifier = verifier(documents)
        var renewed = claims(); renewed["nonce"] = nil
        let token = try key.token(renewed)
        let identity = ChatGPTIdentity(issuer: "https://auth.openai.com", clientID: "oaiapp_test",
                                      subject: "neutral-subject", email: nil, name: nil)
        #expect(try await verifier.verifyRenewed(token, identity: identity).subject == identity.subject)
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
        }
        let wrongAccount = ChatGPTIdentity(issuer: identity.issuer, clientID: identity.clientID,
                                          subject: "other-subject", email: nil, name: nil)
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verifyRenewed(token, identity: wrongAccount)
        }
    }

    @Test func rejectsUntrustedAlgorithmsAndCriticalHeadersBeforeFetchingKeys() async throws {
        let key = try SigningKey(), documents = try Documents([keySet([key])]), verifier = verifier(documents)
        let headers: [[String: Any]] = [["alg": "none", "kid": "neutral-key"],
            ["alg": "HS256", "kid": "neutral-key"], ["alg": "RS256"],
            ["alg": "RS256", "kid": "neutral-key", "crit": ["unknown"]],
            ["alg": "RS256", "kid": "neutral-key", "b64": false]]
        for header in headers {
            let token = try key.token(claims(), header: header)
            await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
                try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
            }
        }
        #expect(await documents.requests == 0)
    }

    @Test func refreshesRotatedKeysAndLimitsUnknownKeyRefreshes() async throws {
        let first = try SigningKey(kid: "first"), next = try SigningKey(kid: "next"), unknown = try SigningKey(kid: "unknown")
        let documents = try Documents([keySet([first]), keySet([next])]), verifier = verifier(documents)
        _ = try await verifier.verify(first.token(claims()), nonce: "neutral-nonce", clientID: "oaiapp_test")
        _ = try await verifier.verify(next.token(claims()), nonce: "neutral-nonce", clientID: "oaiapp_test")
        let token = try unknown.token(claims())
        await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidToken) {
            try await verifier.verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
        }
        #expect(await documents.requests == 4)
    }

    @Test func rejectsDiscoveryRedirectToOtherIssuerOrHostAndDuplicateKeys() async throws {
        let key = try SigningKey(), token = try key.token(claims())
        for documents in [try Documents([keySet([key])], issuer: "https://other.invalid"),
                          try Documents([keySet([key])], jwksURI: "https://other.invalid/keys"),
                          try Documents([keySet([key, key])])] {
            await #expect(throws: ChatGPTIdentityVerifier.Failure.invalidConfiguration) {
                try await verifier(documents).verify(token, nonce: "neutral-nonce", clientID: "oaiapp_test")
            }
        }
    }
}
