import Foundation
import Testing
@testable import DraftlyCore

@Suite("Theme installation links")
struct ThemeInstallationTests {
    private func link(_ items: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = "draftly"; components.host = "theme"; components.queryItems = items
        return try #require(components.url)
    }

    private func theme() -> EditorThemeDefinition {
        EditorThemeDefinition(id: UUID(uuidString: "BBBF0026-0000-4000-8000-000000000001")!,
            name: "Neutral café 🐼 & ? % #\nTheme", foreground: "E1E2E3", background: "102030", heading: "44DDAA", isDark: true,
            unknownFields: ["future": .object(["values": .array([.bool(false), .null, .number(12.25), .string("café 🐼 &?%#\n")])]),
                            "draftsSource": .object(["name": .string("Original name"), "unknownScope": .object(["keep": .bool(true)])])])
    }

    @Test func customLinkPreservesIdentityColorsUnicodeAndUnknownSourceWithoutChangingItsValue() throws {
        let original = theme()
        let installation = ThemeInstallation.custom(original)
        let url = try installation.url
        #expect(url.scheme == "draftly" && url.host == "theme")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.map(\.name) == ["type", "data"])
        #expect(components.queryItems?.first?.value == "custom")
        let text = try #require(components.queryItems?.last?.value)
        #expect(try JSONDecoder().decode(EditorThemeDefinition.self, from: Data(text.utf8)) == original)
        #expect(try ThemeInstallation(url: url) == installation)
        #expect(try installation.url == url)
        #expect(original == theme())
    }

    @Test func builtInLinksAreTypedAndLegacyNameOnlyLinksResolveExactly() throws {
        for name in ThemeCatalog.builtInNames {
            let installation = ThemeInstallation.builtIn(name)
            let url = try installation.url
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(items == [URLQueryItem(name: "type", value: "builtIn"), URLQueryItem(name: "name", value: name)])
            #expect(try ThemeInstallation(url: url) == installation)
            #expect(try ThemeInstallation(url: link([URLQueryItem(name: "name", value: name)])) == installation)
        }
        for name in ["", "dark", "Dark ", " Dark", "D", "Custom only"] {
            #expect(throws: (any Error).self) { try ThemeInstallation.builtIn(name).url }
            #expect(throws: (any Error).self) { try ThemeInstallation(url: link([URLQueryItem(name: "name", value: name)])) }
        }
    }

    @Test func malformedAddressOrQueryCannotSelectOrImportATheme() throws {
        for text in ["https://theme?name=Dark", "draftly://action?name=Dark", "draftly://theme/other?name=Dark",
                     "draftly://user@theme?name=Dark", "draftly://theme:1234?name=Dark", "draftly://theme?name=Dark#fragment"] {
            #expect(throws: (any Error).self) { try ThemeInstallation(url: #require(URL(string: text))) }
        }
        let invalidItems: [[URLQueryItem]] = [
            [], [.init(name: "name", value: nil)], [.init(name: "data", value: "{}")],
            [.init(name: "name", value: "Dark"), .init(name: "data", value: "{}")],
            [.init(name: "type", value: "builtIn"), .init(name: "data", value: "{}")],
            [.init(name: "type", value: "custom"), .init(name: "name", value: "Dark")],
            [.init(name: "type", value: "unknown"), .init(name: "name", value: "Dark")],
            [.init(name: "type", value: "custom"), .init(name: "data", value: "{}"), .init(name: "name", value: "Dark")],
            [.init(name: "name", value: "Dark"), .init(name: "future", value: "ignored")],
            [.init(name: "name", value: "Dark"), .init(name: "name", value: "Light")],
            [.init(name: "type", value: "custom"), .init(name: "type", value: "builtIn"), .init(name: "data", value: "{}")],
            [.init(name: "type", value: "custom"), .init(name: "data", value: "{}"), .init(name: "data", value: "{}")]
        ]
        for items in invalidItems {
            #expect(throws: (any Error).self) { try ThemeInstallation(url: link(items)) }
        }
    }

    @Test func customPayloadRequiresNativeIdentityFieldsAndValidColorsBeforeInstallation() throws {
        let original = theme()
        let data = try JSONEncoder().encode(original)
        let dictionary = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var invalid: [[String: Any]] = []
        for key in ["id", "name", "foreground", "background", "heading", "isDark"] {
            var value = dictionary; value.removeValue(forKey: key); invalid.append(value)
        }
        for (key, value) in [("id", "invalid"), ("name", "System"), ("name", " \n"), ("foreground", "GGGGGG"),
                             ("background", "FFF"), ("heading", "red")] {
            var object = dictionary; object[key] = value; invalid.append(object)
        }
        var wrongType = dictionary; wrongType["isDark"] = "true"; invalid.append(wrongType)
        for object in invalid {
            let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            #expect(throws: (any Error).self) {
                try ThemeInstallation(url: link([.init(name: "type", value: "custom"), .init(name: "data", value: text)]))
            }
        }
        for text in ["invalid JSON", "[]", "false", "null"] {
            #expect(throws: (any Error).self) {
                try ThemeInstallation(url: link([.init(name: "type", value: "custom"), .init(name: "data", value: text)]))
            }
        }
        var invalidValue = original; invalidValue.background = "blue"
        #expect(throws: (any Error).self) { try ThemeInstallation.custom(invalidValue).url }
    }

    @Test func fileReferencesCannotExposeLocalAccessThroughAnInstallationLink() throws {
        do {
            _ = try ThemeInstallation(url: link([.init(name: "type", value: "file"), .init(name: "name", value: "Neutral")]))
            Issue.record("A file theme link was accepted without file support.")
        } catch { #expect(error.localizedDescription == "Theme links must contain a portable custom definition.") }
    }
}
