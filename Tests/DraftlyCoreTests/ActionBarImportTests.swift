import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported action bar options") @MainActor
struct ActionBarImportTests {
    @Test func originalActionsMapTheirExplicitBarOptions() throws {
        for (id, label, icon) in [("1VL", "Template", true), ("1Ga", "", true),
                                  ("1Bg", "", true), ("1qn", "", false), ("1DM", "", false)] {
            let url = try #require(Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Fixtures"))
            let action = try #require(ActionImporter.decode(Data(contentsOf: url)).first)
            let colors = ["1VL": "blue", "1Ga": "green", "1Bg": "orange", "1qn": "green", "1DM": "none"]
            #expect(action.presentation.tintColor == colors[id])
            #expect(action.presentation.barLabel == label, Comment(rawValue: id))
            #expect(action.presentation.barUsesIcon == icon, Comment(rawValue: id))
        }
    }

    @Test func omittedOptionsStayAbsentInOldNativeAndForeignFormats() throws {
        let original = ActionPresentation()
        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["barLabel"] == nil && object["barUsesIcon"] == nil)
        let decoded = try JSONDecoder().decode(ActionPresentation.self, from: data)
        #expect(decoded.barLabel == nil && decoded.barUsesIcon == nil && decoded.tintColor == nil)
        let foreign = try #require(ActionImporter.decode(Data(#"{"name":"Old foreign","steps":[]}"#.utf8)).first)
        #expect(foreign.presentation.barLabel == nil && foreign.presentation.barUsesIcon == nil)
    }

    @Test func explicitBarOptionsAndRawPayloadSurviveExportAndBackup() throws {
        for label in ["", "Capturar café 🐼"] {
            for icon in [false, true] {
                let source = try JSONSerialization.data(withJSONObject: ["name": "Neutral bar action", "steps": [],
                    "shortName": label, "keyUseIcon": icon, "tintColor": "future-color", "futureBarOption": ["keep": "🐼"]] as [String: Any])
                let imported = try #require(ActionImporter.decode(source).first)
                let reimported = try #require(ActionImporter.decode(JSONEncoder().encode(imported)).first)
                #expect(reimported.presentation.barLabel == label && reimported.presentation.barUsesIcon == icon)
                #expect(reimported.presentation.tintColor == "future-color")
                #expect(reimported.rawPayload == imported.rawPayload)
                let library = try LibraryStore(inMemory: true, seed: false)
                try library.saveAction(reimported)
                let recovered = try LibraryStore(inMemory: true, seed: false)
                try recovered.restore(library.backupData())
                let restored = try #require(recovered.actions.first { $0.id == imported.id })
                #expect(restored.presentation.barLabel == label && restored.presentation.barUsesIcon == icon)
                #expect(restored.presentation.tintColor == "future-color")
                #expect(restored.rawPayload == imported.rawPayload)
                let raw = try JSONSerialization.jsonObject(with: Data(try #require(restored.rawPayload).utf8)) as? NSDictionary
                #expect(raw == (try JSONSerialization.jsonObject(with: source) as? NSDictionary))
            }
        }
    }
}
