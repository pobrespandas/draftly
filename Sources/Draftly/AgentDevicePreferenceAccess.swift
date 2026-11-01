import Foundation
import CoreFoundation
import AgentContracts

// Known scalar preferences only. Native registration and resource references use other adapters.
@MainActor enum AgentDevicePreferenceAccess {
    static let supportedIDs: Set<String> = [
        "application.appearance", "application.showInMenuBar", "application.showMainWindowAtLaunch",
        "editor.preferAdvancedFind", "editor.showCustomTouchBar", "application.actionMoveNavigation", "capture.newDraftAfter",
        "editor.fontName", "editor.monospaceFontName", "editor.fontSize", "editor.lineSpacing",
        "editor.lineHeightMultiple", "editor.paragraphSpacing", "editor.horizontalMargin", "editor.verticalMargin", "editor.maximumWidth",
        "editor.typewriter", "editor.highlightInsertionPoint", "editor.focusOnListSelection", "editor.cursorOnListSelection",
        "markdown.processor", "html.strongMark", "html.emphasisMark", "html.ulItemMark", "html.pasteAsMarkdown",
        "html.inlineLinks", "html.linksEachParagraph", "html.ignoreLinks", "html.ignoreImages", "html.ignoreEmphasis"
    ]

    struct Change {
        let storageKey: String
        let value: AgentJSONValue?
    }

    static func read(address item: AgentJSONValue, defaults: UserDefaults) throws -> AgentPreferenceReading {
        let field = try supportedField(item)
        guard let stored = defaults.object(forKey: field.id) else {
            guard let fallback = field.defaultValue else { throw AgentErrorCode.unavailable }
            return AgentPreferenceReading(effectiveValue: fallback, origin: "default", hasOverride: false)
        }
        do {
            let value = try typedValue(stored)
            try field.value.validate(value)
            return AgentPreferenceReading(effectiveValue: value, origin: "stored", hasOverride: true)
        } catch {
            // Keep invalid legacy data. Do not claim that it is a resolved typed value.
            return AgentPreferenceReading(effectiveValue: .null, origin: "invalid", hasOverride: true)
        }
    }

    static func prepare(address item: AgentJSONValue, value: AgentJSONValue?) throws -> Change {
        let field = try supportedField(item)
        guard field.writable else { throw AgentErrorCode.invalidInput }
        if let value { try field.value.validate(value) }
        return Change(storageKey: field.id, value: value)
    }

    private static func supportedField(_ item: AgentJSONValue) throws -> AgentPreferenceField {
        let registry = try AgentPreferenceCatalog.make()
        let address = try registry.address(item)
        let field = try registry.field(address.id)
        guard supportedIDs.contains(field.id), case .device = field.context else { throw AgentErrorCode.unavailable }
        return field
    }

    private static func typedValue(_ value: Any) throws -> AgentJSONValue {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            guard let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
                  !decimal.isNaN else { throw AgentErrorCode.invalidInput }
            return .number(decimal)
        }
        if let text = value as? String { return .string(text) }
        throw AgentErrorCode.invalidInput
    }
}
