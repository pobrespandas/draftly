import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Native action API") @MainActor
struct NativeActionAPITests {
    @Test(arguments: [false, true]) func failedTransferRestoresDestinationAndRemovesPartialOutput(move: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try "Source".write(to: source, atomically: true, encoding: .utf8)
        try "Original 🐼".write(to: destination, atomically: true, encoding: .utf8)
        enum FixtureFailure: Error { case interrupted }
        #expect(throws: FixtureFailure.self) {
            try NativeFileAdapter().transferItem(from: source, to: destination, root: root, overwrite: true, move: move) { _, target, _ in
                try "Partial".write(to: target, atomically: true, encoding: .utf8)
                throw FixtureFailure.interrupted
            }
        }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "Original 🐼")
        #expect(try String(contentsOf: source, encoding: .utf8) == "Source")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) == Set(["source", "destination"]))
    }
    @Test(arguments: [false, true]) func scriptsCopyAndMoveWithExplicitOverwrite(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "File operations", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (!fm.writeString('/source','Source 🐼') || !fm.writeString('/target','Keep')) throw Error('setup');
        if (fm.copyItem('/source','/target') || fm.readString('/target') !== 'Keep') throw Error('copy collision');
        if (!fm.copyItem('/source','/target',true) || fm.readString('/target') !== 'Source 🐼') throw Error('copy replace');
        if (fm.moveItem('/missing','/target',true) || fm.readString('/target') !== 'Source 🐼') throw Error('missing source');
        if (!fm.writeString('/source','Moved') || !fm.moveItem('/source','/target',true)) throw Error('move replace');
        if (fm.exists('/source') || fm.readString('/target') !== 'Moved') throw Error('move result');
        if (fm.copyItem('/target','/target',true) || fm.readString('/target') !== 'Moved') throw Error('same path');
        if (!fm.writeString('/sourceDir/a','New') || !fm.writeString('/targetDir/b','Old')) throw Error('directory setup');
        if (!fm.copyItem('/sourceDir','/targetDir',true)) throw Error('directory replace');
        if (fm.readString('/targetDir/a') !== 'New' || fm.exists('/targetDir/b')) throw Error('directory result');
        if (!fm.writeString('/moveDir/new','Moved folder') || !fm.moveItem('/moveDir','/targetDir',true)) throw Error('directory move');
        if (fm.exists('/moveDir') || fm.readString('/targetDir/new') !== 'Moved folder' || fm.exists('/targetDir/a')) throw Error('directory move result');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
        #expect(try String(contentsOf: root.appendingPathComponent("target"), encoding: .utf8) == "Moved")
    }
    @Test(arguments: [false, true]) func scriptCreatesNamedDirectoryInIsolatedRoot(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession()
        editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "Directory QA", steps: [ActionStep("script", ["script": """
        const fm=FileManager.create(true);
        if (!fm.createDirectory('Café 🐼','/parent')) throw new Error(fm.lastError);
        if (!fm.isDirectory('/parent/Café 🐼')) throw new Error('Directory missing');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded) }
        else { #expect(runner.run(action)) }
        var directory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("parent/Café 🐼").path, isDirectory: &directory))
        #expect(directory.boolValue)
    }
    @Test func namedDirectoryIsCreatedInsideItsParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = NativeFileAdapter(testFileRoot: root)
        #expect(try adapter.fileAPI(["operation": "createDirectory", "path": "/parent", "name": "Café 🐼"]) as? Bool == true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("parent/Café 🐼").path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(throws: (any Error).self) {
            try adapter.fileAPI(["operation": "createDirectory", "path": "/parent", "name": "../../outside"])
        }
    }
    @Test func legacyFileOperationsRejectSymbolicLinkEscapes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("Library")
        let outside = folder.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let external = outside.appendingPathComponent("keep.txt")
        try "Original".write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let adapter = NativeFileAdapter(testFileRoot: root)
        for operation in ["readFile", "writeFile", "fileExists"] {
            #expect(throws: (any Error).self) {
                try adapter.perform(operation, values: ["path": "escape/keep.txt", "text": "Blocked"])
            }
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"), withDestinationURL: outside.appendingPathComponent("new"))
        #expect(throws: (any Error).self) {
            try adapter.perform("writeFile", values: ["path": "dangling/note.txt", "text": "Blocked"])
        }
        #expect(throws: (any Error).self) {
            try adapter.perform("fileExists", values: ["path": "dangling/note.txt"])
        }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("new/note.txt").path))
        #expect(try String(contentsOf: external, encoding: .utf8) == "Original")
        _ = try adapter.perform("writeFile", values: ["path": "nested/note.txt", "text": "café 🐼"])
        #expect(try adapter.perform("readFile", values: ["path": "nested/note.txt"]) as? String == "café 🐼")
    }
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
