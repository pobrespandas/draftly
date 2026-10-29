import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Native action API") @MainActor
struct NativeActionAPITests {
    @Test(arguments: [false, true]) func listContentsReturnsUsablePathsAndRecoversFromMissingDirectory(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "List files", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (!fm.writeString('/folder/Café 🐼.txt','Unicode') || !fm.createDirectory('child','/folder')) throw Error('setup');
        if (fm.listContents('/missing')!==undefined || typeof fm.lastError!=='string') throw Error('missing');
        const paths=fm.listContents('/folder');
        if (!Array.isArray(paths) || paths.length!==2 || fm.lastError!==undefined) throw Error('listing');
        if (!paths.some(p=>p.normalize('NFC')==='/folder/Café 🐼.txt') || !paths.includes('/folder/child')) throw Error('paths '+JSON.stringify(paths));
        if (fm.readString(paths.find(p=>p.endsWith('.txt')))!=='Unicode') throw Error('reusable path');
        if (!fm.isDirectory(paths.find(p=>p.endsWith('/child')))) throw Error('directory');
        if (!fm.listContents('/').includes('/folder')) throw Error('root listing');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(arguments: [false, true]) func writeStringRejectsInvalidContentWithoutReplacingFile(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "Text files", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (!fm.writeString('/note','Café 🐼')) throw Error('setup');
        for (const value of [undefined,null,42,{}]) {
            if (fm.writeString('/note',value)!==false || typeof fm.lastError!=='string') throw Error('invalid accepted');
            if (fm.readString('/note')!=='Café 🐼') throw Error('file changed');
        }
        if (!fm.writeString('/note','') || fm.readString('/note')!=='') throw Error('empty text');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(arguments: [false, true]) func invalidFileTagsDoNotEraseExistingTags(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "File tags", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (!fm.writeString('/note.txt','Neutral') || !fm.setTags('/note.txt',['Café'])) throw Error('setup');
        for (const tags of [undefined, ['valid',42]]) {
            if (fm.setTags('/note.txt',tags)!==false || typeof fm.lastError!=='string') throw Error('invalid accepted');
            if (fm.getTags('/note.txt').join(',')!=='Café') throw Error('tags changed');
        }
        if (!fm.setTags('/note.txt',[]) || fm.getTags('/note.txt').length!==0) throw Error('explicit clear');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(arguments: [false, true]) func readJSONReportsInvalidOrMissingFilesAndRecovers(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "JSON reading", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (fm.readJSON('/missing.json')!==undefined || typeof fm.lastError!=='string') throw Error('missing');
        if (!fm.writeString('/invalid.json','{bad')) throw Error('setup');
        if (fm.readJSON('/invalid.json')!==undefined || typeof fm.lastError!=='string') throw Error('invalid');
        if (!fm.writeJSON('/valid.json',[{text:'café 🐼'},null])) throw Error('valid write');
        const value=fm.readJSON('/valid.json');
        if (!Array.isArray(value) || value[0].text!=='café 🐼' || value[1]!==null || fm.lastError!==undefined) throw Error('recovery');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(arguments: [false, true]) func writeJSONRejectsUnserializableValuesWithoutChangingFile(worker: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let editor = EditorSession(); editor.load(try library.createNote(content: "Neutral"), focusEditor: false)
        let host = NativeActionHost(); host.testFileRoot = root
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = DraftAction(name: "JSON files", steps: [ActionStep("script", ["script": """
        const fm=FileManager.createLocal();
        if (!fm.writeJSON('/value.json',{text:'café 🐼'})) throw Error('initial write');
        const before=fm.readString('/value.json');
        let cyclic={}; cyclic.self=cyclic;
        for (const value of [undefined, cyclic]) {
            if (fm.writeJSON('/value.json',value)!==false || typeof fm.lastError!=='string') throw Error('invalid value');
            if (fm.readString('/value.json')!==before) throw Error('original changed');
        }
        if (!fm.writeJSON('/value.json',{text:'recovered'}) || fm.lastError!==undefined) throw Error('recovery');
        if (fm.readJSON('/value.json').text!=='recovered') throw Error('read');
        """])])
        if worker { #expect(await runner.runAsync(action).result.succeeded, Comment(rawValue: runner.message ?? "")) }
        else { #expect(runner.run(action), Comment(rawValue: runner.message ?? "")) }
    }
    @Test(.enabled(if: getuid() != 0)) func unreadableSourceRestoresExistingCopyDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try "Source".write(to: source, atomically: true, encoding: .utf8)
        try "Original 🐼".write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: source.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
            try? FileManager.default.removeItem(at: root)
        }
        #expect(throws: (any Error).self) { try Data(contentsOf: source) }
        let adapter = NativeFileAdapter(testFileRoot: root)
        #expect(throws: (any Error).self) {
            try adapter.fileAPI(["operation": "copyItem", "path": "source", "destination": "destination", "overwrite": true])
        }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "Original 🐼")
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) == Set(["source", "destination"]))
    }
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
