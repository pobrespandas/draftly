import Foundation
import Testing
@testable import DraftlyCore

@Suite("Imported action payload recovery") @MainActor
struct ImportedActionPreservationTests {
    @Test func disabledUnknownPayloadSurvivesExportBackupAndRestore() async throws {
        let source = Data(#"{"name":"Future disabled","unknown":{"nullable":null,"unicode":"café 🐼","values":[1,true]},"steps":[{"type":"futureStep","isEnabled":false,"data":{"nested":{"keep":["x",null]},"futureOption":true}},{"type":"script","data":{"script":"context.addSuccessParameter('retained','yes');"}}]}"#.utf8)
        let action = try #require(ActionImporter.decode(source).first)
        let exported = try JSONEncoder().encode(action)
        let reimported = try #require(ActionImporter.decode(exported).first)
        #expect(reimported.rawPayload == action.rawPayload)
        #expect(reimported.steps == action.steps)
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveAction(reimported)
        let recovered = try LibraryStore(inMemory: true, seed: false)
        try recovered.restore(library.backupData())
        let restored = try #require(recovered.actions.first { $0.id == action.id })
        #expect(restored.rawPayload == action.rawPayload && restored.steps == action.steps)
        let originalJSON = try JSONSerialization.jsonObject(with: source) as? NSDictionary
        let recoveredJSON = try JSONSerialization.jsonObject(with: Data(try #require(restored.rawPayload).utf8)) as? NSDictionary
        #expect(recoveredJSON == originalJSON)
        let editor = EditorSession(); editor.load(try recovered.createNote(content: "Keep"))
        let report = await ActionRunner(library: recovered, editor: editor).runAsync(restored)
        #expect(report.reason == .success && report.successParameters["retained"] == "yes")
        #expect(editor.content == "Keep")
    }
}
