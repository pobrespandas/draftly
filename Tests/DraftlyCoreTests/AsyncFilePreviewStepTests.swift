import Foundation
import Testing
@testable import DraftlyCore

@Suite("Async file preview and message steps") @MainActor
struct AsyncFilePreviewStepTests {
    @Test func fileStepRendersTheDestinationAndPreservesWriteOptions() async throws {
        let f = try ScriptTestFixture(content: "Title\nBody 🐼", host: FilePreviewStepHost())
        let step = ActionStep("file", ["fileNameTemplate": "[[title]].md", "useBookmark": "true", "bookmarkName": "Neutral", "folderTemplate": "Folder/[[title]]", "writeType": "append"])
        let report = await f.runner.runAsync(DraftAction(name: "File", steps: [step]))
        #expect(report.reason == .success && f.host.calls == ["saveFile"])
        let values = try #require(f.host.payloads.first)
        #expect(values["name"] as? String == "Title.md")
        #expect(values["folder"] as? String == "Folder/Title")
        #expect(values["bookmark"] as? String == "Neutral" && values["mode"] as? String == "append")
        #expect(values["text"] as? String == "Title\nBody 🐼")
    }

    @Test(arguments: ["markdown", "plainText", "html"])
    func printRendersItsFormatBeforeNativeReview(format: String) async throws {
        let host = FilePreviewStepHost()
        let text = "# Title café 🐼\n\n**Bold**"
        let f = try ScriptTestFixture(content: text, host: host)
        let step = ActionStep("print", ["format": format, "template": "[[draft]]", "topMargin": "20"])
        let report = await f.runner.runAsync(DraftAction(name: "Print", steps: [step]))
        #expect(report.reason == .success && host.calls == ["print"])
        let values = try #require(host.payloads.first)
        #expect(values["format"] as? String == (format == "markdown" ? "html" : format))
        #expect(values["topMargin"] as? String == "20")
        let body = try #require(values["text"] as? String)
        if format == "markdown" {
            #expect(body.contains("<h1") && body.contains("<strong>Bold</strong>"))
            #expect(body.contains("café 🐼"))
        } else { #expect(body == text) }
    }

    @Test(arguments: ["replace", "append", "prepend"])
    func clipboardReadsOnlyWhenNeededAndWritesTheResolvedText(mode: String) async throws {
        let host = FilePreviewStepHost()
        host.clipboard = "Before 🐼"
        let f = try ScriptTestFixture(content: "New café", host: host)
        let step = ActionStep("clipboard", ["template": "[[draft]]", "writeType": mode])
        #expect(await f.runner.runAsync(DraftAction(name: "Copy", steps: [step])).reason == .success)
        #expect(host.calls == (mode == "replace" ? ["clipboard"] : ["getClipboard", "clipboard"]))
        let expected = mode == "append" ? "Before 🐼New café" : mode == "prepend" ? "New caféBefore 🐼" : "New café"
        #expect(host.payloads.last?["text"] as? String == expected)
    }

    @Test(arguments: ["html", "richText"])
    func richClipboardReviewsRenderedHTML(output: String) async throws {
        let host = FilePreviewStepHost()
        let f = try ScriptTestFixture(content: "**café 🐼**", host: host)
        let step = ActionStep("clipboard", ["output": output, "template": "[[draft]]"])
        #expect(await f.runner.runAsync(DraftAction(name: "Copy HTML", steps: [step])).reason == .success)
        #expect(host.calls == ["htmlToClipboard"])
        #expect((host.payloads.first?["html"] as? String)?.contains("<strong>café 🐼</strong>") == true)
    }

    @Test func malformedClipboardReadCannotOverwriteTheClipboard() async throws {
        let host = FilePreviewStepHost()
        let f = try ScriptTestFixture(content: "New", host: host)
        let step = ActionStep("clipboard", ["writeType": "append"])
        #expect(await f.runner.runAsync(DraftAction(name: "Append", steps: [step])).reason == .error)
        #expect(host.calls == ["getClipboard"])
    }

    @Test func clipboardFailureStopsFollowingSteps() async throws {
        let host = FilePreviewStepHost(); host.response = #"{"value":false}"#
        let f = try ScriptTestFixture(content: "Keep", host: host)
        let action = DraftAction(name: "Copy", steps: [ActionStep("clipboard"), ActionStep("insertText", ["template": "Late"])])
        #expect(await f.runner.runAsync(action).reason == .cancelled)
        #expect(f.editor.content == "Keep")
    }

    @Test(arguments: [true, false])
    func linksReviewTheEncodedDestinationAndStopOnFailure(accepted: Bool) async throws {
        let host = FilePreviewStepHost()
        host.response = accepted ? #"{"value":true}"# : #"{"value":false}"#
        let f = try ScriptTestFixture(content: "café 🐼", host: host)
        let action = DraftAction(name: "Link", steps: [
            ActionStep("url", ["url": "https://example.invalid/search?q=[[draft]]"]),
            ActionStep("insertText", ["template": "Later"])
        ])
        #expect(await f.runner.runAsync(action).reason == (accepted ? .success : .cancelled))
        #expect(host.calls == ["openURL"])
        let raw = try #require(host.payloads.first?["url"] as? String)
        #expect(URLComponents(string: raw)?.queryItems?.first?.value == "café 🐼")
        if !accepted { #expect(f.editor.content == "café 🐼") }
    }

    @Test func exportUsesItsDefaultRenderedName() async throws {
        let f = try ScriptTestFixture(content: "Title\nBody", host: FilePreviewStepHost())
        let report = await f.runner.runAsync(DraftAction(name: "Export", steps: [ActionStep("export")]))
        #expect(report.reason == .success && f.host.calls == ["saveFile"])
        #expect(f.host.payloads.first?["name"] as? String == "Title.txt")
    }

    @Test func htmlStepSharesReturnedFieldsWithItsFollowingScript() async throws {
        let host = FilePreviewStepHost()
        host.response = #"{"value":{"success":true,"values":{"text":"café 🐼","empty":null}}}"#
        let f = try ScriptTestFixture(content: "# Title", host: host)
        let report = await f.runner.runAsync(DraftAction(name: "HTML", steps: [
            ActionStep("htmlpreview", ["hideInterface": "true"]),
            ActionStep("script", ["script": "if(context.previewValues.empty!==null)throw new Error('null lost');editor.setText(context.previewValues.text);"])
        ]))
        #expect(report.reason == .success && f.editor.content == "café 🐼")
        #expect(host.calls == ["htmlPreview"])
        #expect(host.payloads.first?["hideInterface"] as? Bool == true)
        #expect((host.payloads.first?["html"] as? String)?.contains("<h1") == true)
    }

    @Test func cancelledPreviewStopsTheNextStepAndSuccessEffects() async throws {
        let host = FilePreviewStepHost()
        host.response = #"{"value":{"success":false,"values":{"text":"Not accepted"}}}"#
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = DraftAction(name: "Cancel preview", steps: [ActionStep("htmlpreview"), ActionStep("insertText", ["template": "Late"])])
        action.afterSuccess = "archive"
        #expect(await f.runner.runAsync(action).reason == .cancelled)
        #expect(f.editor.content == "Keep" && f.library.notes.first?.isArchived == false)
    }

    @Test(arguments: ["print", "share", "openIn"])
    func cancelledNativeOutputStopsStepsAndSuccessEffects(type: String) async throws {
        let host = FilePreviewStepHost()
        host.response = #"{"value":false}"#
        let f = try ScriptTestFixture(content: "Keep 🐼", host: host)
        var action = DraftAction(name: "Cancel output", steps: [ActionStep(type), ActionStep("insertText", ["template": "Late"])])
        action.afterSuccess = "archive"
        #expect(await f.runner.runAsync(action).reason == .cancelled)
        #expect(host.calls == [type == "openIn" ? "shareFile" : type])
        #expect(host.payloads.first?["text"] as? String == "Keep 🐼")
        #expect(f.editor.content == "Keep 🐼" && f.library.notes.first?.isArchived == false)
    }

    @Test(arguments: ["mail", "message"], ["sent", "userCancelled"])
    func messageStepsRespectTheNativeOutcome(type: String, status: String) async throws {
        let host = FilePreviewStepHost()
        host.response = #"{"value":{"status":"\#(status)"}}"#
        let f = try ScriptTestFixture(content: "Keep", host: host)
        var action = DraftAction(name: "Compose", steps: [ActionStep(type, ["toRecipients": "first@example.invalid, second@example.invalid", "subject": "[[title]]"]), ActionStep("insertText", ["template": "Accepted"])])
        action.afterSuccess = "archive"
        let report = await f.runner.runAsync(action)
        #expect(report.reason == (status == "sent" ? .success : .cancelled))
        #expect(host.calls == [type == "mail" ? "composeMail" : "composeMessage"])
        #expect(host.payloads.first?["toRecipients"] as? [String] == ["first@example.invalid", "second@example.invalid"])
        #expect(host.payloads.first?["subject"] as? String == "Keep")
        #expect(f.library.notes.first?.isArchived == (status == "sent"))
        if status == "userCancelled" { #expect(f.editor.content == "Keep") }
    }
}

@MainActor private final class FilePreviewStepHost: ActionHost {
    var calls: [String] = []
    var payloads: [[String: Any]] = []
    var clipboard: String?
    var response = #"{"value":true}"#
    func supportsAsync(_ operation: String) -> Bool { ["saveFile", "htmlPreview", "composeMail", "composeMessage", "print", "share", "shareFile"].contains(operation) }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        Issue.record("The synchronous native host ran."); return nil
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        calls.append(operation)
        payloads.append(try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] ?? [:])
        await Task.yield()
        if operation == "getClipboard", let clipboard {
            return String(decoding: try JSONSerialization.data(withJSONObject: ["value": clipboard]), as: UTF8.self)
        }
        return response
    }
}
