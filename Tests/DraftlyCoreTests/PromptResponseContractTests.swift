import Foundation
import Testing
@testable import DraftlyCore

@MainActor private final class PromptResponseHost: ActionHost {
    var responses: [Any?]
    var prompts: [[String: Any]] = []
    var clipboard = ""

    init(responses: [Any?]) { self.responses = responses }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "clipboard" { clipboard = values["text"] as? String ?? ""; return true }
        guard operation == "prompt", !responses.isEmpty else {
            throw DraftlyError.message("Unexpected prompt contract host call: \(operation)")
        }
        prompts.append(values)
        return responses.removeFirst()
    }
}

@Suite("Prompt response contracts") @MainActor
struct PromptResponseContractTests {
    private func setup(_ responses: [Any?]) throws -> (LibraryStore, PromptResponseHost, ActionRunner) {
        let fixture = try ScriptTestFixture(content: "Neutral prompt source 🐼", host: PromptResponseHost(responses: responses))
        return (fixture.library, fixture.host, fixture.runner)
    }

    private func action(_ script: String) -> DraftAction {
        ScriptTestAction.make(script, name: "Prompt response contract", helpers: "function options(){return {key:'wrong',label:'Wrong',value:'Wrong value',kind:'switch',futureOption:{version:7}};}\n")
    }

    private func field(_ host: PromptResponseHost, named key: String) throws -> [String: Any] {
        let fields = try #require(host.prompts.last?["fields"] as? [[String: Any]])
        let value = try #require(fields.first { $0["key"] as? String == key })
        #expect((value["futureOption"] as? [String: Int])?["version"] == 7)
        return value
    }

