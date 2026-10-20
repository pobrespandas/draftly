import Foundation
import Testing
@testable import DraftlyCore

@Suite("Worker Mustache contracts") @MainActor
struct MustacheWorkerTests {
    private func worker() -> ActionScriptWorker {
        ActionScriptWorker(executionID: UUID(), stepID: UUID(), hostTimeout: 1) { request in
            if request.operation == "device" { return "{\"value\":{}}" }
            return "{\"error\":\"Template rendering must stay on the script worker.\"}"
        }
    }

    @Test func renderingUsesTheWorkerContextWithoutAHostRequest() async throws {
        let worker = worker()
        try await worker.start("")
        do {
            let result = try await worker.run(source: #"""
            const t=MustacheTemplate.createWithTemplate('{{name}}|{{#items}}{{value}};{{/items}}');
            if(t.render({name:'<Café 🐼>',items:[{value:'one'},{value:'two'}]})!=='&lt;Café 🐼&gt;|one;two;')throw new Error('HTML output');
            t.contentType='text';if(t.render({name:'<Café 🐼>',items:[]})!=='<Café 🐼>|')throw new Error('text output');
            if(MustacheTemplate.renderTemplate('{{>line}}',{label:'café 🐼'},{line:'{{label}}'})!=='café 🐼')throw new Error('partial');
            if(MustacheTemplate.createWithTemplate('{{date}}').render({date:new Date('2020-01-01T00:00:00Z')})!=='2020-01-01T00:00:00.000Z')throw new Error('date compatibility');
            """#, stepID: UUID(), asynchronous: false, timeout: 1, synchronousTimeout: 1)
            #expect(result)
            await worker.close()
        } catch {
            await worker.close()
            throw error
        }
    }

    @Test func renderingUsesTheScriptDeadlineAndDoesNotPoisonTheNextStep() async throws {
        let worker = worker()
        try await worker.start("var load={items:Array(2000).fill({value:'x'})};var renderCount=0;var originalEscape=Mustache.escape;Mustache.escape=function(v){renderCount++;return originalEscape(v)};")
        var termination: ActionExecutionInterruption?
        do {
            _ = try await worker.run(source: "MustacheTemplate.createWithTemplate('{{#items}}{{#items}}{{value}}{{/items}}{{/items}}').render(load);", stepID: UUID(), asynchronous: false, timeout: 1, synchronousTimeout: 0.05)
        } catch { termination = error as? ActionExecutionInterruption }
        #expect(termination == .timeout)
        do {
            let next = try await worker.run(source: "if(renderCount===0)throw new Error('render was not entered');if(MustacheTemplate.createWithTemplate('{{value}}').render({value:'Next café 🐼'})!=='Next café 🐼')throw new Error('late state');", stepID: UUID(), asynchronous: false, timeout: 1, synchronousTimeout: 1)
            #expect(next)
            await worker.close()
        } catch {
            await worker.close()
            throw error
        }
    }
}
