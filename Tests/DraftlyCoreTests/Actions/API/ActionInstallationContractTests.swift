import Foundation
import Testing
@testable import DraftlyCore

@Suite("Action installation contracts") @MainActor
struct ActionInstallationContractTests {
    @Test(arguments: [false, true])
    func installURLPreservesCompleteActionAndUnknownPayloadWithoutMutatingSource(worker: Bool) async throws {
        let (library, _, host, runner) = try makeAPIContext()
        var disabled = ActionStep("futureNeutralStep", ["unicode": "café 🐼\n\"&?%"])
        disabled.isEnabled = false
        var original = DraftAction(name: "Export café 🐼 & ?", steps: [disabled])
        original.group = "Other group"; original.symbol = "folder.fill"
        original.configuredValues = ["neutral": "café 🐼 &?%"]
        original.shortcut = "k"; original.shortcutModifiers = ["command", "option"]
        original.presentation.showInList = false; original.presentation.order = 8
        original.presentation.description = "Neutral description"
        original.unknownFields = ["future": .object(["keep": .array([.bool(false), .string("café 🐼")])])]
        original.rawPayload = #"{"futureOriginal":{"keep":true}}"#
        try library.saveActions([original])
        let source = makeAPIAction(#"""
        const found=Action.find('Export café 🐼 & ?'), url=found.installURL;
        check(typeof url==='string' && url.startsWith('draftly://action?data='),'installation URL');
        check(found.installURL===url,'stable link');
        check(Reflect.set(found,'installURL','wrong')===false && found.installURL===url,'readonly link');
        app.setClipboard(url);
        """#)
        #expect(await ActionTestExecution.succeeds(source, runner: runner, worker: worker), Comment(rawValue: runner.message ?? ""))
        let url = try #require(URL(string: host.clipboard))
        #expect(try ActionImporter.installationActions(url) == [original])
        #expect(library.actions == [original])
        let destination = try LibraryStore(inMemory: true, seed: false)
        try LibraryFileImport.apply(ActionImporter.installationData(url), fileExtension: "json", to: destination)
        #expect(destination.actions == [original])
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(destination.backupData())
        #expect(restored.actions == [original])
    }

}
