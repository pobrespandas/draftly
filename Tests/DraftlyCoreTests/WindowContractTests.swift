import Foundation
import Testing
@testable import DraftlyCore

@Suite("Window member contracts") @MainActor
struct WindowContractTests {
    @Test(arguments: [false, true])
    func visibilityAndTabAvailabilityAreReadOnlyHostValues(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WindowContractHost())
        let action = makeAPIAction("""
        const w=app.currentWindow;
        for(const key of ['areFiltersVisible','canCreateTab','isActionListVisible','isDraftListVisible','isChatConsoleVisible']){
          const descriptor=Object.getOwnPropertyDescriptor(Window.prototype,key);
          check(typeof descriptor.get==='function'&&descriptor.set===undefined,key+' readonly');
          check(w[key]===false,key+' initial value');
          w[key]=true;
          check(w[key]===false,key+' assignment cannot change host value');
        }
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.count == 10)
        #expect(f.host.calls.allSatisfy { $0["operation"] as? String == "get" })
    }

    @Test(arguments: [false, true])
    func panelCommandsReturnUndefinedAndUpdateSubsequentVisibilityReads(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WindowContractHost())
        let action = makeAPIAction("""
        const w=app.currentWindow;
        for(const [show,hide,key] of [
          ['showFilters','hideFilters','areFiltersVisible'],
          ['showDraftList','hideDraftList','isDraftListVisible'],
          ['showActionList','hideActionList','isActionListVisible']]){
          check(w[show]()===undefined,show+' void result');
          check(w[key]===true,show+' visible');
          check(w[hide]()===undefined,hide+' void result');
          check(w[key]===false,hide+' hidden');
        }
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [false, true])
    func queryAndInfoCommandsForwardArgumentsAndReturnUndefined(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep café 🐼", host: WindowContractHost())
        let action = makeAPIAction("""
        const w=app.currentWindow;
        check(w.showQuickSearch('café 🐼')===undefined,'search void');
        check(w.showCommandPalette('Neutral action')===undefined,'palette void');
        check(w.showDraftInfo(draft)===undefined,'target info void');
        check(w.showDraftInfo()===undefined,'current info void');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.map { $0["operation"] as? String } == ["showQuickSearch", "showCommandPalette", "showDraftInfo", "showDraftInfo"])
        try #require(f.host.calls.count == 4)
        #expect(f.host.calls[0]["value"] as? String == "café 🐼")
        #expect(f.host.calls[1]["value"] as? String == "Neutral action")
        #expect((f.host.calls[2]["value"] as? [String: Any])?["uuid"] as? String == f.editor.noteID?.uuidString)
        #expect(f.host.calls[3]["value"] == nil && f.editor.content == "Keep café 🐼")
    }

    @Test(arguments: [false, true])
    func floatOnTopWritesThroughAndDoesNotChangePanelVisibility(worker: Bool) async throws {
        let f = try ScriptTestFixture(content: "Keep", host: WindowContractHost())
        let action = makeAPIAction("""
        const w=app.currentWindow;
        check(w.floatOnTop===false,'initial floating value');
        w.floatOnTop=true;check(w.floatOnTop===true,'enabled floating value');
        check(w.areFiltersVisible===false,'floating does not show filters');
        w.floatOnTop=false;check(w.floatOnTop===false,'disabled floating value');
        """)
        #expect(await ActionTestExecution.succeeds(action, runner: f.runner, worker: worker),
                Comment(rawValue: f.runner.message ?? ""))
        #expect(f.host.calls.filter { $0["operation"] as? String == "set" }.map { $0["value"] as? Bool } == [true, false])
    }
}

@MainActor private final class WindowContractHost: ActionHost {
    var calls: [[String: Any]] = []
    private var state: [String: Bool] = [:]

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        guard operation == "ui" else { throw DraftlyError.message("Unexpected Window operation: \(operation)") }
        calls.append(values)
        let command = values["operation"] as? String ?? ""
        let key = values["key"] as? String ?? ""
        if command == "get" { return state[key] ?? false }
        if command == "set" { state[key] = values["value"] as? Bool; return true }
        let panels = ["showFilters": "areFiltersVisible", "hideFilters": "areFiltersVisible",
                      "showDraftList": "isDraftListVisible", "hideDraftList": "isDraftListVisible",
                      "showActionList": "isActionListVisible", "hideActionList": "isActionListVisible"]
        if let panel = panels[command] { state[panel] = command.hasPrefix("show") }
        return true
    }
}
