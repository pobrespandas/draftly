import Foundation
import Testing
@testable import DraftlyCore

@Suite("Theme installURL scripting contract") @MainActor
struct ThemeInstallURLContractTests {
    @Test(arguments: [false, true])
    func customLinksPreserveDefinitionsAndResolveIdentityBeforeDetachedName(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let definition = EditorThemeDefinition(name: "Install café 🐼 &?%", foreground: "123456", background: "FEDCBA", heading: "ABCDEF", unknownFields: ["future": .object(["keep": .array([.bool(false), .string("\n\"&?%🦊")])])])
        try fixture.library.saveTheme(definition)
        let before = fixture.library.themes
        let action = makeAPIAction("""
        const t=Theme.find('custom','Install café 🐼 &?%');
        const url=t.installURL;
        check(typeof url==='string'&&url.startsWith('draftly://theme?'),'installation link');
        check(t.installURL===url,'stable link');
        check(Reflect.set(t,'installURL','wrong')===false&&t.installURL===url,'readonly');
        t.name='Detached rename';check(t.installURL===url,'identity before name');
        app.setClipboard(url);
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker), Comment(rawValue: fixture.runner.message ?? ""))
        let url = try #require(URL(string: fixture.host.clipboard))
        #expect(try ThemeInstallation(url: url) == .custom(definition))
        #expect(fixture.library.themes == before)
        #expect(fixture.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func builtinAndLegacyCustomReferencesHaveExplicitErrorsAndNoSideEffects(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let definition = EditorThemeDefinition(name: "Name only")
        try fixture.library.saveTheme(definition)
        let action = makeAPIAction("""
        function rejected(t,label){let failed=false;try{t.installURL;}catch(e){failed=true;}check(failed,label);}
        const legacy=new Theme('Name only','custom');
        check(legacy.installURL.includes('data='),'legacy name resolution');
        legacy.uuid='invalid';rejected(legacy,'invalid uuid');
        legacy.uuid='BBBF0026-0000-4000-8000-000000009999';rejected(legacy,'missing uuid no name fallback');
        rejected(new Theme('Missing','custom'),'missing custom');
        rejected(new Theme('Dark','file'),'unimplemented file');
        rejected(new Theme('Dark','other'),'invalid type');
        rejected(new Theme('Missing','builtIn'),'missing built-in');
        const builtin=Theme.find('builtIn','Dark');
        app.setClipboard(builtin.installURL);
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker), Comment(rawValue: fixture.runner.message ?? ""))
        let url = try #require(URL(string: fixture.host.clipboard))
        #expect(try ThemeInstallation(url: url) == .builtIn("Dark"))
        #expect(fixture.library.themes == [definition])
        #expect(fixture.editor.content == "Keep café 🐼")
    }
}
