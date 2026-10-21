import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Workspace presentation selection") @MainActor
struct WorkspacePresentationSelectionTests {
    private let customID = "DAAF7300-0000-4000-8000-000000000021"
    private let fileID = "DAAF7300-0000-4000-8000-000000000022"

    private var choices: [WorkspacePresentationSettings.Choice] {
        [
            .init(id: "Dark", title: "Dark", value: ["name": "Dark"]),
            .init(id: customID, title: "Dark", value: ["name": "Dark", "type": "custom", "uuid": customID]),
            .init(id: fileID, title: "Dark (File)", value: ["name": "Dark", "type": "file", "uuid": fileID])
        ]
    }

    @Test(arguments: [false, true])
    func builtInThemeSelectionUsesNameAndRetainsAnImportedUUIDAndUnknownFields(explicitType: Bool) throws {
        var imported: [String: Any] = ["name": "Dark", "uuid": customID, "future": ["enabled": true]]
        if explicitType { imported["type"] = "builtIn" }
        let before = NSDictionary(dictionary: imported)
        let resolved = try ThemeReferenceResolver.resolve(imported, themes: [])
        #expect(WorkspacePresentationSettings.selectedReferenceID(imported, isTheme: true, choices: choices) == "Dark")
        #expect(WorkspacePresentationSettings.selectedReferenceID(resolved, isTheme: true, choices: choices) == "Dark")
        #expect(resolved["uuid"] as? String == customID)
        #expect((resolved["future"] as? [String: Bool])?["enabled"] == true)
        #expect(before.isEqual(to: imported))
    }

    @Test(arguments: ["custom", "file"])
    func storedThemeTypesUseTheirOwnUUIDAndNameFallback(type: String) {
        let id = type == "custom" ? customID : fileID
        let identified = ["name": "Old name", "uuid": id, "type": type]
        #expect(WorkspacePresentationSettings.selectedReferenceID(identified, isTheme: true, choices: choices) == id)
        #expect(WorkspacePresentationSettings.selectedReferenceID(["name": "Dark", "type": type], isTheme: true, choices: choices) == id)
        let missing = ["name": "Dark", "uuid": "missing", "type": type]
        #expect(WorkspacePresentationSettings.selectedReferenceID(missing, isTheme: true, choices: choices) == "missing")
    }

    @Test func groupIdentityAndMissingReferenceRepresentationsStayUnchanged() {
        #expect(WorkspacePresentationSettings.selectedReferenceID(["name": "Old group", "uuid": customID], isTheme: false, choices: choices) == customID)
        #expect(WorkspacePresentationSettings.selectedReferenceID(["name": "Dark"], isTheme: false, choices: choices) == "Dark")
        #expect(WorkspacePresentationSettings.selectedReferenceID(nil, isTheme: true, choices: choices).isEmpty)
        #expect(WorkspacePresentationSettings.selectedReferenceID([:], isTheme: true, choices: choices) == "missing:reference")
        #expect(WorkspacePresentationSettings.selectedReferenceID(["name": "Missing", "type": "builtIn"], isTheme: true, choices: choices) == "missing:Missing")
    }
}
