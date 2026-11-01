import Foundation
import Testing
@testable import DraftlyCore

@Suite("Public theme catalog")
struct PublicThemeCatalogTests {
    @Test func everyDownloadUsesTheDraftlyThemeImporter() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = repository.appendingPathComponent("website/public/themes")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "draftsTheme" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        #expect(files.count == 6)
        var names: Set<String> = []
        for file in files {
            let theme = try DraftsThemeImport.decode(data: Data(contentsOf: file))
            #expect(names.insert(theme.name).inserted)
            #expect(theme.unknownFields["draftsSource"] != nil)
        }
    }
}
