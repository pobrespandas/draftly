import Foundation
import Testing
import Darwin
import AgentContracts
import AgentLocalTransport
import AgentLocalSecurity
@testable import DraftlyCore
@testable import Draftly

@Suite("Private local agent transport") @MainActor
struct AgentLocalTransportTests {
    private func pair() throws -> (AgentUnixChannel, Int32) {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw AgentErrorCode.unavailable }
        return (try AgentUnixChannel(descriptor: descriptors[0]), descriptors[1])
    }
    private func send(_ bytes: [UInt8], to fd: Int32) throws {
        let size = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress!, $0.count, 0) }
        #expect(size == bytes.count)
    }
    private func listener() throws -> AgentUnixListener { try AgentUnixListener(parentDirectory: FileManager.default.temporaryDirectory) }

    @MainActor private final class Fixture {
        let library: LibraryStore
        let libraryID = UUID()
        var data: Data?
        var credentials: [UUID: Data] = [:]
        var credentialReads = 0
        var locked = false
        lazy var registry = AgentConnectionRegistry(metadata: .init(read: { [unowned self] in self.data }, replace: { [unowned self] data, expected in
            guard self.data == expected else { throw AgentErrorCode.versionConflict }; self.data = data
        }), credentials: .init(read: { [unowned self] id in self.credentialReads += 1; return self.credentials[id] }, create: { [unowned self] in self.credentials[$0] = $1 },
                             remove: { [unowned self] in self.credentials.removeValue(forKey: $0) }), authorityChanged: { _ in })
        var service: AgentCommandService!
        init() throws {
            library = try LibraryStore(inMemory: true, seed: false)
            service = try AgentCommandService(library: library, libraryID: libraryID, connections: registry, appVersion: "QA",
                isLocked: { [unowned self] in self.locked }, pendingEditorGeneration: { _ in "" })
            try registry.setEnabledFromUserInterface(true)
        }
        func connection(scope: AgentResourceScope = .library) throws -> AgentConnectionRecord {
            try registry.connectFromUserInterface(name: "Neutral local QA", libraryID: libraryID, scope: scope)
        }
        func broker() throws -> AgentSocketBroker {
            try AgentSocketBroker(service: service, parentDirectory: FileManager.default.temporaryDirectory,
                                  validateHelper: { guard $0.count == 32 && $0.contains(where: { $0 != 0 }) else { throw AgentErrorCode.permissionDenied } })
        }
        func client(_ connection: AgentConnectionRecord, broker: AgentSocketBroker) async throws -> AgentLocalClient {
            try await AgentLocalClient.connect(path: broker.path, connectionID: connection.id,
                credential: #require(credentials[connection.id]), validateServer: { guard $0.count == 32 && $0.contains(where: { $0 != 0 }) else { throw AgentErrorCode.permissionDenied } })
        }
        func request(_ operation: String, libraryID: UUID? = nil) throws -> Data {
            try JSONEncoder().encode(AgentRequest(requestID: UUID(), libraryID: libraryID, operation: operation))
        }
    }

    @Test func realSocketReadsBindTheHostLibraryAndPreserveScope() async throws {
        let f = try Fixture(), allowed = try f.library.createNote(content: "Neutral 🐼")
        _ = try f.library.createNote(content: "Hidden")
        let connection = try f.connection(scope: .resources([.init(kind: .draft, id: allowed.id)])), broker = try f.broker()
        defer { broker.stop() }
        let client = try await f.client(connection, broker: broker)
        #expect(await client.libraryID == f.libraryID)
        let before = try f.library.backupData()
        let response = try JSONDecoder().decode(AgentResponse.self, from: await client.request(f.request("library.summary")))
        #expect(response.outcome == .result(.object(["draftCount": .integer(1)])))
        let wrongLibrary = try JSONDecoder().decode(AgentResponse.self, from: await client.request(f.request("server.status", libraryID: UUID())))
        #expect(wrongLibrary.outcome == .error(.permissionDenied))
        #expect(try f.library.backupData() == before)
        await client.close()
    }

    @Test func wrongCredentialAndRevocationAreReturnedWithoutAnotherAuthentication() async throws {
        let f = try Fixture(), connection = try f.connection(), broker = try f.broker()
        defer { broker.stop() }
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await AgentLocalClient.connect(path: broker.path, connectionID: connection.id, credential: Data(repeating: 0, count: 32), validateServer: { _ in })
        }
        let client = try await f.client(connection, broker: broker)
        _ = try f.registry.revokeFromUserInterface(connection.id)
        let result = try JSONDecoder().decode(AgentResponse.self, from: await client.request(f.request("server.status")))
        #expect(result.outcome == .error(.permissionDenied))
        await client.close()
    }

    @Test func realPeerSignatureValidationRejectsTheTestProcessBeforeAuthentication() async throws {
        let f = try Fixture(), broker = try f.broker(), connection = try f.connection()
        defer { broker.stop() }
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await AgentLocalClient.connect(path: broker.path, connectionID: connection.id,
                credential: #require(f.credentials[connection.id]), validateServer: { try AgentPeerIdentity.validate($0, role: .application) })
        }
        #expect(throws: AgentErrorCode.permissionDenied) { try AgentPeerIdentity.validate(Data(), role: .helper) }
    }

    @Test func socketModesOwnershipAndCleanupArePrivateAndIdempotent() throws {
        let server = try listener(), path = server.path
        let parent = (path as NSString).deletingLastPathComponent
        var info = stat()
        #expect(lstat(parent, &info) == 0 && info.st_mode & 0o777 == 0o700 && info.st_uid == geteuid())
        #expect(lstat(path, &info) == 0 && info.st_mode & 0o777 == 0o600 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK))
        server.close(); server.close()
        #expect(!FileManager.default.fileExists(atPath: parent))
    }

    @Test func unsafeSocketPermissionsAndSymlinkAliasesAreRejected() async throws {
        let server = try listener(), path = server.path, parent = (path as NSString).deletingLastPathComponent
        defer { server.close() }
        #expect(lchmod(path, 0o666) == 0)
        await #expect(throws: AgentErrorCode.permissionDenied) { try await AgentUnixChannel.connect(path: path, validatePeer: { _ in }) }
        #expect(lchmod(path, 0o600) == 0)
        let alias = parent + "/alias"
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: path)
        defer { try? FileManager.default.removeItem(atPath: alias) }
        await #expect(throws: AgentErrorCode.permissionDenied) { try await AgentUnixChannel.connect(path: alias, validatePeer: { _ in }) }
    }

    @Test func framesRoundTripIncludingTheMaximumBudget() async throws {
        for count in [1, 65_536, AgentRequest.maximumBytes] {
            let (reader, raw) = try pair(), writer = try AgentUnixChannel(descriptor: raw)
            defer { reader.close(); writer.close() }
            let data = Data(repeating: 7, count: count)
            async let writing: Void = writer.writeFrame(data)
            #expect(try await reader.readFrame() == data)
            try await writing
        }
    }

    @Test func oversizedAndEmptyHeadersFailBeforeReadingTheirPayload() async throws {
        for bytes: [UInt8] in [[0, 0, 0, 0], [255, 255, 255, 255], [0, 128, 0, 1]] {
            let (reader, raw) = try pair()
            defer { reader.close(); Darwin.close(raw) }
            try send(bytes, to: raw)
            await #expect(throws: AgentErrorCode.invalidInput) { try await reader.readFrame() }
        }
    }

    @Test func truncatedFramesTimeoutAndCancellationClosesPendingIO() async throws {
        let (reader, raw) = try pair()
        defer { reader.close(); Darwin.close(raw) }
        try send([0, 0, 0, 4, 1, 2], to: raw)
        await #expect(throws: AgentErrorCode.timeout) { try await reader.readFrame(timeout: 0.02) }
        let task = Task { try await reader.readFrame(timeout: 5) }
        await Task.yield(); task.cancel()
        await #expect(throws: AgentErrorCode.cancelled) { try await task.value }
    }

    @Test func stoppedBrokerRemovesTheEndpointAndDisconnectsClients() async throws {
        let f = try Fixture(), broker = try f.broker(), connection = try f.connection()
        let client = try await f.client(connection, broker: broker), path = broker.path
        broker.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        await #expect(throws: (any Error).self) { try await client.request(f.request("server.status")) }
        await client.close()
    }

    @Test func productionBrokerRejectsAnUnsignedHelperBeforeReadingCredentials() async throws {
        let f = try Fixture(), record = try f.connection()
        let broker = try AgentSocketBroker(service: f.service, parentDirectory: FileManager.default.temporaryDirectory)
        defer { broker.stop() }
        await #expect(throws: (any Error).self) { try await f.client(record, broker: broker) }
        #expect(f.credentialReads == 0)
    }

    @Test func clientRejectsAResponseForAnotherRequest() async throws {
        let server = try listener()
        defer { server.close() }
        let task = Task {
            let peer = try await server.accept()
            defer { peer.close() }
            _ = try await peer.readFrame(maximumBytes: AgentLocalHandshake.maximumBytes)
            try await peer.writeFrame(JSONEncoder().encode(AgentLocalHandshake.Welcome(libraryID: UUID())))
            _ = try await peer.readFrame()
            try await peer.writeFrame(JSONEncoder().encode(AgentResponse(requestID: UUID(), outcome: .error(.busy))))
        }
        defer { task.cancel() }
        let client = try await AgentLocalClient.connect(path: server.path, connectionID: UUID(), credential: Data(repeating: 1, count: 32), validateServer: { _ in })
        let request = try JSONEncoder().encode(AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status"))
        await #expect(throws: AgentErrorCode.invalidInput) { try await client.request(request) }
        try await task.value
        await client.close()
    }

    @Test func deinitializingBrokerClosesItsListenerWithoutAnExplicitStop() throws {
        let f = try Fixture()
        var broker: AgentSocketBroker? = try f.broker()
        let path = try #require(broker?.path)
        broker = nil
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func disabledOrLockedAccessCannotConstructAListener() throws {
        let f = try Fixture()
        try f.registry.setEnabledFromUserInterface(false)
        #expect(throws: AgentErrorCode.permissionDenied) { try f.broker() }
        try f.registry.setEnabledFromUserInterface(true)
        f.locked = true
        #expect(throws: AgentErrorCode.permissionDenied) { try f.broker() }
    }
}
