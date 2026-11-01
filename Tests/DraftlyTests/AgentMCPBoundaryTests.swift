import Foundation
import Testing
import MCP
import Darwin
import AgentContracts
import AgentMCP
import AgentLocalTransport

@Suite("Bounded lossless MCP input") @MainActor
struct AgentMCPBoundaryTests {
    private func connected() throws -> (AgentMCPStdioTransport, AgentPipeChannel) {
        let a = Pipe(), b = Pipe()
        let server = try AgentMCPStdioTransport(input: a.fileHandleForReading.fileDescriptor, output: b.fileHandleForWriting.fileDescriptor)
        let client = try AgentPipeChannel(input: b.fileHandleForReading.fileDescriptor, output: a.fileHandleForWriting.fileDescriptor)
        try a.fileHandleForReading.close(); try a.fileHandleForWriting.close()
        try b.fileHandleForReading.close(); try b.fileHandleForWriting.close()
        return (server, client)
    }
    private func errorCode(_ data: Data?) throws -> AgentJSONValue? {
        guard case .object(let root) = try JSONDecoder().decode(AgentJSONValue.self, from: #require(data)),
              case .object(let error) = root["error"] else { throw AgentErrorCode.invalidInput }
        return error["code"]
    }

    @Test func decimalRoundingIsRejectedBeforeSDKDispatchAndExactJSONPassesUnchanged() async throws {
        let (server, client) = try connected()
        try await server.connect()
        do {
            let rounded = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"draftly_drafts_list","arguments":{"parameters":{"limit":1.00000000000000001}}}}"#
            try await client.writeLine(Data(rounded.utf8))
            #expect(try errorCode(await client.readLine(timeout: 3)) == .integer(-32602))
            let exact = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"draftly_drafts_list","arguments":{"parametersJSON":"{\"limit\":1.00000000000000001}"}}}"#
            try await client.writeLine(Data(exact.utf8))
            var iterator = await server.receive().makeAsyncIterator()
            #expect(try await iterator.next() == Data(exact.utf8))
            await server.disconnect(); client.close()
        } catch { await server.disconnect(); client.close(); throw error }
    }

    @Test func inFlightRequestsAreBoundedAndDuplicatesCannotReplacePendingWork() async throws {
        let (server, client) = try connected()
        try await server.connect()
        do {
            for id in 1...17 {
                try await client.writeLine(Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"ping\"}".utf8))
            }
            #expect(try errorCode(await client.readLine(timeout: 3)) == .integer(-32000))
            try await client.writeLine(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}".utf8))
            #expect(try errorCode(await client.readLine(timeout: 3)) == .integer(-32600))
            await server.disconnect(); client.close()
        } catch { await server.disconnect(); client.close(); throw error }
    }

    @Test func batchesDoNotBypassTheRequestBudget() async throws {
        let (server, client) = try connected()
        try await server.connect()
        do {
            try await client.writeLine(Data("[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}]".utf8))
            #expect(try errorCode(await client.readLine(timeout: 3)) == .integer(-32600))
            await server.disconnect(); client.close()
        } catch { await server.disconnect(); client.close(); throw error }
    }

    @Test func pipeCloseAndBrokenOutputDoNotChangeTheProcessSignalPolicy() async throws {
        let (server, client) = try connected()
        await server.disconnect()
        await #expect(throws: (any Error).self) { try await client.writeLine(Data("neutral".utf8)) }
        #expect(try await client.readLine(timeout: 3) == nil)
        client.close()
    }

    @Test func oversizedUnterminatedLinesAreRejectedBeforeEOF() async throws {
        let a = Pipe(), b = Pipe()
        let reader = try AgentPipeChannel(input: a.fileHandleForReading.fileDescriptor, output: b.fileHandleForWriting.fileDescriptor)
        let writer = dup(a.fileHandleForWriting.fileDescriptor)
        #expect(writer >= 0 && fcntl(writer, F_SETNOSIGPIPE, 1) == 0)
        try a.fileHandleForReading.close(); try a.fileHandleForWriting.close()
        try b.fileHandleForReading.close(); try b.fileHandleForWriting.close()
        defer { reader.close(); Darwin.close(writer) }
        let job = Task.detached {
            let data = Data(repeating: 120, count: AgentRequest.maximumBytes + 1)
            return data.withUnsafeBytes { buffer -> Bool in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(writer, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    if count <= 0 { return false }; offset += count
                }
                return true
            }
        }
        let line = Task { try await reader.readLine(timeout: 3) }
        defer { line.cancel() }
        await #expect(throws: AgentErrorCode.invalidInput) { try await line.value }
        reader.close()
        #expect(await job.value)
    }
}
