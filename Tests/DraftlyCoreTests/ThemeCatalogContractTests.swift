import Foundation
import Testing
@testable import DraftlyCore

@Suite("Theme catalog scripting contracts") @MainActor
struct ThemeCatalogContractTests {
    @Test(arguments: [false, true])
    func headlessCatalogFindsStoredThemesByExactNameAndType(worker: Bool) async throws {
        let fixture = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let theme = EditorThemeDefinition(name: "Tema café 🐼")
        let sameNameAsBuiltIn = EditorThemeDefinition(name: "Dark", isDark: true)
        try fixture.library.saveThemes([theme, sameNameAsBuiltIn])
        let original = fixture.library.themes
        let action = makeAPIAction("""
        const themes=Theme.getAll();
        check(Array.isArray(themes)&&themes.length===5,'typed theme array');
        check(themes.every(t=>t instanceof Theme),'typed theme entries');
        const custom=Theme.find('custom','Tema café 🐼');
        check(custom instanceof Theme&&custom.name==='Tema café 🐼'&&custom.type==='custom','custom lookup');
        check(custom.uuid==='\(theme.id.uuidString)','custom identity');
        check(Theme.find('builtIn','Dark').type==='builtIn','built-in lookup');
        check(Theme.find('custom','Dark').uuid==='\(sameNameAsBuiltIn.id.uuidString)','same name different type');
        for(const name of ['missing','Tema','tema café 🐼','Tema café 🐼 ',' Tema café 🐼']){
            check(Theme.find('custom',name)===undefined,'exact names');
        }
        check(Theme.find('file','Tema café 🐼')===undefined,'wrong type');
        check(Theme.find('unknown','Tema café 🐼')===undefined,'unknown type');
        custom.name='Changed local name';custom.type='file';
        check(custom.name==='Changed local name'&&custom.type==='file','writable fields');
        check(Theme.find('custom','Tema café 🐼').name==='Tema café 🐼','catalog detached values');
        themes.length=0;
        check(Theme.getAll().length===5,'independent array');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.library.themes == original)
        #expect(fixture.editor.content == "Keep café 🐼")
        #expect(fixture.host.calls.isEmpty)
    }

    @Test(arguments: [false, true])
    func constructorsAndEmptyLibrariesDoNotShareCustomCatalogEntries(worker: Bool) async throws {
        let other = try LibraryStore(inMemory: true, seed: false)
        try other.saveTheme(EditorThemeDefinition(name: "Only another library 🐼"))
        let fixture = try ScriptTestFixture(content: "Keep café 🐼", host: APIContractHost())
        let action = makeAPIAction("""
        const first=new Theme(),second=new Theme();
        check(first instanceof Theme&&second instanceof Theme&&first!==second,'constructor identity');
        first.name='Local name café 🐼';first.type='custom';
        check(first.name==='Local name café 🐼'&&first.type==='custom','writable constructor fields');
        check(typeof second.name==='string'&&typeof second.type==='string','constructor field types');
        check(Theme.find('custom','Only another library 🐼')===undefined,'library isolation');
        check(Theme.getAll().every(t=>t.type==='builtIn'),'empty library catalog');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: fixture.runner, worker: worker),
                Comment(rawValue: fixture.runner.message ?? ""))
        #expect(fixture.library.themes.isEmpty)
        #expect(other.themes.map(\.name) == ["Only another library 🐼"])
        #expect(fixture.host.calls.isEmpty)
    }
}
