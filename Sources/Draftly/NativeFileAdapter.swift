import AppKit
import DraftlyCore

@MainActor
struct NativeFileAdapter {
    var defaults: UserDefaults = .standard
    var testFileRoot: URL?
    static let operations: Set<String> = ["saveFile", "readFile", "writeFile", "fileExists"]

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "saveFile": return try saveFile(values)
        case "readFile", "writeFile", "fileExists":
            let root = try libraryFolder().resolvingSymlinksInPath().standardizedFileURL
            let path = values["path"] as? String ?? ""
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let target = try containedTarget(root.appendingPathComponent(relative), root: root,
                                             message: "The file path must stay inside the Draftly Library folder.")
            guard target != root else { throw DraftlyError.message("The file path must stay inside the Draftly Library folder.") }
            if operation == "fileExists" { return FileManager.default.fileExists(atPath: target.path) }
            if operation == "readFile" { return try String(contentsOf: target, encoding: .utf8) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8); return true
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func saveFile(_ values: [String: Any]) throws -> Bool {
        let text = values["text"] as? String ?? ""
        let name = (values["name"] as? String ?? "Draft.md").replacingOccurrences(of: "/", with: "-")
        let bookmarkName = values["bookmark"] as? String ?? ""
        let target: URL
        var scope: URL?
        defer { scope?.stopAccessingSecurityScopedResource() }
        if !bookmarkName.isEmpty {
            let key = "bookmark.\(bookmarkName)"
            var stale = false
            var root: URL?
            if let data = defaults.data(forKey: key) {
                root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            }
            if root == nil || stale {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                panel.message = "Choose the folder for \(bookmarkName)."
                guard panel.runModal() == .OK, let url = panel.url else { throw DraftlyError.message("File export cancelled.") }
                root = url
                defaults.set(try BookmarkPreferences.data(for: url), forKey: key)
            }
            guard let root else { throw DraftlyError.message("The destination folder is unavailable.") }
            _ = root.startAccessingSecurityScopedResource(); scope = root
            target = try exportDestination(root: root, folder: values["folder"] as? String ?? "", name: name)
        } else {
            let panel = NSSavePanel(); panel.nameFieldStringValue = name
            guard panel.runModal() == .OK, let url = panel.url else { throw DraftlyError.message("File export cancelled.") }
            target = url
        }
        return try writeExport(text: text, target: target, mode: values["mode"] as? String ?? "create", usesBookmark: !bookmarkName.isEmpty)
    }

    private func writeExport(text: String, target: URL, mode: String, usesBookmark: Bool) throws -> Bool {
        try validateExportMode(mode)
        if mode == "create", FileManager.default.fileExists(atPath: target.path), usesBookmark {
            throw DraftlyError.message("A file with this name already exists. Choose another draft title.")
        }
        var result = text
        if ["append", "prepend"].contains(mode), FileManager.default.fileExists(atPath: target.path) {
            let previous = try String(contentsOf: target, encoding: .utf8)
            result = mode == "append" ? previous + text : text + previous
        }
        try result.write(to: target, atomically: true, encoding: .utf8)
        return true
    }

    private func validateExportMode(_ mode: String) throws {
        guard ["create", "replace", "append", "prepend"].contains(mode) else {
            throw DraftlyError.message("Unsupported file write type: \(mode)")
        }
    }

    func performAsync(_ operation: String, values: [String: Any],
                      select: NativeFileSelector = { try await NativeFileSelectionRequest.select($0) }) async throws -> Any? {
        switch operation {
        case "saveFile": return try await saveFileAsync(values, select: select)
        case "bookmark": return try await bookmarkRootAsync(values["name"] as? String ?? "", select: select).path
        case "fileAPI": return try await fileAPIAsync(values, select: select)
        default: throw DraftlyError.message("The asynchronous file operation is unavailable.")
        }
    }

