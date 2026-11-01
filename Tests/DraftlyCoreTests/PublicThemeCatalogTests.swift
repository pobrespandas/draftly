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
        let catalog = try String(contentsOf: repository.appendingPathComponent("website/public/themes.html"), encoding: .utf8)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "draftsTheme" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let expectedNames: Set<String> = [
            "Catppuccin Latte", "Catppuccin Mocha", "Dracula", "Flexoki Dark", "Flexoki Light",
            "Gruvbox Dark", "Gruvbox Light", "Nord", "Rosé Pine", "Rosé Pine Dawn",
            "Rosé Pine Moon", "Solarized Dark", "Solarized Light", "Tokyo Night",
        ]
        #expect(files.count == expectedNames.count)
        var names: Set<String> = []
        for file in files {
            let theme = try DraftsThemeImport.decode(data: Data(contentsOf: file))
            #expect(names.insert(theme.name).inserted)
            #expect(theme.unknownFields["draftsSource"] != nil)
            #expect(catalog.contains("themes/\(file.lastPathComponent)"))
        }
        #expect(names == expectedNames)
    }
}