    @Test func showAcceptsZeroIndexAndPreservesTypedAndUnknownResultValues() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": [
            "date": "2020-01-02T03:04:05.000Z", "count": 2.5, "enabled": true,
            "unknown": ["values": ["Café", "🐼"]]
        ]]])
        defer { withExtendedLifetime(host) {} }
        #expect(runner.run(action(#"""
        const p=Prompt.create();p.addDatePicker('date','Date',new Date('2020-01-02T03:04:05Z'));
        p.addNumberField('count','Count',2.5,true);p.addSwitch('enabled','Enabled',true);
        const selected={id:'chosen',nested:{value:42}};p.addButton('Use',selected);
        check(p.show()===true,'success');check(p.buttonPressed===selected,'button value identity');
        check(p.fieldValues.date instanceof Date&&p.fieldValues.date.toISOString()==='2020-01-02T03:04:05.000Z','date type');
        check(p.fieldValues.count===2.5&&p.fieldValues.enabled===true,'native result types');
        check(p.fieldValues.unknown.values.join(',')==='Café,🐼','unknown result data');
        """#)), Comment(rawValue: runner.message ?? ""))
    }

    @Test func showAcceptsTheImplicitContinueButtonWhenNoButtonsWereAdded() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": [:] as [String: Any]]])
        defer { withExtendedLifetime(host) {} }
        #expect(runner.run(action("const p=new Prompt();check(p.show()===true,'implicit button');check(p.buttonPressed==='Continue','Continue result');check(Object.keys(p.fieldValues).length===0,'empty dictionary');")), Comment(rawValue: runner.message ?? ""))
    }

    @Test func showCancellationKeepsPreviouslyPublishedValuesAndButton() throws {
        for cancelled in [nil, false] as [Any?] {
            let (_, host, runner) = try setup([["index": 0, "fields": ["value": "Previous 🐼"]], cancelled])
            defer { withExtendedLifetime(host) {} }
            #expect(runner.run(action("""
            const p=new Prompt();p.addButton('Use',42);check(p.show()===true,'initial success');
            const previous=p.fieldValues;check(p.show()===false,'cancel result');
            check(p.fieldValues===previous&&p.fieldValues.value==='Previous 🐼','previous fields retained');
            check(p.buttonPressed===42,'previous button retained');
            """)), Comment(rawValue: runner.message ?? ""))
        }
    }

    @Test func showRejectsMalformedResponsesWithoutChangingPublishedResults() throws {
        let fields: [String: Any] = [:]
        let malformed: [(String, Any)] = [
            ("true", true), ("zero", 0), ("empty string", ""), ("string", "response"),
            ("array", [] as [Any]), ("empty object", [:] as [String: Any]),
            ("negative index", ["index": -1, "fields": fields]),
            ("past final button", ["index": 1, "fields": fields]),
            ("fractional index", ["index": 0.5, "fields": fields]),
            ("string index", ["index": "0", "fields": fields]),
            ("boolean index", ["index": true, "fields": fields]),
            ("null index", ["index": NSNull(), "fields": fields]),
            ("missing index", ["fields": fields]), ("missing fields", ["index": 0]),
            ("null fields", ["index": 0, "fields": NSNull()]),
            ("array fields", ["index": 0, "fields": [] as [Any]]),
            ("boolean fields", ["index": 0, "fields": false]),
            ("string fields", ["index": 0, "fields": "bad"]),
            ("numeric fields", ["index": 0, "fields": 2])
        ]
        for (label, response) in malformed {
            let (_, host, runner) = try setup([["index": 0, "fields": ["value": "Previous 🐼"]], response])
            defer { withExtendedLifetime(host) {} }
            #expect(runner.run(action("""
            const p=new Prompt();p.addButton('Use',42);check(p.show()===true,'initial success');
            const previous=p.fieldValues;let rejected=false;
            try{p.show();}catch(error){rejected=error instanceof Error&&error.message.includes('invalid response');}
            check(rejected,'malformed response rejected');
            check(p.fieldValues===previous&&p.fieldValues.value==='Previous 🐼','published fields unchanged');
            check(p.buttonPressed===42,'published button unchanged');
            """)), Comment(rawValue: label + ": " + (runner.message ?? "")))
        }
    }

    @Test func anUncaughtMalformedResponseStopsLaterStatementsAndSteps() throws {
        let (library, host, runner) = try setup([["index": 99, "fields": [:] as [String: Any]]])
        var value = action("const p=new Prompt();p.addButton('Use');p.show();app.setClipboard('Must not run');")
        value.steps.append(ActionStep("createDraft", ["template": "Must not exist"]))
        #expect(!runner.run(value))
        #expect(runner.message?.contains("invalid response") == true)
        #expect(host.clipboard.isEmpty)
        #expect(library.notes.count == 1)
        #expect(library.runs.first?.status == "Error")
    }

    @Test func addTextFieldKeepsRequiredArgumentsAndUnknownOptionsAndReturnsVoid() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": ["text": "Initial 🐼"]]])
        #expect(runner.run(action("const p=new Prompt();check(p.addTextField('text','Text','Initial 🐼',{...options(),placeholder:'Hint',autocorrect:false})===undefined,'void');p.show();")), Comment(rawValue: runner.message ?? ""))
        let value = try field(host, named: "text")
        #expect(value["label"] as? String == "Text" && value["kind"] as? String == "text")
        #expect(value["value"] as? String == "Initial 🐼")
        #expect(value["placeholder"] as? String == "Hint" && value["autocorrect"] as? Bool == false)
    }

    @Test func addTextViewKeepsRequiredArgumentsAndUnknownOptionsAndReturnsVoid() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": ["body": "Initial\n🐼"]]])
        #expect(runner.run(action(#"""
        const p=new Prompt();check(p.addTextView('body','Body','Initial\n🐼',{...options(),height:180,wantsFocus:true})===undefined,'void');p.show();
        """#)), Comment(rawValue: runner.message ?? ""))
        let value = try field(host, named: "body")
        #expect(value["label"] as? String == "Body" && value["kind"] as? String == "textView")
        #expect(value["value"] as? String == "Initial\n🐼")
        #expect(value["height"] as? Int == 180 && value["wantsFocus"] as? Bool == true)
    }

    @Test func addNumberFieldKeepsItsExplicitDecimalPolicyAndReturnsVoid() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": ["count": 2]]])
        #expect(runner.run(action("const p=new Prompt();check(p.addNumberField('count','Count',2,false,{...options(),allowDecimals:true,placeholder:'Count'})===undefined,'void');p.show();")), Comment(rawValue: runner.message ?? ""))
        let value = try field(host, named: "count")
        #expect(value["label"] as? String == "Count" && value["kind"] as? String == "number")
        #expect(value["value"] as? Int == 2 && value["allowDecimals"] as? Bool == false)
        #expect(value["placeholder"] as? String == "Count")
    }

    @Test func addDatePickerKeepsItsInitialDateAndUnknownOptionsAndReturnsVoid() throws {
        let date = "2020-01-02T03:04:05.000Z"
        let (_, host, runner) = try setup([["index": 0, "fields": ["date": date]]])
        #expect(runner.run(action("const p=new Prompt();check(p.addDatePicker('date','Date',new Date('2020-01-02T03:04:05Z'),{...options(),mode:'date',minuteInterval:5})===undefined,'void');check(p.show()&&p.fieldValues.date instanceof Date,'date result');")), Comment(rawValue: runner.message ?? ""))
        let value = try field(host, named: "date")
        #expect(value["label"] as? String == "Date" && value["kind"] as? String == "date")
        #expect(value["value"] as? String == date)
        #expect(value["mode"] as? String == "date" && value["minuteInterval"] as? Int == 5)
    }

    @Test func addLabelKeepsItsIdentityAndUnknownOptionsAndReturnsVoid() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": [:] as [String: Any]]])
        #expect(runner.run(action("const p=new Prompt();check(p.addLabel('label','Information 🐼',{...options(),textSize:'caption'})===undefined,'void');p.show();")), Comment(rawValue: runner.message ?? ""))
        let value = try field(host, named: "label")
        #expect(value["label"] as? String == "Information 🐼" && value["kind"] as? String == "label")
        #expect(value["value"] is NSNull)
        #expect(value["textSize"] as? String == "caption")
    }

    @Test func otherPromptBuildersKeepVoidReturnsAndTheirDocumentedValueKinds() throws {
        let (_, host, runner) = try setup([["index": 0, "fields": [:] as [String: Any]]])
        #expect(runner.run(action("""
        const p=new Prompt();check(p.addButton('Use',42,true,true,'red')===undefined,'button void');
        check(p.addPasswordField('password','Password','secret')===undefined,'password void');
        check(p.addSwitch('toggle','Toggle',true)===undefined,'switch void');
        check(p.addSelect('select','Select',['one','two'],['two'],true)===undefined,'select void');
        check(p.addSegmentedControl('segment','Segment',['one','two'],'two')===undefined,'segment void');
        check(p.addPicker('picker','Picker',[['one','two']],[1])===undefined,'picker void');
        check(p.addDivider()===undefined,'divider void');check(p.show()===true&&p.buttonPressed===42,'button value');
        """)), Comment(rawValue: runner.message ?? ""))
        let fields = try #require(host.prompts.first?["fields"] as? [[String: Any]])
        #expect(fields.compactMap { $0["kind"] as? String } == ["password", "switch", "select", "segment", "picker", "divider"])
        let button = try #require((host.prompts.first?["buttons"] as? [[String: Any]])?.first)
        #expect(button["isDefault"] as? Bool == true && button["isDestructive"] as? Bool == true)
        #expect(button["tintColor"] as? String == "red")
    }
}
