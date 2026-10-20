import Foundation
import UniformTypeIdentifiers
import Testing
@testable import Draftly

@Suite("Theme import file types")
struct ThemeImportFileTypeTests {
    @Test(arguments: ["draftsTheme", "json", "txt"])
    func panelTypesMatchTheActualFilesystemType(_ suffix: String) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{}".utf8).write(to: url)
        let actual = try #require(url.resourceValues(forKeys: [.contentTypeKey]).contentType)
        let enabled = ThemeImportFileTypes.allowed.contains { actual.conforms(to: $0) }
        #expect(enabled == (suffix != "txt"))
    }
}