    func saveFileAsync(_ values: [String: Any],
                       select: NativeFileSelector = { try await NativeFileSelectionRequest.select($0) }) async throws -> Bool {
        try Task.checkCancellation()
        let mode = values["mode"] as? String ?? "create"
        try validateExportMode(mode)
        let name = (values["name"] as? String ?? "Draft.md").replacingOccurrences(of: "/", with: "-")
        let bookmark = values["bookmark"] as? String ?? ""
        let target: URL
        var scope: URL?
        defer { scope?.stopAccessingSecurityScopedResource() }
        if !bookmark.isEmpty {
            let root = try await bookmarkRootAsync(bookmark, select: select)
            try Task.checkCancellation()
            _ = root.startAccessingSecurityScopedResource(); scope = root
            target = try exportDestination(root: root, folder: values["folder"] as? String ?? "", name: name)
        } else {
            guard let selected = try await select(.save(name: name)) else { throw ActionExecutionInterruption.cancelled }
            try Task.checkCancellation()
            target = selected
        }
        try Task.checkCancellation()
        return try writeExport(text: values["text"] as? String ?? "", target: target,
                               mode: mode, usesBookmark: !bookmark.isEmpty)
    }

    func bookmarkRootAsync(_ name: String,
                           select: NativeFileSelector = { try await NativeFileSelectionRequest.select($0) }) async throws -> URL {
        try Task.checkCancellation()
        guard !name.isEmpty else { throw DraftlyError.message("The bookmark name is empty.") }
        let key = "bookmark.\(name)"
        var stale = false
        if let data = defaults.data(forKey: key),
           let root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale {
            return root
        }
        guard let root = try await select(.folder(name: name)) else { throw ActionExecutionInterruption.cancelled }
        try Task.checkCancellation()
        let data = try BookmarkPreferences.data(for: root)
        try Task.checkCancellation()
        defaults.set(data, forKey: key)
        return root
    }

    func fileAPIAsync(_ values: [String: Any],
                      select: NativeFileSelector = { try await NativeFileSelectionRequest.select($0) }) async throws -> Any {
        try Task.checkCancellation()
        if values["storage"] as? String == "bookmark" {
            let root = try await bookmarkRootAsync(values["bookmark"] as? String ?? "", select: select)
            try Task.checkCancellation()
            return try fileAPI(values, root: root)
        }
        return try fileAPI(values)
    }

    private func exportDestination(root: URL, folder path: String, name: String) throws -> URL {
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = canonical.appendingPathComponent(path).standardizedFileURL
        guard candidate.path == canonical.path || candidate.path.hasPrefix(canonical.path + "/") else {
            throw DraftlyError.message("The destination must stay inside the selected folder.")
        }
        let folder = try containedTarget(candidate, root: canonical, message: "The destination must stay inside the selected folder.")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try containedTarget(folder.appendingPathComponent(name), root: canonical,
                                   message: "The destination must stay inside the selected folder.")
    }

