import Foundation
import Testing
@testable import Draftly

@Suite("Native asynchronous routing policies") @MainActor
struct NativeAsyncRoutingTests {
    private let supported: [(operation: String, route: NativeAsyncRoute)] = [
        ("confirmAction", .prompt), ("alert", .prompt), ("prompt", .prompt), ("selectPrompt", .prompt),
        ("callbackURL", .callback), ("shellScript", .shell), ("shortcut", .shortcut), ("eventAPI", .eventAPI),
        ("reminder", .event), ("event", .event), ("location", .location), ("speak", .speech),
        ("transcribe", .transcription), ("modelModes", .model), ("modelRespond", .model), ("appleScript", .appleScript),
        ("dictate", .dictation), ("htmlPreview", .htmlPreview), ("saveFile", .file), ("bookmark", .file),
        ("fileAPI", .file), ("composeMail", .message), ("composeMessage", .message), ("print", .printing),
        ("arrangeText", .arrangement), ("share", .sharing), ("shareFile", .sharing), ("shareURL", .sharing)
    ]

    private let fallback = [
        "readFile", "writeFile", "fileExists", "forgetBookmark", "requireScript",
        "openURL", "clipboard", "unknown", ""
    ]

    @Test func asyncSupportIncludesTheCurrentPromptAndNativeOperationInventory() {
        let host = NativeActionHost()
        #expect(NativePromptAdapter.operations == ["confirmAction", "alert", "prompt", "selectPrompt"])
        for (operation, route) in supported {
            #expect(host.supportsAsync(operation), Comment(rawValue: operation))
            #expect(NativeAsyncRoute.resolve(operation) == route, Comment(rawValue: operation))
        }
    }

    @Test func synchronousAndFallbackNamesAreNotAdvertisedAsAsyncSupport() {
        let host = NativeActionHost()
        for operation in fallback + ["Prompt", "FileAPI", "ModelRespond"] {
            #expect(!host.supportsAsync(operation), Comment(rawValue: operation))
        }
    }

    @Test func malformedAndNonObjectPayloadsFailBeforeSupportedAndFallbackDispatch() async throws {
        let suite = "Draftly-NativeAsyncRouting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Keep", forKey: "unrelated")
        let host = NativeActionHost()
        host.fileDefaults = defaults
        host.testFileRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        for operation in supported.map({ $0.operation }) + fallback {
            for payload in ["[", "[]"] {
                do {
                    _ = try await host.performAsync(operation, payload: payload)
                    Issue.record("Invalid payload reached \(operation) with \(payload).")
                } catch {
                    if payload == "[]" {
                        #expect(error.localizedDescription == "The native operation payload must be an object.",
                            Comment(rawValue: operation))
                    } else {
                        #expect((error as NSError).domain == NSCocoaErrorDomain, Comment(rawValue: operation))
                    }
                }
            }
        }
        #expect(defaults.string(forKey: "unrelated") == "Keep")
        #expect(!FileManager.default.fileExists(atPath: try #require(host.testFileRoot).path))
    }
}
