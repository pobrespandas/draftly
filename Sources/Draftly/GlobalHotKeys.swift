import AppKit
import Carbon
import DraftlyCore

@MainActor
final class GlobalHotKeys {
    static let signature: OSType = 0x44524654
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var handlerStatus: OSStatus = noErr
    private var identities = GlobalHotKeyIdentity()
    var perform: (String) -> Void
    var changed: ([String: String]) -> Void

    init(perform: @escaping (String) -> Void, changed: @escaping ([String: String]) -> Void) {
        self.perform = perform
        self.changed = changed
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var identity = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identity) == noErr,
                  identity.signature == GlobalHotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let id = identity.id
            Task { @MainActor in AppDelegate.current?.dispatchGlobalShortcut(id) }
            return noErr
        }, 1, &type, nil, &handler)
    }

    func reload(configuration: String, actions: [DraftAction]) {
        suspend()
        var errors: [String: String] = [:]
        guard handler != nil else {
            for name in GlobalShortcuts.names where !CommandShortcuts.binding(name, configuration: configuration).key.isEmpty {
                errors[name] = "Global shortcut handler unavailable (\(handlerStatus))."
            }
            changed(errors)
            return
        }
        for name in GlobalShortcuts.names {
            let binding = CommandShortcuts.binding(name, configuration: configuration)
            guard !binding.key.isEmpty else { continue }
            if let error = GlobalShortcuts.conflict(name: name, binding: binding, configuration: configuration, actions: actions) {
                errors[name] = error
                continue
            }
            guard let keyCode = binding.keyCode ?? Self.legacyKeyCode(binding.key) else {
                errors[name] = "Record this shortcut to identify its keyboard key."
                continue
            }
            guard let id = identities.allocate() else {
                errors[name] = "Global shortcut identities are exhausted. Restart Draftly."
                continue
            }
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(keyCode, Self.carbonModifiers(binding.modifiers),
                EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference {
                registrations.append(reference)
                identities.register(id, name: name)
            } else { errors[name] = "Shortcut unavailable (\(result)). Choose another shortcut." }
        }
        changed(errors)
    }

    func dispatch(_ id: UInt32) {
        guard let name = identities.name(for: id) else { return }
        perform(name)
    }

    func suspend() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        identities.invalidate()
    }

    func stop() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        identities.invalidate()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    static func carbonModifiers(_ modifiers: [String]) -> UInt32 {
        let values = Set(modifiers)
        return (values.contains("command") ? UInt32(cmdKey) : 0)
            | (values.contains("option") ? UInt32(optionKey) : 0)
            | (values.contains("control") ? UInt32(controlKey) : 0)
            | (values.contains("shift") ? UInt32(shiftKey) : 0)
    }

    static func legacyKeyCode(_ key: String) -> UInt32? {
        // Keep earlier bindings compatible. Recorded bindings use their physical key.
        let codes: [String: UInt32] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
            "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
            "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
            "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
            "/": 44, "n": 45, "m": 46, ".": 47, "`": 50]
        return codes[key.lowercased()]
    }
}
