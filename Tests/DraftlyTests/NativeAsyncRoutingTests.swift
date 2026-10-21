import Foundation
import Testing
@testable import Draftly

@Suite("Native asynchronous routing policies") @MainActor
struct NativeAsyncRoutingTests {
    private let supported = [
        "confirmAction", "alert", "prompt", "selectPrompt",
        "callbackURL", "shellScript", "shortcut", "eventAPI", "reminder", "event",
        "location", "speak", "transcribe", "modelModes", "modelRespond", "appleScript",
        "dictate", "htmlPreview", "saveFile", "bookmark", "fileAPI", "composeMail",
        "composeMessage", "print", "arrangeText", "share", "shareFile", "shareURL"
    ]

    private let fallback = [
        "readFile", "writeFile", "fileExists", "forgetBookmark", "requireScript",
        "openURL", "clipboard", "unknown", ""
    ]

    @Test func asyncSupportIncludesTheCurrentPromptAndNativeOperationInventory() {
        let host = NativeActionHost()
        #expect(NativePromptAdapter.operations == ["confirmAction", "alert", "prompt", "selectPrompt"])
        for operation in supported {
            #expect(host.supportsAsync(operation), Comment(rawValue: operation))
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
        for operation in supported + fallback {
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
