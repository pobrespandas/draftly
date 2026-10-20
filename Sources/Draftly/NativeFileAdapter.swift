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
            let root = try libraryFolder()
            let path = values["path"] as? String ?? ""
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let target = root.appendingPathComponent(relative).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw DraftlyError.message("The file path must stay inside the Draftly Library folder.") }
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
            let folder = root.appendingPathComponent(values["folder"] as? String ?? "").standardizedFileURL
            guard folder == root || folder.path.hasPrefix(root.path + "/") else { throw DraftlyError.message("The destination must stay inside the selected folder.") }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            target = folder.appendingPathComponent(name)
        } else {
            let panel = NSSavePanel(); panel.nameFieldStringValue = name
            guard panel.runModal() == .OK, let url = panel.url else { throw DraftlyError.message("File export cancelled.") }
            target = url
        }
        defer { scope?.stopAccessingSecurityScopedResource() }
        let mode = values["mode"] as? String ?? "create"
        guard ["create", "replace", "append", "prepend"].contains(mode) else { throw DraftlyError.message("Unsupported file write type: \(mode)") }
        if mode == "create", FileManager.default.fileExists(atPath: target.path), !bookmarkName.isEmpty {
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
        let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        func resolve(_ path: String) throws -> URL {
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            var ancestor = canonical.appendingPathComponent(relative).standardizedFileURL
            var suffix: [String] = []
            while !manager.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
                suffix.insert(ancestor.lastPathComponent, at: 0)
                ancestor.deleteLastPathComponent()
            }
            let url = suffix.reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.standardizedFileURL
            guard url == canonical || url.path.hasPrefix(canonical.path + "/") else { throw DraftlyError.message("The path must stay inside the selected file root.") }
            return url
        }
        let target = try resolve(values["path"] as? String ?? "")
        switch values["operation"] as? String ?? "" {
        case "basePath": return root.path
        case "baseURL": return root.absoluteString
        case "readString": return try String(contentsOf: target, encoding: .utf8)
        case "writeString":
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (values["text"] as? String ?? "").write(to: target, atomically: true, encoding: .utf8); return true
        case "exists": return manager.fileExists(atPath: target.path)
        case "isDirectory": var isDirectory: ObjCBool = false; return manager.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
        case "createDirectory": try manager.createDirectory(at: target, withIntermediateDirectories: true); return true
        case "listContents": return try manager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).map { $0.path.replacingOccurrences(of: canonical.path, with: "", options: .anchored) }.sorted()
        case "copyItem": try manager.copyItem(at: target, to: resolve(values["destination"] as? String ?? "")); return true
        case "moveItem": try manager.moveItem(at: target, to: resolve(values["destination"] as? String ?? "")); return true
        case "getCreationDate", "getModificationDate":
            let key: FileAttributeKey = values["operation"] as? String == "getCreationDate" ? .creationDate : .modificationDate
            guard let date = try manager.attributesOfItem(atPath: target.path)[key] as? Date else { throw DraftlyError.message("The file date is unavailable.") }
            return APIValues.date(date)
        case "setCreationDate", "setModificationDate":
            guard let date = APIValues.parseDate(values["date"]) else { throw DraftlyError.message("The file date is invalid.") }
            try manager.setAttributes([values["operation"] as? String == "setCreationDate" ? .creationDate : .modificationDate: date], ofItemAtPath: target.path); return true
        case "getTags": return try target.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        case "setTags": var url = target; var resource = URLResourceValues(); resource.tagNames = values["tags"] as? [String] ?? []; try url.setResourceValues(resource); return true
        default: throw DraftlyError.message("The file operation is invalid.")
        }
    }

}
