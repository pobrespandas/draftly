import CryptoKit
import Darwin
import DraftlyCore
import Foundation

@main struct LibraryBenchmark {
    struct Options {
        var notes = 10_000
        var samples = 5
        var storage = "sqlite"
    }

    @MainActor static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] {
                print("DraftlyLibraryBenchmark [--notes 10000] [--samples 5] [--storage sqlite|memory]")
                return
            }
            var options = Options()
            var index = 0
            while index < arguments.count {
                guard index + 1 < arguments.count else { throw DraftlyError.message("An option needs a value.") }
                let key = arguments[index], value = arguments[index + 1]
                switch key {
                case "--notes":
                    guard let count = Int(value), count > 0 else { throw DraftlyError.message("Use a positive note count.") }
                    options.notes = count
                case "--samples":
                    guard let count = Int(value), count > 0 else { throw DraftlyError.message("Use a positive sample count.") }
                    options.samples = count
                case "--storage":
                    guard ["sqlite", "memory"].contains(value) else { throw DraftlyError.message("Use sqlite or memory storage.") }
                    options.storage = value
                default: throw DraftlyError.message("Unknown option: \(key)")
                }
                index += 2
            }
            try measure(options)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    static func milliseconds(_ operation: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try operation()
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    static func identity(_ index: Int, prefix: String) -> UUID {
        UUID(uuidString: String(format: prefix + "-0000-4000-8000-%012d", index))!
    }

    static func summary(_ values: [Double]) -> [String: Double] {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return ["minimum": sorted[0], "median": median, "maximum": sorted[sorted.count - 1]]
    }

    @MainActor static func measure(_ options: Options) throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = (0..<options.notes).map { index in
            Note(id: identity(index, prefix: "BAAA0001"), content: "Note \(index)\nSearchable café 🐼 日本語",
                 tags: index % 2 == 0 ? ["even"] : [], createdAt: date, modifiedAt: date)
        }
        let revisions = notes.enumerated().map { index, note in
            var revision = Revision(noteID: note.id, content: note.content)
            revision.id = identity(index, prefix: "BAAA0002"); revision.date = date
            return revision
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let baseline = try encoder.encode(Backup(notes: notes, revisions: revisions, workspaces: [], actions: []))
        let actionID = identity(0, prefix: "BAAA0003")
        let action = DraftAction(name: "Benchmark neutral action", steps: [])
        var importedAction = action; importedAction.id = actionID
        let inputNoteID = identity(0, prefix: "BAAA0004")
        let noteFile = try JSONSerialization.data(withJSONObject: ["drafts": [
            ["uuid": inputNoteID.uuidString, "content": "Imported café 🐼", "tags": ["imported"],
             "flag": 7, "syntax": "TaskPaper", "modifiedAt": "2020-02-03T04:05:06Z"]]])
        let files = [LibraryFileImport.File(data: try encoder.encode(importedAction), fileExtension: "json"),
                     .init(data: noteFile, fileExtension: "json")]
        let document = String(String(repeating: "café 🐼\n", count: 20_000).prefix(100_000))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DraftlyLibraryBenchmark-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var samples: [[String: Double]] = []
        for index in 0..<options.samples {
            let directory = folder.appendingPathComponent(String(index))
            let library = try LibraryStore(inMemory: options.storage == "memory", directory: directory, seed: false)
            let setup = try milliseconds { try library.restore(baseline) }
            let batch = try milliseconds { try LibraryFileImport.apply(files, to: library) }
            let current = Dictionary(uniqueKeysWithValues: library.notes.map { ($0.id, $0) })
            let currentRevisions = Dictionary(uniqueKeysWithValues: library.revisions.map { ($0.id, $0) })
            guard notes.allSatisfy({ current[$0.id] == $0 }), revisions.allSatisfy({ currentRevisions[$0.id] == $0 }),
                  library.notes.count == notes.count + 1,
                  library.revisions.count == revisions.count + 1,
                  library.actions == [importedAction], current[inputNoteID]?.content == "Imported café 🐼",
                  current[inputNoteID]?.flag == 7, current[inputNoteID]?.syntax == "TaskPaper",
                  current[inputNoteID]?.tags == ["imported"],
                  current[inputNoteID]?.modifiedAt == ISO8601DateFormatter().date(from: "2020-02-03T04:05:06Z") else {
                throw DraftlyError.message("Import verification failed.")
            }
            var workspace = Workspace(name: "Benchmark"); workspace.folder = .all
            workspace.tags = ["even"]; workspace.query = "Searchable"
            var matches = 0
            let query = milliseconds { matches = workspace.filter(library.notes).count }
            guard matches == (options.notes + 1) / 2 else { throw DraftlyError.message("Query verification failed.") }
            var largeNote = try library.createNote(content: document)
            largeNote.content.replaceSubrange(largeNote.content.startIndex...largeNote.content.startIndex, with: "C")
            let save = try milliseconds { try library.saveNote(largeNote) }
            guard library.notes.first(where: { $0.id == largeNote.id })?.content == largeNote.content,
                  largeNote.content.count == 100_000 else { throw DraftlyError.message("Document verification failed.") }
            samples.append(["baselineRestore": setup, "multiFileImport": batch, "workspaceQuery": query, "documentSave": save])
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var hashes: [String: String] = [:]
        for name in ["LibraryFileImport.swift", "LibraryStore.swift"] {
            let data = try Data(contentsOf: root.appendingPathComponent("Sources/DraftlyCore/" + name))
            hashes[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        #if DEBUG
        let configuration = "debug"
        #else
        let configuration = "release"
        #endif
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let report: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()), "configuration": configuration,
            "os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": architecture,
            "processors": ProcessInfo.processInfo.processorCount, "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "storage": options.storage, "notes": options.notes, "baselineRevisions": revisions.count,
            "samples": options.samples, "warmUpSamples": 0, "baselineBytes": baseline.count,
            "fixtureSHA256": SHA256.hash(data: baseline).map { String(format: "%02x", $0) }.joined(),
            "sourceSHA256": hashes, "documentCharacters": document.count, "documentUTF16Units": document.utf16.count,
            "milliseconds": samples,
            "summaryMilliseconds": Dictionary(uniqueKeysWithValues: ["baselineRestore", "multiFileImport", "workspaceQuery", "documentSave"].map { key in
                (key, summary(samples.compactMap { $0[key] }))
            }),
            "verification": "Every sample retained the baseline notes, import identities and metadata, revision count, query result, and edited document.",
            "limits": "Fresh local stores. No iCloud, UI selection, scrolling, typing latency, Undo, RSS, or cold filesystem-cache measurement. Timings are observations, not acceptance thresholds."
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
