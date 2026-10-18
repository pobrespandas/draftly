import Foundation
import Testing
@testable import Draftly

@Suite("Native action API") @MainActor
struct NativeActionAPITests {
    @Test func fileOperationsStayInsideTheirRoot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let host = NativeActionHost(); host.testFileRoot = root
        _ = try host.fileAPI(["operation": "writeString", "path": "nested/note.txt", "text": "café 🐼"])
        #expect(try host.fileAPI(["operation": "readString", "path": "nested/note.txt"]) as? String == "café 🐼")
        _ = try host.fileAPI(["operation": "copyItem", "path": "nested/note.txt", "destination": "copy.txt"])
        #expect(try host.fileAPI(["operation": "exists", "path": "copy.txt"]) as? Bool == true)
        #expect(throws: (any Error).self) { try host.fileAPI(["operation": "writeString", "path": "../outside.txt", "text": "blocked"]) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: folder)
        #expect(throws: (any Error).self) { try host.fileAPI(["operation": "writeString", "path": "escape/outside.txt", "text": "blocked"]) }
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("outside.txt").path))
    }

    @Test func shellArgumentsRemainLiteralAndReturnBothStreams() throws {
        let host = NativeActionHost()
        let argument = "$(echo expanded) `echo expanded` café"
        let result = try host.executeShell(["source": "printf '%s' \"$1\"\nprintf 'diagnostic' >&2\nexit 7", "arguments": [argument]])
        #expect(result["stdout"] as? String == argument)
        #expect(result["stderr"] as? String == "diagnostic")
        #expect(result["status"] as? Int == 7)
    }
}
