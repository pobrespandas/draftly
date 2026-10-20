import Foundation
import CryptoKit
import Testing
@testable import DraftlyCore

@Suite("Frozen Drafts theme reference")
struct DraftsThemeReferenceTests {
    @Test func officialLightSampleMatchesTheArchivedFormatAndRetainsAllScopes() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/research/theme-format-reference/2026-10-20")
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
        let sample = try #require(manifest["sample"] as? [String: String])
        let filename = try #require(sample["file"])
        let data = try Data(contentsOf: folder.appendingPathComponent(filename))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hash == sample["sha256"])
        let theme = try DraftsThemeImport.decode(data: data)
        #expect(theme.name == "Light" && !theme.isDark)
        #expect(theme.foreground == "000000")
        #expect(theme.background == "FFFFFF")
        #expect(theme.heading == "600100")
        let source = try JSONDecoder().decode(ThemeJSONValue.self, from: data)
        #expect(theme.unknownFields["draftsSource"] == source)
    }
}
