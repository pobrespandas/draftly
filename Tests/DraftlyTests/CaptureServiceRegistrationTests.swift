import AppKit
import Foundation
import Testing
@testable import Draftly

@Suite("Capture service registration") @MainActor
struct CaptureServiceRegistrationTests {
    @Test func bothServiceEntriesResolveToImplementedSelectors() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Configuration/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let services = try #require(plist["NSServices"] as? [[String: Any]])
        #expect(services.count == 2)
        let delegate = AppDelegate()
        var names: [String] = []
        for service in services {
            let message = try #require(service["NSMessage"] as? String)
            let title = try #require((service["NSMenuItem"] as? [String: String])?["default"])
            names.append(title)
            #expect(delegate.responds(to: NSSelectorFromString(message + ":userData:error:")))
            let types = try #require(service["NSSendTypes"] as? [String])
            #expect(types.contains("public.utf8-plain-text"))
            #expect(types.contains("public.rtf"))
            #expect(types.contains("com.apple.flat-rtfd"))
            #expect(types.contains("public.url"))
        }
        #expect(names == ["Capture to Draftly", "Capture to Draftly with Options"])
    }

    @Test func selectorsRouteDirectOptionsAndLegacyRequestsWithoutChangingTheInput() {
        var saved: [String] = [], shown: [String] = []
        let delegate = AppDelegate()
        delegate.captureService = CaptureService(save: { saved.append($0) }, showOptions: { shown.append($0) })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Selected 🐼\r\nCafé", forType: .string)
        let originalChangeCount = pasteboard.changeCount
        var error: NSString?
        delegate.captureSelectionDirectly(pasteboard, userData: nil, error: &error)
        #expect(error == nil && saved == ["Selected 🐼\r\nCafé"] && shown.isEmpty)
        delegate.captureSelectionWithOptions(pasteboard, userData: nil, error: &error)
        delegate.captureSelection(pasteboard, userData: nil, error: &error)
        #expect(error == nil && shown == ["Selected 🐼\r\nCafé", "Selected 🐼\r\nCafé"])
        #expect(saved.count == 1)
        #expect(pasteboard.changeCount == originalChangeCount)
        #expect(pasteboard.string(forType: .string) == "Selected 🐼\r\nCafé")
    }

    @Test func serviceWriteErrorsReachTheCallerWithoutOpeningOptions() {
        let delegate = AppDelegate()
        var shown = false
        delegate.captureService = CaptureService(save: { _ in throw CocoaError(.fileWriteOutOfSpace) }, showOptions: { _ in shown = true })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Keep this selection", forType: .string)
        var error: NSString?
        delegate.captureSelectionDirectly(pasteboard, userData: nil, error: &error)
        #expect(error != nil && !shown)
        #expect(pasteboard.string(forType: .string) == "Keep this selection")
    }
}
