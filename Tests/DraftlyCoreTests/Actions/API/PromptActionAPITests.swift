import Foundation
import Testing
@testable import DraftlyCore

@Suite("Prompt scripting API") @MainActor
struct PromptActionAPITests {
    @Test func selectPromptItemConstructorCreatesIndependentEmptyValues() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const a=new SelectPromptItem(),b=new SelectPromptItem();
        check(a instanceof SelectPromptItem && a!==b,'independent values');
        check(a.id===undefined && a.title===undefined && a.subtitle===undefined && a.symbolName===undefined,'initial fields');
        a.title='Changed';check(b.title===undefined,'no shared state');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func selectPromptItemFactoryPreservesArgumentsAndOptionalValues() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const a=SelectPromptItem.create('id','Café 🐼'),b=SelectPromptItem.create('other','Title','Details','doc');
        check(a instanceof SelectPromptItem && b instanceof SelectPromptItem && a!==b,'factory type');
        check(a.id==='id' && a.title==='Café 🐼','required fields');
        check(a.subtitle===undefined && a.symbolName===undefined,'optional fields omitted');
        check(b.subtitle==='Details' && b.symbolName==='doc','optional fields supplied');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(host.calls.isEmpty)
    }

    @Test func selectPromptItemIDEnforcesUniquenessWhenAdded() throws {
        let (_, _, _, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const a=new SelectPromptItem();a.id='🐼';a.title='First';
        const p=new SelectPrompt();check(p.addItem(a)===true,'writable ID');
        check(p.addItem(SelectPromptItem.create('🐼','Duplicate'))===false,'duplicate ID');
        check(p.addItem(SelectPromptItem.create('different','First'))===true,'same title allowed');
        check(p.items.length===2 && p.items[0].id==='🐼','invalid item did not change list');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func selectPromptItemTitleReachesSelectionWithoutChangingUnicode() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const item=new SelectPromptItem();item.id='one';item.title='Café 🐼 日本語';
        const p=new SelectPrompt();check(p.addItem(item),'add');check(p.show(),'selection');
        check(p.selectedItem.title==='Café 🐼 日本語','selected title');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["title"] as? String == "Café 🐼 日本語")
    }

    @Test func selectPromptItemSubtitleRemainsOptionalAndSeparate() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const item=SelectPromptItem.create('one','Title');check(item.subtitle===undefined,'omitted subtitle');
        item.subtitle='Details 🐼\nSecond line';const p=new SelectPrompt();p.addItem(item);check(p.show(),'selection');
        check(p.selectedItem.subtitle===item.subtitle && p.selectedItem.title==='Title','separate subtitle');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["subtitle"] as? String == "Details 🐼\nSecond line")
    }

    @Test func selectPromptItemSymbolNameReachesTheNativeHost() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        const item=SelectPromptItem.create('one','Title');check(item.symbolName===undefined,'omitted symbol');
        item.symbolName='doc.text';const p=new SelectPrompt();p.addItem(item);check(p.show(),'selection');
        check(p.selectedItem.symbolName==='doc.text','selected symbol');
        """#)), Comment(rawValue: runner.message ?? ""))
        let items = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(items.first?["symbolName"] as? String == "doc.text")
    }

    @Test func selectPromptDefaultsFactoryAndCancelContract() throws {
        let (library, editor, host, runner) = try makeAPIContext()
        host.selectedIndex = nil
        #expect(runner.run(makeAPIAction(#"""
        const p=SelectPrompt.create();check(p instanceof SelectPrompt,'factory');
        check(p.message==='' && p.selectedItem===undefined,'defaults');
        check(p.addItem()===false,'missing parameters');
        check(p.addItem('one','Title')===true,'optional arguments');
        check(p.items[0].subtitle===undefined && p.items[0].symbolName===undefined,'optional defaults');
        check(p.show()===false && p.selectedItem===null,'cancel result');
        const empty=new SelectPrompt();check(empty.show()===false && empty.selectedItem===null,'empty selection');
        """#)), Comment(rawValue: runner.message ?? ""))
        #expect(library.runs.first?.message.contains("unique string ID") == true)
        let noHost = ActionRunner(library: library, editor: editor)
        #expect(!noHost.run(makeAPIAction("const p=SelectPrompt.create();p.addItem('one','One');p.show();")))
        #expect(noHost.message?.contains("selectPrompt") == true)
    }

    @Test func selectPromptPreservesItemFieldsAndReturnsBooleanResults() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        let p=SelectPrompt.create();p.message='Choose';
        check(p.addItem('one','Café','Subtitle 🐼','tag')===true,'boolean success');
        check(p.addItem('one','Duplicate')===false,'duplicate');
        check(p.addItem(42,'Invalid')===false,'missing ID');
        check(p.items.length===1,'invalid items unchanged');
        check(p.show()===true,'show');
        check(p.selectedItem.id==='one' && p.selectedItem.subtitle==='Subtitle 🐼','result fields');
        check(p.selectedItem.symbolName==='tag','symbol');
        const item=SelectPromptItem.create('two','Title','Details','doc');check(item instanceof SelectPromptItem && item.id==='two' && item.title==='Title' && item.subtitle==='Details' && item.symbolName==='doc','item factory');
        check(new SelectPromptItem().id===undefined,'item defaults');
        """#)), Comment(rawValue: runner.message ?? ""))
        let fields = try #require(host.calls.first { $0.0 == "selectPrompt" }?.1["items"] as? [[String: Any]])
        #expect(fields.count == 1)
        #expect(host.calls.first { $0.0 == "selectPrompt" }?.1["message"] as? String == "Choose")
        #expect(fields[0]["subtitle"] as? String == "Subtitle 🐼")
        host.selectedIndex = nil
        #expect(runner.run(makeAPIAction("let p=new SelectPrompt();p.addItem('a','A');p.selectedItem={id:'old'};check(p.show()===false && p.selectedItem===null,'cancel clears old selection');")))
        host.selectedIndex = 99
        #expect(runner.run(makeAPIAction("let p=new SelectPrompt();p.addItem('a','A');check(p.show()===false && p.selectedItem===null,'invalid response');")))
    }

    @Test func promptValuesRetainNativeTypesAndRequireLoadsHelpers() throws {
        let (_, _, host, runner) = try makeAPIContext()
        #expect(runner.run(makeAPIAction(#"""
        let p = Prompt.create(); p.addDatePicker('date','Date',new Date('2020-01-02T03:04:05Z'));
        p.addNumberField('count','Count',2,true); p.addSwitch('flag','Flag',true); p.addSelect('tags','Tags',['a','b'],['a','b'],true); p.addButton('Use',42);
        check(p.show() && p.buttonPressed === 42, 'prompt button value');
        check(p.fieldValues.date instanceof Date && p.fieldValues.count === 2 && p.fieldValues.flag === true && p.fieldValues.tags.length === 2, 'prompt types');
        require('helpers'); app.setClipboard(loadedHelper('loaded'));
        """#)), Comment(rawValue: runner.message ?? "")); #expect(host.clipboard == "LOADED")
    }
}
