import Foundation
import Testing
@testable import DraftlyCore

@Suite("File theme scripting contracts") @MainActor
struct FileThemeScriptContractTests {
    @Test(arguments: [false, true])
    func exactFileCatalogAndPortableLinkReadTheCurrentFileWithoutSavingIt(worker: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "Draftly.FileTheme.Script.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let url = directory.appendingPathComponent("neutral.json")
        var source = EditorThemeDefinition(name: "Same café 🐼", background: "123456", unknownFields: ["future": .object(["keep": .string("&?%\n🦊")])])
        try JSONEncoder().encode(source).write(to: url)
        let prepared = try ThemeFileAccess.prepare(url)
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: APIContractHost())
        try ThemeFileAccess.install(prepared, in: fixture.library, defaults: defaults)
        try fixture.library.saveTheme(EditorThemeDefinition(name: source.name))
        fixture.runner.readTheme = { try ThemeFileAccess.read($0, defaults: defaults) }
        source.background = "654321"; try JSONEncoder().encode(source).write(to: url)
        #expect(fixture.library.themes.map(\.type) == ["custom", "file"])
        let before = fixture.library.themes
        let action = makeAPIAction("""
        const file=Theme.find('file','Same café 🐼'),custom=Theme.find('custom','Same café 🐼');
        check(file instanceof Theme&&custom instanceof Theme,'typed values');
        check(file.type==='file'&&file.uuid!==custom.uuid,'distinct types and identities');
        check(Theme.getAll().some(t=>t.type==='file'&&t.uuid===file.uuid),'catalog');
        const portable=file.installURL;check(file.installURL===portable,'stable current snapshot');
        const wrong=new Theme(file.name,'custom');wrong.uuid=file.uuid;
        let rejected=false;try{wrong.installURL;}catch(e){rejected=true;}check(rejected,'no cross-type UUID fallback');
        app.setClipboard(portable);
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker), Comment(rawValue: fixture.runner.message ?? ""))
        let link = try #require(URL(string: fixture.host.clipboard))
        var expected = source; expected.id = prepared.definition.id
        #expect(try ThemeInstallation(url: link) == .custom(expected))
        let text = fixture.host.clipboard
        #expect(!text.contains("theme.file.") && !text.contains("bookmark") && !text.contains(directory.path))
        #expect(fixture.library.themes == before && fixture.editor.content == "Keep original 🐼")
    }

    @Test(arguments: [false, true])
    func inaccessibleFileStopsTheActionAndDoesNotApplySuccessEffects(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep original 🐼", host: APIContractHost())
        let domain = "Draftly.FileTheme.Missing.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let file = EditorThemeDefinition(name: "Missing bookmark", type: "file")
        try fixture.library.saveTheme(file)
        fixture.runner.readTheme = { try ThemeFileAccess.read($0, defaults: defaults) }
        var action = makeAPIAction("Theme.find('file','Missing bookmark').installURL;editor.setText('Must not run');")
        action.afterSuccess = "archive"
        let succeeded = await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker)
        #expect(!succeeded)
        #expect(fixture.runner.message?.contains("Reselect the file") == true)
        #expect(fixture.editor.content == "Keep original 🐼")
        #expect(fixture.library.notes.first?.isArchived == false && fixture.library.themes == [file])
    }
}