    func libraryFolder() throws -> URL {
        let root = testFileRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly/Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func bookmarkRoot(_ name: String) throws -> URL {
        guard !name.isEmpty else { throw DraftlyError.message("The bookmark name is empty.") }
        let key = "bookmark.\(name)"
        var stale = false
        if let data = defaults.data(forKey: key), let root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale { return root }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.message = "Choose the folder for \(name)."
        guard panel.runModal() == .OK, let root = panel.url else { throw DraftlyError.message("Folder selection cancelled.") }
        defaults.set(try BookmarkPreferences.data(for: root), forKey: key)
        return root
    }
    func fileAPI(_ values: [String: Any]) throws -> Any {
        let storage = values["storage"] as? String ?? "local", manager = FileManager.default
        let root: URL
        switch storage {
        case "bookmark": root = try bookmarkRoot(values["bookmark"] as? String ?? "")
        case "cloud":
            guard let cloud = manager.url(forUbiquityContainerIdentifier: nil) else { throw DraftlyError.message("iCloud Drive is unavailable. Sign in and enable iCloud for Draftly.") }
            root = cloud.appendingPathComponent("Documents")
        default: root = try libraryFolder()
        }
        return try fileAPI(values, root: root)
    }

    private func fileAPI(_ values: [String: Any], root: URL) throws -> Any {
        let manager = FileManager.default
        let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        func resolve(_ path: String) throws -> URL {
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            return try containedTarget(canonical.appendingPathComponent(relative), root: canonical,
                                       message: "The path must stay inside the selected file root.")
        }
        let target = try resolve(values["path"] as? String ?? "")
        switch values["operation"] as? String ?? "" {
        case "basePath": return root.path
        case "baseURL": return root.absoluteString
        case "readString": return try String(contentsOf: target, encoding: .utf8)
        case "writeString":
            guard let text = values["text"] as? String else {
                throw DraftlyError.message("File content must be a string.")
            }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8); return true
        case "exists": return manager.fileExists(atPath: target.path)
        case "isDirectory": var isDirectory: ObjCBool = false; return manager.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
        case "createDirectory":
            var directory = target
            if let name = values["name"] as? String {
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                    throw DraftlyError.message("The directory name must be a single path component.")
                }
                directory = try containedTarget(target.appendingPathComponent(name), root: canonical,
                                                message: "The path must stay inside the selected file root.")
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true); return true
        case "listContents":
            let parent = target == canonical ? "" : String(target.path.dropFirst(canonical.path.count))
            return try manager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
                .map { parent + "/" + $0.lastPathComponent }.sorted()
        case "copyItem", "moveItem":
            let destination = try resolve(values["destination"] as? String ?? "")
            let isMove = values["operation"] as? String == "moveItem"
            try transferItem(from: target, to: destination, root: canonical,
                             overwrite: values["overwrite"] as? Bool == true, move: isMove)
            return true
        case "getCreationDate", "getModificationDate":
            let key: FileAttributeKey = values["operation"] as? String == "getCreationDate" ? .creationDate : .modificationDate
            guard let date = try manager.attributesOfItem(atPath: target.path)[key] as? Date else { throw DraftlyError.message("The file date is unavailable.") }
            return APIValues.date(date)
        case "setCreationDate", "setModificationDate":
            guard let date = APIValues.parseDate(values["date"]) else { throw DraftlyError.message("The file date is invalid.") }
            try manager.setAttributes([values["operation"] as? String == "setCreationDate" ? .creationDate : .modificationDate: date], ofItemAtPath: target.path); return true
        case "getTags": return try target.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        case "setTags":
            guard let tags = values["tags"] as? [String] else {
                throw DraftlyError.message("File tags must be an array of strings.")
            }
            var url = target; var resource = URLResourceValues(); resource.tagNames = tags
            try url.setResourceValues(resource); return true
        default: throw DraftlyError.message("The file operation is invalid.")
        }
    }

    func transferItem(from source: URL, to destination: URL, root: URL, overwrite: Bool, move: Bool,
                      performTransfer: (URL, URL, Bool) throws -> Void = { source, destination, move in
                          if move { try FileManager.default.moveItem(at: source, to: destination) }
                          else { try FileManager.default.copyItem(at: source, to: destination) }
                      }) throws {
        let manager = FileManager.default
        guard source != root, destination != root, source != destination,
              !destination.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(destination.path + "/") else {
            throw DraftlyError.message("The source and destination must be separate paths inside the file root.")
        }
        guard manager.fileExists(atPath: source.path) else { throw DraftlyError.message("The source file does not exist.") }
        func transfer() throws { try performTransfer(source, destination, move) }
        guard overwrite, manager.fileExists(atPath: destination.path) else { try transfer(); return }
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".draftly-replaced-" + UUID().uuidString)
        try manager.moveItem(at: destination, to: backup)
        do { try transfer() }
        catch {
            let transferError = error
            do {
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.moveItem(at: backup, to: destination)
            } catch {
                throw DraftlyError.message("The transfer failed and the original destination could not be restored. Its backup is at \(backup.path).")
            }
            throw transferError
        }
        try manager.removeItem(at: backup)
    }

    private func containedTarget(_ candidate: URL, root: URL, message: String) throws -> URL {
        let manager = FileManager.default
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        var ancestor = candidate.standardizedFileURL
        var suffix: [String] = []
        while !manager.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
            if (try? manager.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                throw DraftlyError.message(message)
            }
            suffix.insert(ancestor.lastPathComponent, at: 0)
            ancestor.deleteLastPathComponent()
        }
        let target = suffix.reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.standardizedFileURL
        guard target == canonical || target.path.hasPrefix(canonical.path + "/") else { throw DraftlyError.message(message) }
        return target
    }

}
